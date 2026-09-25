extends RedlineTestCase
## M8 T05: NPC arcs (NpcArc/ArcTracker, pick order, the Orr choice in the
## DialogueBox, the pending tick, the journal PEOPLE page) and the five
## Act I arcs (design_arcs A3 as amended by the M8 plan).

const RELAY := "res://world/rooms/lowlight/Relay.tscn"
const SAVE_V3 := "res://tests/fixtures/save_v3_slice.json"
const TEST_SAVE_DIR := "user://test_npc_arcs"
const NPCS := ["mara", "vell", "nix", "orr", "iko"]

var menus: Array[StringName] = []
var entered: Array = []
var choices_made: Array = []
var choice_ms: Array[int] = []
var hints: Array = []
var _box: Variant = null
var _root: Node2D = null
var _extras: Array[Node] = []
var _pad_was: bool = false


func before_each() -> void:
	_pad_was = InputGlyphs.using_pad
	InputGlyphs.using_pad = false
	SaveManager.save_dir = TEST_SAVE_DIR
	Game.new_game()
	menus.clear()
	entered.clear()
	choices_made.clear()
	choice_ms.clear()
	hints.clear()
	EventBus.menu_requested.connect(_on_menu)
	EventBus.arc_stage_entered.connect(_on_arc)
	EventBus.dialogue_choice_made.connect(_on_choice)
	EventBus.hint_requested.connect(_on_hint)


func after_each() -> void:
	EventBus.menu_requested.disconnect(_on_menu)
	EventBus.arc_stage_entered.disconnect(_on_arc)
	EventBus.dialogue_choice_made.disconnect(_on_choice)
	EventBus.hint_requested.disconnect(_on_hint)
	for a in [&"jump", &"interact", &"ui_accept", &"move_up", &"move_down", &"ui_up", &"ui_down", &"attack_light"]:
		Input.action_release(a)
	InputGlyphs.using_pad = _pad_was
	if _box != null and is_instance_valid(_box):
		_box.queue_free()
	_box = null
	for n in _extras:
		if is_instance_valid(n):
			n.queue_free()
	_extras.clear()
	if _root != null:
		SceneRouter.current_room = null
		SceneRouter.world_root = null
		_root.queue_free()
		_root = null
	get_tree().paused = false
	if DirAccess.dir_exists_absolute(TEST_SAVE_DIR):
		for f in DirAccess.get_files_at(TEST_SAVE_DIR):
			DirAccess.remove_absolute("%s/%s" % [TEST_SAVE_DIR, f])
	SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR
	Game.new_game()
	await physics_frames(2)


func _on_menu(id: StringName) -> void:
	menus.append(id)


func _on_arc(npc: String, stage: String, on_load: bool) -> void:
	entered.append([npc, stage, on_load])


func _on_choice(dialogue_id: String, choice_id: String) -> void:
	choices_made.append([dialogue_id, choice_id])
	choice_ms.append(Time.get_ticks_msec())


func _on_hint(text: String, _s: float) -> void:
	hints.append(text)


# --- helpers ---

func _p(npc: String) -> NpcProfile:
	return load("res://data/npcs/%s.tres" % npc)


func _arc(npc: String) -> NpcArc:
	return load("res://data/arcs/arc_%s.tres" % npc)


## One talk as NPC.interact does it (count first, then pick), effects applied
## as DialogueBox._close would (choice 0 for a choice beat, like advance()).
func _talk(npc: String, choice: int = -1) -> String:
	var talks := "talks_%s" % npc
	Game.set_flag(talks, Game.flag_int(talks) + 1)
	var d := _p(npc).pick_dialogue()
	if d == null:
		return "<none>"
	Game.apply_dialogue(d, choice if choice >= 0 or d.choices.is_empty() else 0)
	return d.id


func _remember(id: String) -> void:
	MemoryLibrary.mark_seen(id)


func _on_air() -> DialogueData:
	return _arc("orr").stage("on_air").beat_rules[0].dialogue


func _new_box() -> Variant:
	_box = load("res://ui/dialogue/DialogueBox.gd").new()
	add_child(_box)
	return _box


## Opens `d` in a fresh box, then advances to its choice mode (last line
## fully typed, then advance()).
func _box_at_choice(d: DialogueData) -> Variant:
	var box = _new_box()
	box.open(d, "Orr")
	for i in d.lines.size():
		box.advance()
	return box


## Real milliseconds pass (the arm time is real time; headless fixed-fps
## frames run faster than real time).
func _wait_real_ms(ms: int) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < ms:
		await get_tree().process_frame


func _close_box(box: Variant, max_steps: int = 12) -> void:
	var n := 0
	while box.is_open() and n < max_steps:
		box.advance()
		n += 1
	check(not box.is_open(), "dialogue did not close within %d advances" % max_steps)


# --- framework ---

