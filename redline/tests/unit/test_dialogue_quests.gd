extends RedlineTestCase
## M3.3: NPC dialogue rules, the dialogue box, quest flow and rewards.

var ORR: NpcProfile


func before_each() -> void:
	Game.new_game()
	ORR = load("res://data/npcs/orr.tres")


func after_each() -> void:
	get_tree().paused = false
	Game.new_game()


func test_npc_profiles_validate() -> void:
	for f in DirAccess.get_files_at("res://data/npcs"):
		if f.ends_with(".tres"):
			var p: NpcProfile = load("res://data/npcs/" + f)
			check(p.validate().is_empty(), "%s: %s" % [f, ", ".join(p.validate())])


func test_quests_validate() -> void:
	check(Game.quests.quests.size() >= 1, "no quests loaded")
	for q in Game.quests.quests:
		check(q.validate().is_empty(), "%s: %s" % [q.id, ", ".join(q.validate())])


func test_orr_lines_follow_quest_state() -> void:
	check(ORR.pick_dialogue().id == "orr_intro", "fresh game should get the intro")
	Game.apply_dialogue(ORR.pick_dialogue())
	check(ORR.pick_dialogue().id == "orr_waiting", "after intro Orr should wait")
	for f in ["repeater_market", "repeater_stack", "repeater_bell"]:
		Game.set_flag(f)
	check(ORR.pick_dialogue().id == "orr_report", "all repeaters should unlock the report")
	Game.apply_dialogue(ORR.pick_dialogue())
	check(ORR.pick_dialogue().id == "orr_after", "after completion Orr should move on")


func test_dead_air_completes_once_and_pays() -> void:
	var q: QuestData = load("res://data/quests/dead_air.tres")
	Game.set_flag(q.start_flag)
	check(q.current_stage() == 0, "should start at stage 0")
	Game.set_flag("repeater_market")
	check(q.stage_progress(0) == Vector2i(1, 3), "progress should be 1/3")
	Game.set_flag("repeater_stack")
	Game.set_flag("repeater_bell")
	check(q.current_stage() == 1, "should advance to the report stage")
	var scrap_before := Game.state.total_scrap()
	Game.set_flag("dead_air_reported")
	check(Game.has_flag(q.complete_flag), "quest not completed")
	check(Game.state.total_scrap() == scrap_before + q.reward_scrap, "scrap reward not paid")
	check(Game.state.owned_circuits.has(q.reward_circuit), "circuit reward not granted")
	Game.quests.evaluate()
	check(Game.state.total_scrap() == scrap_before + q.reward_scrap, "reward paid twice")


func test_dialogue_box_pauses_and_applies_effects() -> void:
	var box: CanvasLayer = load("res://ui/dialogue/DialogueBox.gd").new()
	add_child(box)
	var d: DialogueData = ORR.rules[ORR.rules.size() - 1].dialogue
	box.open(d, "Orr")
	check(get_tree().paused, "dialogue should pause the game")
	check(not Game.has_flag("quest_dead_air_started"), "effects applied before the end")
	for i in d.lines.size():
		box.advance()
	check(not get_tree().paused, "closing should unpause")
	check(Game.has_flag("quest_dead_air_started"), "finish effects not applied")
	box.queue_free()


func test_repeater_sets_flag_and_locks() -> void:
	var r := SignalRepeater.new()
	r.flag_id = "repeater_market"
	add_child(r)
	check(r.can_interact(null), "fresh repeater should be usable")
	r.interact(null)
	check(Game.has_flag("repeater_market") and not r.can_interact(null), "repeater did not set/lock")
	r.queue_free()