func test_arc_resources_validate() -> void:
	check(Game.arcs.arcs.size() == 5, "five arcs loaded (got %d)" % Game.arcs.arcs.size())
	for npc: String in NPCS:
		var a := _arc(npc)
		check(a != null and a.npc_id == npc, "arc_%s npc_id" % npc)
		if a == null:
			continue
		check(a.validate().is_empty(), "arc_%s validate: %s" % [npc, ", ".join(a.validate())])
		check(a.content_check().is_empty(), "arc_%s content_check: %s" % [npc, ", ".join(a.content_check())])
		var p := _p(npc)
		check(p.arc == a and p.validate().is_empty(), "%s profile owns arc_%s: %s" % [npc, npc, ", ".join(p.validate())])
		check(Game.arcs.arc(npc) == a, "tracker holds the same arc_%s" % npc)
	var owners := 0
	for path in DataDir.list("res://data/npcs"):
		var p := load(path) as NpcProfile
		if p.arc:
			owners += 1
	check(owners == 5, "exactly five profiles own an arc (got %d)" % owners)
	var v := ContentValidator.new()
	for npc: String in NPCS:
		v.check_resource(_arc(npc), "res://data/arcs/arc_%s.tres" % npc)
	check(v.errors.is_empty(), "arcs lint clean: %s" % ", ".join(v.errors))


func test_stages_sticky_and_consequences_once() -> void:
	var counts := {}
	var probe := func(id: String, _v: Variant) -> void:
		if id == "arc_mara_krail" or id == "thread_mara_core":
			counts[id] = int(counts.get(id, 0)) + 1
	EventBus.flag_changed.connect(probe)
	Game.set_flag("met_mara")
	Game.set_flag("warden_krail_defeated")
	check(_talk("mara") == "mara_after_boss", "Krail beat plays")
	Game.state.flags.erase("warden_krail_defeated")
	Game.arcs.evaluate()
	Game.set_flag("warden_krail_defeated")
	Game.arcs.evaluate()
	EventBus.flag_changed.disconnect(probe)
	check(Game.has_flag("arc_mara_krail") and Game.flag_int("arc_mara_stage") == 2, "the Krail stage stays reached")
	check(counts.get("arc_mara_krail", 0) == 1 and counts.get("thread_mara_core", 0) == 1, "each consequence once: %s" % str(counts))
	check(_talk("mara") != "mara_after_boss", "the beat does not replay")
	var krail_entries := entered.filter(func(e: Array) -> bool: return e[0] == "mara" and e[1] == "krail")
	check(krail_entries.size() == 1, "arc_stage_entered once for mara/krail (got %d)" % krail_entries.size())


func test_story_rules_win_over_beats() -> void:
	# Nix: count:secrets:5 reaction pending, but the chart report is a story rule.
	Game.set_flag("met_nix")
	Game.set_flag("quest_chart_started")
	var ids: Array = SliceStats.totals()["secret_ids"]
	for i in 5:
		Game.mark_collected(ids[i])
	Game.set_flag("map_charted_lowlight")
	check(_talk("nix") == "nix_report", "nix_report before nix_scout")
	check(_talk("nix") == "nix_scout", "then the scout beat")
	# Orr: on_air pending, but the repeater report is a story rule.
	Game.set_flag("met_orr")
	Game.set_flag("quest_dead_air_started")
	Game.set_flag("act1_complete")
	for f in ["repeater_market", "repeater_stack", "repeater_bell"]:
		Game.set_flag(f)
	check(_p("orr").pick_dialogue().id == "orr_report", "orr_report before orr_on_air")
	check(_talk("orr") == "orr_report" and _talk("orr") == "orr_on_air", "then the on-air choice")


func test_beats_play_in_story_order() -> void:
	check(_talk("mara") == "mara_intro", "intro first")
	Game.set_flag("memories_remembered", 1)
	Game.set_flag("warden_krail_defeated")
	_remember("mf_lowlight_02")
	var got: Array[String] = []
	for i in 4:
		got.append(_talk("mara"))
	check(got == (["mara_after_boss", "mara_eyes", "mara_seen_one", "mara_idle_told"] as Array[String]), "story order: %s" % str(got))


func test_skipped_beat_still_counts() -> void:
	Game.set_flag("met_mara")
	Game.set_flag("warden_krail_defeated")
	var box = _new_box()
	EventBus.dialogue_requested.emit(_p("mara").pick_dialogue(), "Mara")
	check(box.is_open() and box.dialogue.id == "mara_after_boss", "beat opened")
	_close_box(box)
	check(Game.has_flag("arcbeat_mara_krail") and Game.has_flag("thread_mara_core"), "skipping through still sets the beat and thread")
	check(menus.has(&"shop_mara"), "the beat opens the shop")


func test_old_save_catches_up_quietly() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_SAVE_DIR)
	var raw := FileAccess.get_file_as_string(SAVE_V3)
	var f := FileAccess.open("%s/profile_1.json" % TEST_SAVE_DIR, FileAccess.WRITE)
	f.store_string(raw)
	f.close()
	entered.clear()
	hints.clear()
	check(Game.load_game(1), "fixture loads")
	check(Game.has_flag("arc_orr_met") and Game.flag_int("arc_orr_stage") == 1, "Orr's arc caught up to met (stage %d)" % Game.flag_int("arc_orr_stage"))
	var orr_met := entered.filter(func(e: Array) -> bool: return e[0] == "orr" and e[1] == "met")
	check(orr_met.size() == 1 and orr_met[0][2] == true, "arc_stage_entered on_load: %s" % str(entered))
	check(hints.is_empty(), "no hints on catch-up: %s" % str(hints))
	check(_talk("mara") == "mara_intro", "unmet Mara gives her intro first")
	check(_talk("mara") == "mara_after_boss", "then her Krail beat")


func test_legacy_slice_end_save_gets_on_air() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_SAVE_DIR)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE_V3))
	data["flags"]["slice_end_seen"] = true
	var f := FileAccess.open("%s/profile_1.json" % TEST_SAVE_DIR, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	entered.clear()
	check(Game.load_game(1), "legacy save loads")
	check(Game.has_flag("act1_complete"), "act1_complete derived")
	var on_air := entered.filter(func(e: Array) -> bool: return e[0] == "orr" and e[1] == "on_air")
	check(Game.has_flag("arc_orr_on_air") and on_air.size() == 1 and on_air[0][2] == true, "on_air entered on load: %s" % str(entered))
	var orr_order: Array[String] = []
	for i in 2:
		orr_order.append(_talk("orr"))
	check(orr_order == (["orr_iko", "orr_on_air"] as Array[String]), "story rule, then the choice beat (not an idle): %s" % str(orr_order))
	var legacy := [_talk("mara"), _talk("mara"), _talk("nix"), _talk("nix")]
	# The same world without the legacy derivation path: a fresh game with the
	# same flags set directly.
	Game.new_game()
	for k: String in data["flags"]:
		Game.set_flag(k, data["flags"][k])
	Game.set_flag("act1_complete")
	var fresh := [_talk("mara"), _talk("mara"), _talk("nix"), _talk("nix")]
	check(legacy == fresh, "Mara/Nix order equals the non-legacy run: %s vs %s" % [str(legacy), str(fresh)])


# --- the five Act I arcs ---

func test_mara_arc_act1() -> void:
	Game.start_campaign()
	Game.set_flag("collector_drone_defeated")
	var got: Array[String] = [_talk("mara"), _talk("mara")]
	_remember("mem_first_rest")
	got.append(_talk("mara"))
	Game.set_flag("dead_air_complete")
	got.append(_talk("mara"))
	Game.set_flag("warden_krail_defeated")
	got.append(_talk("mara"))
	check(Game.has_flag("thread_mara_core"), "thread_mara_core after the Krail beat")
	got.append(_talk("mara"))
	_remember("mf_lowlight_02")
	got.append(_talk("mara"))
	check(Game.has_flag("bond_mara_told"), "bond_mara_told after seen_one")
	got.append(_talk("mara"))
	var expected: Array[String] = ["mara_intro_undercity", "mara_shop", "mara_eyes", "mara_idle_radio", "mara_after_boss", "mara_idle_bench", "mara_seen_one", "mara_idle_told"]
	check(got == expected, "Mara: %s" % str(got))
	check(menus.size() == expected.size() and menus.all(func(m: StringName) -> bool: return m == &"shop_mara"), "every Mara talk opens shop_mara: %s" % str(menus))
	check(Game.flag_int("arc_mara_stage") == 2, "Mara spine complete")


func test_vell_arc_act1() -> void:
	var got: Array[String] = [_talk("vell")]
	Game.grant_circuit("longline")
	Game.grant_circuit("rebound")
	got.append(_talk("vell"))
	check(Game.has_flag("bond_vell_regular"), "bond_vell_regular")
	Game.set_flag("dead_air_complete")
	got.append(_talk("vell"))
	Game.set_flag("warden_krail_defeated")
	got.append(_talk("vell"))
	check(Game.has_flag("thread_vell_source"), "thread_vell_source")
	got.append(_talk("vell"))
	got.append(_talk("vell"))
	var expected: Array[String] = ["vell_intro", "vell_customer", "vell_radio", "vell_supply_cut", "vell_asked", "vell_idle_regular"]
	check(got == expected, "Vell: %s" % str(got))
	check(menus.size() == expected.size() and menus.all(func(m: StringName) -> bool: return m == &"shop_vell"), "every Vell talk opens shop_vell: %s" % str(menus))


func test_vell_customer_by_shards() -> void:
	_root = Node2D.new()
	add_child(_root)
	SceneRouter.register_world_root(_root)
	SceneRouter.goto_room("res://tests/fixtures/WorldA.tscn", &"start")
	await physics_frames(3)
	var room := SceneRouter.current_room as Room
	Game.set_flag("met_vell")
	Game.state.core_shards = 1
	var at_pickup: Array = []
	var probe := func(_id: String, _kind: int) -> void:
		at_pickup.append(Game.has_flag("arc_vell_customer"))
	EventBus.collectible_taken.connect(probe)
	var shard := Collectible.new()
	shard.persist_id = "test_arcs_shard"
	shard.kind = Collectible.Kind.CORE_SHARD
	shard.position = Vector2(80, 0)
	room.add_child(shard)
	room.player.teleport(Vector2(80, -2))
	var room_changes := [0]
	var on_room := func(_d: String, _r: String) -> void: room_changes[0] += 1
	EventBus.room_entered.connect(on_room)
	await physics_frames(3)
	EventBus.collectible_taken.disconnect(probe)
	EventBus.room_entered.disconnect(on_room)
	check(Game.state.core_shards == 2, "the shard counted")
	check(at_pickup == [true], "arc_vell_customer entered on the pickup frame: %s" % str(at_pickup))
	check(room_changes[0] == 0, "no room change was needed")
	check(_talk("vell") == "vell_customer", "the customer beat plays")


func test_nix_arc_act1() -> void:
	var got: Array[String] = [_talk("nix")]
	Game.set_flag("talks_nix", 3)
	got.append(_talk("nix"))
	var ids: Array = SliceStats.totals()["secret_ids"]
	for i in 5:
		Game.mark_collected(ids[i])
	got.append(_talk("nix"))
	check(Game.has_flag("bond_nix_scout"), "bond_nix_scout")
	Game.set_flag("map_charted_lowlight")
	got.append(_talk("nix"))
	got.append(_talk("nix"))
	Game.set_flag("warden_krail_defeated")
	got.append(_talk("nix"))
	check(Game.has_flag("arcbeat_nix_krail") and Game.has_flag("thread_nix_maps"), "arcbeat_nix_krail and thread_nix_maps")
	_remember("mf_lowlight_03")
	got.append(_talk("nix"))
	check(Game.has_flag("thread_nix_desk"), "thread_nix_desk")
	got.append(_talk("nix"))
	var expected: Array[String] = ["nix_intro", "nix_regular", "nix_scout", "nix_report", "nix_idle_charted", "nix_tower", "nix_ledger", "nix_idle_scout"]
	check(got == expected, "Nix: %s" % str(got))
	check(menus.size() == expected.size() and menus.all(func(m: StringName) -> bool: return m == &"shop_nix"), "every Nix talk opens shop_nix: %s" % str(menus))


func _orr_arc(choice: int) -> Array[String]:
	var got: Array[String] = [_talk("orr")]
	Game.set_flag("warden_krail_defeated")
	Game.set_flag("met_iko")
	Game.set_flag("act1_complete")
	var d := _p("orr").pick_dialogue()
	check(d.id == "orr_on_air" and d.choices.size() == 2, "the on-air beat offers two answers")
	got.append(_talk("orr", choice))
	check(Game.has_flag("thread_orr_air") and Game.has_flag("arcbeat_orr_on_air"), "thread_orr_air and the beat flag")
	check(Game.has_flag("orr_air_named") != Game.has_flag("orr_air_ghost"), "exactly one answer recorded")
	got.append(_talk("orr"))
	got.append(_talk("orr"))
	_remember("mf_lowlight_04")
	got.append(_talk("orr"))
	check(Game.has_flag("thread_orr_tapcode"), "thread_orr_tapcode")
	return got


func test_orr_arc_act1_named() -> void:
	var got := _orr_arc(0)
	check(Game.has_flag("orr_air_named") and not Game.has_flag("orr_air_ghost"), "named")
	check(got == (["orr_intro", "orr_on_air", "orr_idle_named", "orr_idle_named", "orr_tap_code"] as Array[String]), "Orr named: %s" % str(got))
	var arc := _arc("orr")
	var on_air := arc.stage("on_air").beat_rules[0].dialogue
	check(on_air.lines[0].text == "Krail's patrol band is still dead. Lowlight's already guessing who.", "on_air line 1")
	check(on_air.lines[1].text == "I can tell Lowlight it was you. Or I let them keep guessing. Your call.", "on_air line 2")
	check(on_air.choices[0].label == "Put it on the air." and on_air.choices[1].label == "Let them guess.", "choice labels")
	check(on_air.choices[0].reply[0].text == "Then Lowlight knows it was you. So do the Wardens.", "named reply")
	check(on_air.choices[1].reply[0].text == "A ghost, then. Ghosts get rumors, not posters.", "ghost reply")
	check(arc.stage("on_air").idle_rules[0].dialogue.lines[0].text == "Every Warden band has your description now. Keep moving.", "idle_named line")
	var tap := arc.stage("tap_code").beat_rules[0].dialogue
	check(tap.lines[0].text == "Board picked up tapping on an old pipe line. Three short, three long.", "tap_code line 1")
	check(tap.lines[1].text == "Old crew call sign. Means 'still here'. Haven't heard it in years.", "tap_code line 2")


func test_orr_arc_act1_ghost() -> void:
	var got := _orr_arc(1)
	check(Game.has_flag("orr_air_ghost") and not Game.has_flag("orr_air_named"), "ghost")
	check(got == (["orr_intro", "orr_on_air", "orr_idle_ghost", "orr_idle_ghost", "orr_tap_code"] as Array[String]), "Orr ghost: %s" % str(got))


func test_iko_arc_den_path() -> void:
	var got: Array[String] = [_talk("iko"), _talk("iko")]
	Game.mark_collected("sr_den_cache")
	got.append(_talk("iko"))
	check(Game.has_flag("bond_iko_rent"), "bond_iko_rent")
	Game.set_flag("warden_krail_defeated")
	got.append(_talk("iko"))
	check(Game.has_flag("thread_iko_spire"), "thread_iko_spire")
	got.append(_talk("iko"))
	var expected: Array[String] = ["iko_intro", "iko_relay_den", "iko_rent", "iko_spire_crates", "iko_idle_rent"]
	check(got == expected, "Iko den path: %s" % str(got))
	check(menus.size() == expected.size() and menus.all(func(m: StringName) -> bool: return m == &"shop_iko"), "every Iko talk opens shop_iko: %s" % str(menus))


func test_iko_arc_orr_path() -> void:
	Game.set_flag("warden_krail_defeated")
	Game.set_flag("met_orr")
	check(_talk("orr") == "orr_iko", "Orr mentions Iko")
	check(not Game.has_flag("arc_iko_krail"), "Iko's Krail stage waits for her Relay intro")
	var got: Array[String] = [_talk("iko"), _talk("iko")]
	check(got == (["iko_relay_word", "iko_spire_crates"] as Array[String]), "Iko Orr path: %s" % str(got))


func test_act1_main_path_reaches_spine() -> void:
	Game.start_campaign()
	var relay_visit := func() -> void:
		for npc: String in NPCS:
			# A Relay visit: talk to everyone present until they only repeat.
			if npc == "iko" and not Game.has_flag("met_iko"):
				continue
			for i in 4:
				_talk(npc)
	for f in ["got_pulse_blade", "met_orr_radio", "collector_drone_defeated", "got_service_pistol", "orr_radio_after"]:
		Game.set_flag(f)
	_remember("mem_first_rest")
	relay_visit.call()
	for f in ["lowlight_power_rerouted", "chase_rainline_done"]:
		Game.set_flag(f)
	check(_talk("iko") == "iko_intro", "den meeting with Iko")
	Game.set_flag("warden_krail_defeated")
	Game.set_flag("unlocked_dash")
	Game.set_flag("slice_end_seen")
	Game.set_flag("act1_complete")
	relay_visit.call()
	for a: NpcArc in Game.arcs.arcs:
		for s in a.stages + a.reactions:
			var st := s as NpcArcStage
			if st.optional:
				continue
			check(a.is_reached(st), "%s: %s not reached" % [a.npc_id, st.id])
			if not st.beat_rules.is_empty():
				check(Game.has_flag(a.heard_flag(st.id)), "%s: %s beat not heard" % [a.npc_id, st.id])
		for t in a.threads:
			if t == "thread_nix_desk" or t == "thread_orr_tapcode":
				continue
			check(Game.has_flag(t), "%s: %s not set on the main path" % [a.npc_id, t])


func test_arcs_are_economy_neutral() -> void:
	for npc: String in NPCS:
		for d in _arc(npc).dialogues():
			check(d.give_scrap == 0 and d.give_circuit == "" and d.give_weapon == "", "%s gives items" % d.id)


# --- DialogueBox choice mode ---

func test_dialogue_box_choice_mode() -> void:
	Game.set_flag("met_orr")
	var box = _new_box()
	var d := _on_air()
	EventBus.dialogue_requested.emit(d, "Orr")
	box.advance()
	box.advance()
	check(box.is_choosing(), "choice mode after the last line")
	check(not box.confirm_armed(), "not armed immediately")
	check(get_tree().paused, "the tree stays paused while choosing")
	await press_action(&"ui_down", 2)
	check(box._selected == 1, "ui_down selects the second answer")
	await _wait_real_ms(450)
	check(box.confirm_armed(), "armed after the arm time with nothing held")
	await press_action(&"ui_accept", 2)
	check(choices_made == [["orr_on_air", "ghost"]], "dialogue_choice_made: %s" % str(choices_made))
	check(box.is_open() and not box.is_choosing() and box._current_line().text.begins_with("A ghost"), "the reply shows")
	check(not Game.has_flag("orr_air_ghost"), "effects wait for the close")
	box.advance()
	check(not box.is_open(), "the reply closes the box")
	check(Game.has_flag("orr_air_ghost") and not Game.has_flag("orr_air_named"), "orr_air_ghost set")
	check(not get_tree().paused, "tree unpaused")


func test_advance_loop_picks_default_choice() -> void:
	var box = _new_box()
	var d := _on_air()
	box.open(d, "Orr")
	var limit: int = d.lines.size() + 1 + d.choices[0].reply.size()
	var n := 0
	while box.is_open() and n < limit + 5:
		box.advance()
		n += 1
	check(not box.is_open() and n == limit, "closed after %d advances (limit %d)" % [n, limit])
	check(Game.has_flag("orr_air_named") and Game.has_flag("thread_orr_air") and Game.has_flag("arcbeat_orr_on_air"), "choice 0 flags")
	check(not Game.has_flag("orr_air_ghost"), "only choice 0")


func test_choice_pad_dpad_up_moves_not_confirms() -> void:
	var box = _box_at_choice(_on_air())
	await _wait_real_ms(450)
	check(box.confirm_armed(), "armed")
	InputGlyphs.using_pad = true
	var dpad_up: Array[StringName] = [&"interact", &"move_up"]
	await press_actions(dpad_up, 3)
	check(box._selected == 1, "D-pad Up moved the cursor (wraps to 1)")
	check(box.is_choosing() and choices_made.is_empty(), "D-pad Up made no choice")
	await press_action(&"attack_light", 3)
	check(box.is_choosing() and choices_made.is_empty(), "attack_light makes no choice")
	await press_action(&"interact", 3)
	check(box.is_choosing() and choices_made.is_empty(), "pad interact alone makes no choice")


func test_choice_ignores_carried_and_mashed_press() -> void:
	# Held: a jump begun on the last line opens the options and is still held.
	var d := _on_air()
	var box = _new_box()
	box.open(d, "Orr")
	box.advance()
	box.shown_chars = 999.0
	var start := Time.get_ticks_msec()
	# The box ignores presses on the frame it opened; start a frame later.
	await get_tree().process_frame
	await press_action(&"jump", 60)
	check(box.is_choosing(), "the held jump opened the options (open %s line %d chosen %s)" % [box.is_open(), box.line_index, str(choices_made)])
	while Time.get_ticks_msec() - start < 1000:
		await get_tree().process_frame
	await physics_frames(3)
	check(box.is_choosing() and choices_made.is_empty(), "a carried, held press never picks")
	box.queue_free()
	await get_tree().process_frame
	# Mashed at 8 Hz from before the options appear.
	box = _new_box()
	box.open(d, "Orr")
	box.advance()
	box.shown_chars = 999.0
	await get_tree().process_frame
	var opened := false
	for i in 12:
		Input.action_press(&"jump")
		await _wait_real_ms(62)
		Input.action_release(&"jump")
		opened = opened or box.is_choosing() or not choices_made.is_empty()
		if not choices_made.is_empty():
			break
		await _wait_real_ms(62)
	check(opened, "the mash opened the options")
	var arm_ms := int(box.CHOICE_ARM_SECONDS * 1000.0)
	check(choices_made.size() == 1, "a fresh press after the arm time picks (%s)" % str(choices_made))
	if choices_made.size() == 1:
		check(choice_ms[0] - box._choice_shown_ms >= arm_ms, "no pick before the arm time (%d ms)" % (choice_ms[0] - box._choice_shown_ms))


func test_choice_waits_without_input() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.PLAY)
	var box = _box_at_choice(_on_air())
	for i in 600:
		await get_tree().process_frame
	check(box.is_open() and box.is_choosing(), "the box still waits after 10 s")
	check(choices_made.is_empty() and not Game.has_flag("orr_air_named") and not Game.has_flag("orr_air_ghost"), "no choice without input")