## M7/D1: both Undercity radios share orr_radio.tres, and either may be
## skipped, so every rule has to read right as the first thing heard. Forward
## campaign players (Pulse Blade in hand) get the lift-shaft call; a legacy
## save that walked down from the Relay gets the legacy or location-neutral
## call instead, never lines about a lift shaft it is not standing at.
func test_orr_radio_rules() -> void:
	var radio: NpcProfile = load("res://data/npcs/orr_radio.tres")
	# Forward campaign at FirstPursuit: lift-shaft call, then the reminder.
	Game.start_campaign()
	Game.set_flag("got_pulse_blade")
	check(radio.pick_dialogue().id == "orr_radio_shaft", "blade holder should get the lift-shaft call")
	Game.apply_dialogue(radio.pick_dialogue())
	check(Game.has_flag("met_orr_radio"), "the first call should set met_orr_radio")
	check(radio.pick_dialogue().id == "orr_radio_waiting", "after the call the radio should repeat the route")
	# Boss killed without ever using a radio: the after-call stands alone.
	Game.start_campaign()
	Game.set_flag("got_pulse_blade")
	Game.set_flag("collector_drone_defeated")
	check(radio.pick_dialogue().id == "orr_radio_after", "after the boss the EscapeTunnel radio should congratulate")
	Game.apply_dialogue(radio.pick_dialogue())
	check(Game.has_flag("orr_radio_after") and Game.has_flag("met_orr_radio"), "after-call should set both flags")
	check(radio.pick_dialogue().id == "orr_radio_climb", "after-call should be one-shot")
	# Legacy save that met Orr at the Relay: no second introduction.
	Game.new_game()
	Game.set_flag("met_orr")
	check(radio.pick_dialogue().id == "orr_radio_legacy", "legacy met_orr should get the crew-band line")
	Game.apply_dialogue(radio.pick_dialogue())
	check(radio.pick_dialogue().id == "orr_radio_waiting", "legacy call should lead to the reminder")
	# Legacy save without met_orr or the blade (EscapeTunnel from above).
	Game.new_game()
	var d := radio.pick_dialogue()
	check(d.id == "orr_radio_first", "fallback should be the location-neutral call, got %s" % d.id)
	for l in d.lines:
		check(not l.text.contains("lift shaft") and not l.text.contains("That eye was"), "fallback mentions FirstPursuit: %s" % l.text)
	Game.apply_dialogue(d)
	check(Game.has_flag("met_orr_radio"), "fallback should set met_orr_radio")
	check(radio.pick_dialogue().id == "orr_radio_waiting", "fallback should lead to the reminder")


## M7/D4: talks to an NPC once and returns the id of the dialogue that played.
func _talk(p: NpcProfile) -> String:
	var d := p.pick_dialogue()
	Game.apply_dialogue(d)
	return d.id


func _way_up() -> QuestData:
	for q in Game.quests.quests:
		if q.id == "way_up":
			return q
	return null


## Fresh campaign: the radio starts "The Way Up", the Collector finishes stage
## 1, and at the Relay Orr and Mara both open with their Undercity intros.
## Meeting Orr completes the quest and pays its 30 Scrap exactly once.
func test_campaign_path_undercity_intros() -> void:
	var radio: NpcProfile = load("res://data/npcs/orr_radio.tres")
	var mara: NpcProfile = load("res://data/npcs/mara.tres")
	var q := _way_up()
	check(q != null, "way_up.tres should be discovered from data/quests")
	if q == null:
		return
	Game.start_campaign()
	Game.set_flag("got_pulse_blade")
	check(not q.is_started(), "way_up should not start before a radio")
	check(_talk(radio) == "orr_radio_shaft", "the first radio should be the lift-shaft call")
	check(q.is_started() and q.current_stage() == 0, "the radio should start way_up on stage 1")
	check(Game.quests.active_quests().has(q), "way_up should be active in the journal")
	Game.set_flag("collector_drone_defeated")
	check(q.current_stage() == 1, "killing the Collector should finish stage 1")
	check(_talk(radio) == "orr_radio_after", "the EscapeTunnel radio should congratulate")
	var scrap_before := Game.state.total_scrap()
	check(_talk(ORR) == "orr_intro_undercity", "the campaign Relay should open with orr_intro_undercity")
	check(Game.has_flag("met_orr") and Game.has_flag("quest_dead_air_started"), "the Undercity intro should set met_orr and start Dead Air")
	check(Game.has_flag(q.complete_flag), "meeting Orr should complete way_up")
	check(Game.state.total_scrap() == scrap_before + 30, "way_up should pay 30 Scrap")
	Game.quests.evaluate()
	check(Game.state.total_scrap() == scrap_before + 30, "way_up paid twice")
	check(Game.quests.completed_quests().has(q), "way_up should be listed as done")
	check(ORR.pick_dialogue().id == "orr_waiting", "after the Undercity intro Orr should wait on the repeaters")
	var menus: Array[StringName] = []
	var on_menu := func(id: StringName) -> void: menus.append(id)
	EventBus.menu_requested.connect(on_menu)
	check(_talk(mara) == "mara_intro_undercity", "Mara should open with mara_intro_undercity")
	EventBus.menu_requested.disconnect(on_menu)
	check(Game.has_flag("met_mara") and Game.state.owned_weapons.has("scattergun"), "Mara's Undercity intro should give the Scattergun")
	check(menus.has(&"shop_mara"), "Mara's Undercity intro should open her shop")
	check(mara.pick_dialogue().id == "mara_shop", "after the intro Mara just sells")