func test_choice_keyboard_e_confirms() -> void:
	var box = _box_at_choice(_on_air())
	await _wait_real_ms(450)
	InputGlyphs.using_pad = false
	await press_action(&"interact", 3)
	check(choices_made == [["orr_on_air", "named"]], "E confirms the selected answer once: %s" % str(choices_made))


func test_choice_footer_glyph() -> void:
	var box = _box_at_choice(_on_air())
	InputGlyphs.using_pad = false
	var kb: String = box.choice_footer()
	InputGlyphs.using_pad = true
	var pad: String = box.choice_footer()
	check(kb == "[E] choose", "keyboard footer: %s" % kb)
	check(pad == "[A] choose", "pad footer: %s" % pad)
	for t in [kb, pad]:
		check(not t.contains("[]") and not t.contains("ui_accept"), "footer names a button: %s" % t)


# --- world, tick, journal ---

func test_relay_npc_beat_via_interact() -> void:
	_root = Node2D.new()
	add_child(_root)
	SceneRouter.register_world_root(_root)
	SceneRouter.goto_room(RELAY, &"start")
	await physics_frames(3)
	var room := SceneRouter.current_room as Room
	var mara := room.find_child("NPC_mara", true, false) as NPC
	check(mara != null, "Relay has Mara")
	if mara == null:
		return
	Game.set_flag("met_mara")
	Game.set_flag("warden_krail_defeated")
	check(mara.has_pending_beat(), "Mara has a pending beat")
	var box = _new_box()
	mara.interact(room.player)
	check(box.is_open() and box.dialogue.id == "mara_after_boss", "interact opens mara_after_boss")
	check(get_tree().paused, "paused while talking")
	_close_box(box)
	check(menus.has(&"shop_mara"), "closes to shop_mara")
	check(not mara.has_pending_beat(), "tick gone")
	check(not get_tree().paused, "unpaused")


func test_tick_colour_and_bodiless_cue() -> void:
	check(NPC.PENDING_TICK_COLOR == UiTheme.TEXT, "tick colour is UiTheme.TEXT")
	check(NPC.PENDING_TICK_COLOR != UiTheme.ACCENT and NPC.PENDING_TICK_COLOR != Color("ffcf5a"), "never Redline red or elite amber")
	var mk := func(id: String, text: String, requires: PackedStringArray) -> NpcDialogueRule:
		var l := DialogueLine.new()
		l.text = text
		var d := DialogueData.new()
		d.id = id
		d.lines = [l]
		var r := NpcDialogueRule.new()
		r.requires_flags = requires
		r.dialogue = d
		return r
	var p := NpcProfile.new()
	p.npc_id = "test_board"
	p.display_name = "Board"
	p.figure = false
	p.verb = "Listen"
	p.cue_new_lines = true
	p.rules = [mk.call("test_board_news", "News.", PackedStringArray(["test_board_news_on"])), mk.call("test_board_idle", "Static.", PackedStringArray())]
	var npc := NPC.new()
	npc.profile = p
	add_child(npc)
	_extras.append(npc)
	check(npc.has_pending_beat(), "unheard line: tick")
	var box = _new_box()
	npc.interact(null)
	_close_box(box)
	check(Game.has_flag("heard_test_board_idle") and not npc.has_pending_beat(), "heard on close: tick cleared")
	Game.set_flag("test_board_news_on")
	check(npc.has_pending_beat(), "a new top rule ticks again")