## Both radios skipped: the Relay intros key on collector_drone_defeated, so
## they still fire; way_up simply never starts.
func test_radio_skipped_still_gets_intros() -> void:
	var mara: NpcProfile = load("res://data/npcs/mara.tres")
	Game.start_campaign()
	Game.set_flag("got_pulse_blade")
	Game.set_flag("collector_drone_defeated")
	check(_talk(ORR) == "orr_intro_undercity", "Orr should still give the Undercity intro")
	check(_talk(mara) == "mara_intro_undercity", "Mara should still give the Undercity intro")
	var q := _way_up()
	check(q != null and not q.is_started(), "way_up should never start without a radio")
	check(q != null and not Game.quests.active_quests().has(q) and not Game.quests.completed_quests().has(q), "way_up should not be in the journal")


## Orr skipped until after the reroute and Krail, with all three repeaters
## done: the first line is always an introduction, never orr_report; then the
## Iko news, the Rainline line and the report, in that order.
func test_orr_skipped_until_after_reroute() -> void:
	for campaign in [true, false]:
		Game.new_game()
		if campaign:
			Game.set_flag("collector_drone_defeated")
		for f in ["lowlight_power_rerouted", "warden_krail_defeated", "repeater_market", "repeater_stack", "repeater_bell"]:
			Game.set_flag(f)
		var expected := ["orr_intro_undercity" if campaign else "orr_intro", "orr_iko", "orr_rainline", "orr_report", "orr_after"]
		var got: Array[String] = []
		for i in expected.size():
			got.append(_talk(ORR))
		check(got == expected, "%s save: expected %s, got %s" % ["campaign" if campaign else "legacy", str(expected), str(got)])
		check(Game.has_flag("met_iko") and Game.has_flag("orr_rainline_line"), "orr_iko/orr_rainline should set their flags")


## orr_report requires met_orr even with every repeater aligned.
func test_orr_report_needs_met_orr() -> void:
	for f in ["repeater_market", "repeater_stack", "repeater_bell"]:
		Game.set_flag(f)
	check(ORR.pick_dialogue().id == "orr_intro", "a stranger with three repeaters still gets the intro first")
	Game.set_flag("met_orr")
	check(ORR.pick_dialogue().id == "orr_report", "once met, the repeaters unlock the report")


## Legacy save (met_orr already set): the Undercity radio gives the crew-band
## line, and the Relay rules are unchanged (no Undercity intro, Mara's old
## intro, and the old Orr order).
func test_legacy_save_rules_unchanged() -> void:
	var radio: NpcProfile = load("res://data/npcs/orr_radio.tres")
	var mara: NpcProfile = load("res://data/npcs/mara.tres")
	Game.set_flag("met_orr")
	Game.set_flag("quest_dead_air_started")
	check(radio.pick_dialogue().id == "orr_radio_legacy", "legacy radio should be the crew-band line")
	check(ORR.pick_dialogue().id == "orr_waiting", "legacy Orr should wait on the repeaters")
	check(mara.pick_dialogue().id == "mara_intro", "legacy Mara should give the original intro")
	Game.set_flag("warden_krail_defeated")
	check(ORR.pick_dialogue().id == "orr_iko", "after Krail Orr should mention Iko once")
	Game.set_flag("collector_drone_defeated")
	Game.set_flag("met_iko")
	check(ORR.pick_dialogue().id == "orr_waiting", "met_orr blocks the Undercity intro")


## The journal lists an active way_up with its current stage.
func test_journal_lists_way_up() -> void:
	Game.set_flag("met_orr_radio")
	var m: MenuScreen = load("res://ui/menus/JournalMenu.gd").new()
	add_child(m)
	m.open_menu()
	var found := false
	for l in m.find_children("*", "Label", true, false):
		if (l as Label).text.contains("The Way Up") and (l as Label).text.contains("Collector's bay"):
			found = true
	check(found, "the journal should list The Way Up on its first stage")
	m.close_menu()
	m.queue_free()