func test_journal_people_notes() -> void:
	# Main page at its fullest: every quest listed, every fragment recovered.
	for q in Game.quests.quests:
		Game.set_flag(q.start_flag)
	Game.set_flag("dead_air_complete")
	MemoryLibrary.dev_grant_all_fragments()
	for npc: String in NPCS:
		Game.set_flag("met_%s" % npc)
	Game.set_flag("warden_krail_defeated")
	Game.set_flag("arcbeat_iko_met")
	Game.set_flag("act1_complete")
	var j: MenuScreen = load("res://ui/menus/JournalMenu.gd").new()
	add_child(j)
	_extras.append(j)
	j.open_menu()
	var people: Button = null
	for b in j.find_children("*", "Button", true, false):
		if (b as Button).text == "People…":
			people = b
	check(people != null, "the main page has a 'People…' button")
	var h_main: float = await menu_height(j)
	check(h_main <= 270.0, "main journal fits the canvas (%.0f px)" % h_main)
	if people == null:
		j.close_menu()
		return
	people.grab_focus()
	var people_index: int = j.focused_index()
	people.pressed.emit()
	var mara_line := false
	var lines := 0
	for l in j.find_children("*", "Label", true, false):
		var t := (l as Label).text
		if t.contains(" — "):
			lines += 1
		if t.contains("Mara") and t.contains("Just a look"):
			mara_line = true
	check(mara_line, "PEOPLE lists Mara's Krail note")
	check(lines == 5, "one line per arc (got %d)" % lines)
	var h_people: float = await menu_height(j)
	check(h_people <= 270.0, "PEOPLE page fits the canvas (%.0f px)" % h_people)
	j.show_main()
	check(j.focused_index() == people_index, "Back returns focus to the People row")
	j.close_menu()


func test_validator_arc_rules() -> void:
	var cases := {
		"beat_no_heard": "must set arcbeat_t_s1",
		"idle_sets": "must set nothing",
		"gives": "economy-neutral",
		"speaker": "speaker 'Stranger'",
		"shop": "must open shop_mara",
		"label_long": "label must be 1-28",
		"overlap": "both set 'x_a'",
		"one_choice": "needs 2-3 options",
		"bogus_count": "unknown count metric",
		"bad_menu": "unknown menu 'shop_nowhere'",
	}
	for key: String in cases:
		var arc := _bad_arc(key)
		var v := ContentValidator.new()
		v.check_resource(arc, "res://data/test/x.tres")
		var hits := Array(v.errors).filter(func(e: String) -> bool: return e.contains(cases[key]))
		check(hits.size() == 1, "%s: expected one '%s' error, got %s" % [key, cases[key], str(v.errors)])
	# Unowned: no lint_owner and no profile under data/npcs owns it.
	var unowned := _bad_arc("")
	unowned.lint_owner = null
	var v2 := ContentValidator.new()
	v2.check_resource(unowned, "res://data/test/x.tres")
	var own := Array(v2.errors).filter(func(e: String) -> bool: return e.contains("owned by exactly one"))
	check(own.size() == 1, "unowned arc errors once: %s" % str(v2.errors))
	# The real content: clean, and bonds are all read.
	var real := ContentValidator.new()
	real.validate_resources()
	real.validate_flags()
	# Rooms are not scanned here, so room-set flags read as unset; the flag
	# graph as a whole is ValidateContent's job.
	var arc_errors := Array(real.errors).filter(func(e: String) -> bool: return e.contains("arc_") and not e.contains("nothing sets it"))
	check(arc_errors.is_empty(), "shipped arcs lint clean: %s" % str(arc_errors))
	var bond_warn := Array(real.warnings).filter(func(w: String) -> bool: return w.contains("'bond_"))
	check(bond_warn.is_empty(), "every bond is read: %s" % str(bond_warn))


## A one-stage in-memory arc owned by an in-memory shopkeeper "T", made
## wrong in exactly one way (key "" = valid).
func _bad_arc(key: String) -> NpcArc:
	var line := func(text: String, speaker: String = "T") -> DialogueLine:
		var l := DialogueLine.new()
		l.speaker = speaker
		l.text = text
		return l
	var beat := DialogueData.new()
	beat.id = "t_beat"
	beat.lines = [line.call("Hello.", "Stranger" if key == "speaker" else "T")]
	beat.set_flags = PackedStringArray([] if key == "beat_no_heard" else ["arcbeat_t_s1"])
	beat.open_menu = &"shop_nowhere" if key == "bad_menu" else (&"" if key == "shop" else &"shop_mara")
	if key == "gives":
		beat.give_scrap = 5
	if key in ["label_long", "overlap", "one_choice"]:
		beat.open_menu = &"shop_mara"
		var a := DialogueChoice.new()
		a.id = "a"
		a.label = "An answer far too long for the box." if key == "label_long" else "Yes."
		a.set_flags = PackedStringArray(["x_a"])
		beat.choices = [a]
		if key != "one_choice":
			var b := DialogueChoice.new()
			b.id = "b"
			b.label = "No."
			b.set_flags = PackedStringArray(["x_a"] if key == "overlap" else ["x_b"])
			beat.choices.append(b)
	var beat_rule := NpcDialogueRule.new()
	beat_rule.dialogue = beat
	var idle := DialogueData.new()
	idle.id = "t_idle"
	idle.lines = [line.call("Still here.")]
	idle.open_menu = &"shop_mara"
	if key == "idle_sets":
		idle.set_flags = PackedStringArray(["t_idle_flag"])
	var idle_rule := NpcDialogueRule.new()
	idle_rule.dialogue = idle
	var s := NpcArcStage.new()
	s.id = "s1"
	s.enter_all = PackedStringArray(["count:bogus:1"] if key == "bogus_count" else ["flag:met_t"])
	s.beat_rules = [beat_rule]
	s.idle_rules = [idle_rule]
	s.journal_note = "Test."
	var arc := NpcArc.new()
	arc.npc_id = "t"
	arc.stages = [s]
	var shop := DialogueData.new()
	shop.id = "t_shop"
	shop.lines = [line.call("Buy.")]
	shop.open_menu = &"shop_mara"
	var fb := NpcDialogueRule.new()
	fb.dialogue = shop
	var owner := NpcProfile.new()
	owner.npc_id = "t"
	owner.display_name = "T"
	owner.rules = [fb]
	owner.arc = arc
	arc.lint_owner = owner
	return arc


# --- tracker wiring and warm-up ---

func test_arc_tracker_signal_wiring() -> void:
	var t: ArcTracker = Game.arcs
	var emits := {
		"flag_changed": func() -> void: EventBus.flag_changed.emit("test_arcs_wiring", true),
		"secret_found": func() -> void: EventBus.secret_found.emit("test_arcs_secret"),
		"memory_fragment_found": func() -> void: EventBus.memory_fragment_found.emit(load("res://data/lore/mf_lowlight_01.tres")),
		"circuit_granted": func() -> void: EventBus.circuit_granted.emit("scavenger"),
		"room_entered": func() -> void: EventBus.room_entered.emit("lowlight", "Relay"),
		"anchor_rested": func() -> void: EventBus.anchor_rested.emit(self),
		"collectible_taken": func() -> void: EventBus.collectible_taken.emit("test_arcs_pickup", Collectible.Kind.CORE_SHARD),
	}
	for sig: String in emits:
		var before := t.evaluate_count
		var loads := t.load_evaluate_count
		(emits[sig] as Callable).call()
		check(t.evaluate_count > before, "%s reaches evaluate" % sig)
		check(t.load_evaluate_count == loads, "%s evaluates with on_load = false" % sig)
	var loads_before := t.load_evaluate_count
	EventBus.game_state_reset.emit()
	check(t.load_evaluate_count == loads_before + 1, "game_state_reset reaches evaluate(true)")


func test_slice_stats_warm_before_play() -> void:
	Game._warm_slice_stats()
	check(not SliceStats._totals.is_empty(), "SliceStats warm after _warm_slice_stats")
	var builds := SliceStats.build_count
	_root = Node2D.new()
	add_child(_root)
	SceneRouter.register_world_root(_root)
	SceneRouter.goto_room("res://tests/fixtures/WorldA.tscn", &"start")
	await physics_frames(3)
	var room := SceneRouter.current_room as Room
	Game.set_flag("met_nix")
	Game.set_flag("met_vell")
	var shard := Collectible.new()
	shard.persist_id = "test_arcs_warm_shard"
	shard.kind = Collectible.Kind.CORE_SHARD
	shard.position = Vector2(80, 0)
	room.add_child(shard)
	var before := Game.arcs.evaluate_count
	room.player.teleport(Vector2(80, -2))
	await physics_frames(3)
	check(Game.state.core_shards == 1, "shard picked up")
	check(Game.arcs.evaluate_count > before, "the pickup evaluated the arcs")
	check(SliceStats.build_count == builds, "no room scan on the pickup (%d -> %d)" % [builds, SliceStats.build_count])
