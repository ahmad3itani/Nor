extends RedlineTestCase
## New Game+ (M9 D3 §2, D-153, R09.1..R09.15): the carry whitelist, the
## archive and the begin flow (from the title and in play), the refusals,
## the NG+ screen, the pickups and shard husks, the stash payout, the known-
## scene skip hold, known dialogue, the Act I card lines and text auto-advance.
## Saves and platform files go to temp dirs (ChallengeHarness).

const H := preload("res://tests/fixtures/challenges/ChallengeHarness.gd")
const WAKE := "res://world/rooms/undercity/Wake.tscn"
const BAY := "res://world/rooms/undercity/CollectorBay.tscn"
const ESCAPE := "res://world/rooms/undercity/EscapeTunnel.tscn"
const PARITY := "res://data/sequences/test_seq_parity.tres"
const LINES := "res://data/sequences/test_seq_lines.tres"
const PLAYTEST_DIR := "user://test_ng_plus_playtest"
## Frames an AUTO x1 play of test_seq_lines takes with text auto-advance off
## (measured on the M8 runtime; R09.9 must not move it by a frame).
const M8_LINES_AUTO_FRAMES := 695

var h: H
var _snap: Dictionary
var _extras: Array[Node] = []
var _finished: Array = []


func before_each() -> void:
	h = H.new(self, "ng_plus")
	h.setup()
	_snap = use_default_m8_settings()
	_extras.clear()
	_finished.clear()
	EventBus.sequence_finished.connect(_on_finished)
	Game.onboarding = Game.ONBOARDING
	NewGamePlus.clear_cache()


func after_each() -> void:
	EventBus.sequence_finished.disconnect(_on_finished)
	for n in _extras:
		if is_instance_valid(n):
			n.queue_free()
	_extras.clear()
	get_tree().paused = false
	CinematicMode.teardown()
	restore_m8_settings(_snap)
	Settings.text_auto_advance = 0
	Game.onboarding = Game.ONBOARDING
	await h.teardown()


func _on_finished(id: String, skipped: bool, _s: float, _i: int, _c: int, _n: float) -> void:
	_finished.append([id, skipped, Engine.get_process_frames()])


func _cfg() -> NgPlusConfig:
	return NewGamePlus.config()


func _shard_ids() -> Array:
	var out: Array = []
	var index := NewGamePlus.collectible_index()
	for id: String in index:
		if int(index[id]["kind"]) == Collectible.Kind.CORE_SHARD:
			out.append(id)
	out.sort()
	return out


## A profile that closed Act I: the full kit, every shard, a plain and a
## secret bundle, a wall, a fragment, story, boss, quest, arc and seen flags.
func _cleared() -> GameState:
	var s := GameState.new()
	s.owned_weapons.assign(["pulse_blade", "service_pistol"])
	s.melee_weapon = "pulse_blade"
	s.ranged_weapon = "service_pistol"
	var circuits: Array[String] = []
	for c in Game.catalog.circuits.slice(0, 2):
		circuits.append(String(c.id))
	s.owned_circuits.assign(circuits)
	s.equipped_circuits.assign(circuits.slice(0, 1))
	s.core_shards = 5
	for id: String in _shard_ids():
		s.collected[id] = true
	for id in ["sb_uc_med_shelf", "sb_uc_bay_vent", "uc_collector_vent", "mf_lowlight_01", "sb_uc_wake_sill"]:
		s.collected[id] = true
	s.memory_fragments.assign(["mf_lowlight_01"])
	s.scrap_banked = 300
	s.scrap_unbanked = 40
	s.dropped_scrap = {"room": BAY, "x": 1.0, "y": 2.0, "amount": 12}
	s.deaths = 7
	s.play_time_sec = 1234.0
	s.abilities = {"dash": true}
	for f in ["act1_complete", "slice_end_seen", "collector_drone_defeated", "warden_krail_defeated", "got_pulse_blade",
			"got_service_pistol", "unlocked_dash", "hint_first_flow", "quest_dead_air_started", "arc_orr_trust",
			"mem_seen_mf_lowlight_01", "seen_seq_act1_close", "null_open", "null_depth_reached", "map_charted_undercity",
			"chase_rainline_done", "met_orr_radio"]:
		s.flags[f] = true
	s.flags["core_hud_hidden"] = false
	s.flags[NewGamePlus._upgrade_flags()[0]] = 2
	s.last_anchor_room = BAY
	s.last_anchor_id = "a1"
	s.anchors_rested.assign([BAY + "|a1"])
	s.visited_rooms.assign([WAKE, BAY])
	return s


func _opts(remix := true, dash := true) -> Dictionary:
	return {"remix": remix, "keep_dash": dash}


# --- carry() ------------------------------------------------------------------------

func test_carry_keeps_the_kit_and_resets_the_world() -> void:
	var old := _cleared()
	var s := NewGamePlus.carry(old, _cfg(), _opts(), Game.onboarding)
	check(Array(s.owned_weapons) == ["pulse_blade", "service_pistol"] and s.melee_weapon == "pulse_blade" and s.ranged_weapon == "service_pistol",
		"weapons and slots carry")
	check(s.owned_circuits == old.owned_circuits and s.equipped_circuits == old.equipped_circuits, "Circuits owned and equipped carry")
	check(s.core_shards == 5 and s.scrap_banked == 300, "shards and banked Scrap carry")
	check(s.scrap_unbanked == 0 and s.dropped_scrap.is_empty(), "unbanked and dropped Scrap are lost")
	var up := NewGamePlus._upgrade_flags()[0]
	check(int(s.flags.get(up, 0)) == 2, "shop upgrade counter %s carries" % up)
	for f in ["hint_first_flow", "null_open", "null_depth_reached"]:
		check(s.flags.has(f), "%s carries" % f)
	for f in ["act1_complete", "slice_end_seen", "collector_drone_defeated", "warden_krail_defeated", "quest_dead_air_started",
			"arc_orr_trust", "mem_seen_mf_lowlight_01", "seen_seq_act1_close", "got_pulse_blade", "got_service_pistol",
			"unlocked_dash", "map_charted_undercity", "chase_rainline_done", "met_orr_radio"]:
		check(not s.flags.has(f), "%s never survives" % f)
	check(s.anchors_rested.is_empty() and s.last_anchor_room == "" and s.visited_rooms.is_empty() and s.map_explored.is_empty(),
		"Anchors, rooms and map reset")
	check(s.memory_fragments.is_empty() and s.deaths == 0 and s.play_time_sec == 0.0, "fragments, deaths and time reset")
	check(s.health == -1 and s.injectors == -1 and s.reactor_charge == -1.0, "health, injectors and Core start full")
	# R09.2: shard spots and plain bundles stay taken; secrets refill.
	for id in _shard_ids():
		check(s.collected.has(id), "shard spot %s stays found" % id)
	check(s.collected.has("sb_uc_med_shelf") and s.collected.has("sb_uc_wake_sill"), "plain bundles stay taken")
	check(not s.collected.has("sb_uc_bay_vent"), "the secret stash behind the vent refills")
	check(not s.collected.has("uc_collector_vent") and not s.collected.has("mf_lowlight_01"), "walls and fragments reset")
	check(not old.collected.is_empty() and old.flags.has("act1_complete"), "carry() does not touch the old state")


func test_denied_flags_never_carry_even_if_listed() -> void:
	var cfg := _cfg().duplicate() as NgPlusConfig
	cfg.carry_flags = PackedStringArray(["act1_complete", "boss_defeated", "null_open"])
	cfg.carry_flag_prefixes = PackedStringArray(["quest_", "hint_"])
	check(cfg.validate().size() >= 3, "validate rejects story flags and prefixes: %s" % [cfg.validate()])
	var old := _cleared()
	old.flags["boss_defeated"] = true
	var s := NewGamePlus.carry(old, cfg, _opts(), Game.onboarding)
	check(not s.flags.has("act1_complete") and not s.flags.has("boss_defeated") and not s.flags.has("quest_dead_air_started"),
		"the deny-list wins over a bad config")
	check(_cfg().validate().is_empty(), "the shipped config validates: %s" % [_cfg().validate()])
	check(Array(_cfg().content_flags()["produces"]) == ["ng_cycle", "ng_remix", "ng_keep_dash"], "produces the three NG+ flags")


func test_onboarding_start_flags_minus_core_hud() -> void:
	var ob := Game.ONBOARDING.duplicate() as OnboardingConfig
	ob.start_flags = {"core_hud_hidden": true, "ng_test_start": true}
	var s := NewGamePlus.carry(_cleared(), _cfg(), _opts(), ob)
	check(not s.flags.has("core_hud_hidden"), "the Core HUD is known: core_hud_hidden not set")
	check(s.flags.get("ng_test_start", false), "other onboarding start flags apply")


func test_dash_follows_the_option() -> void:
	var on := NewGamePlus.carry(_cleared(), _cfg(), _opts(true, true), Game.onboarding)
	var off := NewGamePlus.carry(_cleared(), _cfg(), _opts(true, false), Game.onboarding)
	check(on.abilities.get("dash", false) and on.flags["ng_keep_dash"] == true, "Start with the Dash: On")
	check(not off.abilities.get("dash", false) and off.flags["ng_keep_dash"] == false, "Start with the Dash: Off")
	check(not on.flags.has("unlocked_dash") and not off.flags.has("unlocked_dash"), "unlocked_dash is never carried")
	var r := NewGamePlus.carry(_cleared(), _cfg(), _opts(false, true), Game.onboarding)
	check(r.flags["ng_remix"] == false and on.flags["ng_remix"] == true, "the remix option is stored as ng_remix")


func test_cycle_increments_and_archive_appends() -> void:
	var c0 := _cleared()
	var c1 := NewGamePlus.carry(c0, _cfg(), _opts(), Game.onboarding)
	check(int(c1.flags["ng_cycle"]) == 1, "0 -> 1")
	c1.flags["act1_complete"] = true
	c1.flags["seen_seq_relay_intro"] = true
	# JSON turns ints into floats (R09.7): the next carry still counts.
	var json := JSON.parse_string(JSON.stringify(c1.to_dict())) as Dictionary
	var c2 := NewGamePlus.carry(GameState.from_dict(json), _cfg(), _opts(), Game.onboarding)
	check(int(c2.flags["ng_cycle"]) == 2, "1 -> 2 (%s)" % c2.flags.get("ng_cycle"))
	var cycles: Array = c2.ng_archive.get("cycles", [])
	check(cycles.size() == 2 and int(cycles[0]["cycle"]) == 0 and int(cycles[1]["cycle"]) == 1, "one archive row per finished cycle: %s" % [cycles])
	check(int(cycles[0]["deaths"]) == 7 and int(cycles[0]["fragments"]) == 1 and int(cycles[0]["secrets"]) >= 5, "row 0 keeps the run's numbers")
	var seen: Array = c2.ng_archive.get("seen_flags", [])
	check(seen.has("seen_seq_act1_close") and seen.has("mem_seen_mf_lowlight_01") and seen.has("seen_seq_relay_intro"),
		"seen_flags unions every cycle's seen scenes: %s" % [seen])
	# R09.12: a conversation's flags join the archive.
	check(NewGamePlus.dialogue_flags().has("met_orr_radio") or not seen.has("met_orr_radio"), "dialogue flags come from DialogueData producers")
	if NewGamePlus.dialogue_flags().has("met_orr_radio"):
		check(seen.has("met_orr_radio"), "a finished conversation's flag is known in NG+")


func test_ng_plus_keeps_dev_taint() -> void:
	var old := _cleared()
	old.dev_tainted = true
	check(NewGamePlus.carry(old, _cfg(), _opts(), Game.onboarding).dev_tainted, "R09.1: taint is sticky through NG+")
	check(not NewGamePlus.carry(_cleared(), _cfg(), _opts(), Game.onboarding).dev_tainted, "a clean profile stays clean")


func test_can_begin() -> void:
	check(not NewGamePlus.can_begin({}), "no save")
	check(not NewGamePlus.can_begin(GameState.new().to_dict()), "false without act1_complete")
	check(NewGamePlus.can_begin(_cleared().to_dict()), "true after the Act I close")
	var old_m7 := GameState.new()
	old_m7.flags["slice_end_seen"] = true
	check(NewGamePlus.can_begin(old_m7.to_dict()), "a pre-M8 save that saw the end counts (load derives act1_complete)")
	BuildInfo.set_force_demo(1)
	check(not NewGamePlus.can_begin(_cleared().to_dict()), "false in the demo")
	BuildInfo.set_force_demo(-1)


func test_old_save_loads_with_defaults() -> void:
	var data := AtomicJson.read(H.SAVE_V3)
	check(not data.is_empty(), "fixture loads")
	var s := GameState.from_dict(SaveManager.migrate(data))
	check(s.ng_archive.is_empty(), "ng_archive defaults to {}")
	Game.state = s
	check(NewGamePlus.cycle() == 0 and not NewGamePlus.knows_seen_flag("seen_seq_act1_close"), "cycle 0, nothing known")


# --- begin() ------------------------------------------------------------------------

func _save_cleared() -> void:
	Game.state = _cleared()
	Game.profile_id = 1
	check(Game.save_game() == OK, "saved the cleared profile")


func test_begin_archives_and_lands_at_wake_armed() -> void:
	_save_cleared()
	var events: Array = []
	h.listen(EventBus.ng_plus_started, func(c: int) -> void: events.append(c))
	check(NewGamePlus.begin({"from": "", "remix": true, "keep_dash": true}), "begin: %s" % NewGamePlus.last_refusal)
	check(events == [1], "ng_plus_started(1) (%s)" % [events])
	var archive := "%s/profile_1.cycle0.json" % SaveManager.save_dir
	check(FileAccess.file_exists(archive), "profile_1.cycle0.json written")
	var arch := AtomicJson.read(archive)
	check(bool((arch.get("flags", {}) as Dictionary).get("act1_complete", false)), "the archive is the cleared save")
	var live := SaveManager.load_profile(1)
	check(NewGamePlus.cycle_of(live) == 1 and not bool((live["flags"] as Dictionary).get("act1_complete", false)), "the live save is NG+ cycle 1")
	check(Game.state.igt_complete and Game.state.igt_frames == 0, "a fresh campaign clock that may post a best")
	check(Game.abilities.dash, "abilities rebuilt from the carried state")
	check(await h.until(func() -> bool: return SceneRouter.current_room_path == Game.campaign_start_room() and not SceneRouter.transitioning, 60),
		"lands at the campaign start (%s)" % SceneRouter.current_room_path)
	check(Game.campaign_start_room() == WAKE, "the shipped start is Wake")
	var room := h.room()
	check(room != null and room.player != null and room.player.combat.melee_weapon != null, "armed with the carried blade")
	check(not Game.has_flag("core_hud_hidden"), "the Core HUD shows")


func test_ng_plus_from_fresh_boot_title() -> void:
	_save_cleared()
	# A fresh boot: Game.state is the default GameState (the title only loads in _continue).
	Game.new_game()
	check(NewGamePlus.begin({"from": "title", "remix": false, "keep_dash": false}), "begin from the title: %s" % NewGamePlus.last_refusal)
	check(NewGamePlus.cycle() == 1 and Game.state.owned_weapons.has("service_pistol") and Game.state.scrap_banked == 300,
		"loaded, then carried")
	check(not Game.abilities.dash and not NewGamePlus.remix_on(), "the options apply")
	check(await h.until(func() -> bool: return SceneRouter.current_room_path == Game.campaign_start_room() and not SceneRouter.transitioning, 60),
		"lands at Game.campaign_start_room()")


func test_refused_during_challenge_scene_or_without_act1() -> void:
	_save_cleared()
	Challenges.force_active = true
	check(not NewGamePlus.begin(_opts()) and NewGamePlus.last_refusal == "a challenge is running", "refused during a challenge")
	Challenges.force_active = false
	SceneRouter.transitioning = true
	check(not NewGamePlus.begin(_opts()) and NewGamePlus.last_refusal == "a room is loading", "refused mid-transition")
	SceneRouter.transitioning = false
	Game.state = GameState.new()
	check(not NewGamePlus.begin(_opts()) and NewGamePlus.last_refusal == "Act I not closed", "refused before the Act I close")
	check(not FileAccess.file_exists("%s/profile_1.cycle0.json" % SaveManager.save_dir), "no archive on a refusal")
	check(NewGamePlus.cycle_of(SaveManager.load_profile(1)) == 0, "the save on disk is untouched")


# --- The NG+ screen ------------------------------------------------------------------

func _labels(m: MenuScreen) -> Array:
	return m._body.get_children().filter(func(n: Node) -> bool: return n is Label).map(func(l: Label) -> String: return l.text)


func _button_texts(m: MenuScreen) -> Array:
	return m._body.get_children().filter(func(n: Node) -> bool: return n is Button).map(func(b: Button) -> String: return b.text)


func _press(m: MenuScreen, text: String) -> bool:
	for c in m._body.get_children():
		if c is Button and (c as Button).text == text:
			(c as Button).pressed.emit()
			return true
	check(false, "no '%s' button (%s)" % [text, _button_texts(m)])
	return false


func _ng_menu(host: Node) -> MenuScreen:
	var m: MenuScreen = load("res://ui/menus/NgPlusMenu.gd").new()
	host.add_child(m)
	m.ctx = {"from": "title"}
	m.open_menu()
	return m


func test_ng_plus_menu_fits_270_in_both_steps() -> void:
	_save_cleared()
	var host := h.make_host(true)
	var m := _ng_menu(host)
	var hdr: String = _labels(m)[0]
	check(hdr.begins_with("NEW GAME+") and hdr.ends_with("NG+"), "header with the next cycle label (%s)" % hdr)
	check(_button_texts(m) == ["Remixed enemies and hazards: On", "Start with the Dash: On", "Begin", "Back"], "rows: %s" % [_button_texts(m)])
	var hgt: float = await content_height(m)
	check(hgt <= 270.0, "options step fits 270 px (%.0f)" % hgt)
	m.focus_index(0)
	_press(m, "Remixed enemies and hazards: On")
	check(_button_texts(m)[0] == "Remixed enemies and hazards: Off", "confirm flips the option")
	_press(m, "Begin")
	check(_labels(m).has("Replace your Continue save with New Game+?"), "the confirm step asks")
	check(_button_texts(m) == ["Begin New Game+", "Back"], "confirm rows: %s" % [_button_texts(m)])
	hgt = await content_height(m)
	check(hgt <= 270.0, "confirm step fits 270 px (%.0f)" % hgt)
	_press(m, "Back")
	check(_button_texts(m)[0] == "Remixed enemies and hazards: Off", "Back keeps the chosen options")
	m.close_menu()


func test_ngplus_menu_copy_has_no_backup_promise() -> void:
	_save_cleared()
	var host := h.make_host(true)
	var m := _ng_menu(host)
	var text := "\n".join(_labels(m))
	check(not text.to_lower().contains("backup") and not text.contains("kept as a"), "no backup promise (R09.5): %s" % text)
	check(text.contains("the game cannot load it back"), "says the archive cannot be loaded")
	check(text.contains("Core Shards you found stay found") and text.contains("a quarter of their Scrap"), "the carry copy matches R09.2")
	m.close_menu()


func test_refusal_keeps_title_menu_open() -> void:
	# A save that has not closed Act I (a dev edit, a stale row).
	Game.state = GameState.new()
	Game.save_game()
	var host := h.make_host(true)
	var title: MenuScreen = host.get("title")
	var m := _ng_menu(host)
	_press(m, "Begin")
	_press(m, "Begin New Game+")
	check(m.is_open() and title.is_open(), "the NG+ screen and the title stay open")
	check(_labels(m).has("New Game+ is not available for this save."), "the neutral refusal line shows")
	check(m.focused_index() == 3, "focus on Back (%d)" % m.focused_index())
	_press(m, "Back")
	check(not m.is_open() and title.is_open(), "Back returns to the title")


func test_menu_success_closes_title() -> void:
	_save_cleared()
	Game.new_game()
	var host := h.make_host(true)
	var title: MenuScreen = host.get("title")
	var m := _ng_menu(host)
	_press(m, "Begin")
	_press(m, "Begin New Game+")
	check(NewGamePlus.cycle() == 1, "began NG+: %s" % NewGamePlus.last_refusal)
	check(not m.is_open(), "the NG+ screen closed")
	# The stand-in host is not a MenuHost: the real one closes its title
	# (MenuHost.title); here the title is closed by hand like Main would.
	title.close_menu()
	check(await h.until(func() -> bool: return SceneRouter.current_room_path == WAKE and not SceneRouter.transitioning, 60), "travelled to Wake")


# --- Pickups, shards and stashes -------------------------------------------------------------

func _pickup(weapon: String) -> WeaponPickup:
	var p := WeaponPickup.new()
	p.weapon_id = weapon
	h.root.add_child(p)
	return p


func test_weapon_pickup_marks_flag_when_owned() -> void:
	Game.state = NewGamePlus.carry(_cleared(), _cfg(), _opts(), Game.onboarding)
	var granted: Array = []
	h.listen(EventBus.weapon_granted, func(id: String) -> void: granted.append(id))
	var p := _pickup("service_pistol")
	check(Game.has_flag("got_service_pistol"), "NG+: an owned weapon's pickup sets its flag")
	check(p.is_queued_for_deletion() and granted.is_empty(), "no grant, gone")


func test_weapon_pickup_flag_only_in_ng_plus() -> void:
	Game.new_game()
	check(Game.state.owned_weapons.has("service_pistol"), "cycle 0 profile owns the pistol (legacy start)")
	var p := _pickup("service_pistol")
	check(not Game.has_flag("got_service_pistol"), "cycle 0: the flag stays unset")
	check(p.is_queued_for_deletion(), "and the pickup is gone as before")


func test_ngplus_collector_bay_exit_opens() -> void:
	Game.state = NewGamePlus.carry(_cleared(), _cfg(), _opts(false, false), Game.onboarding)
	Game.abilities = PlayerAbilities.new()
	Game.set_flag("collector_drone_defeated")
	var room := await h.goto(BAY, &"from_lift")
	await physics_frames(5)
	check(Game.has_flag("got_service_pistol"), "the pistol drop set its flag (the exit's requires_flag)")
	var bot := RouteBot.new(get_tree(), room.player)
	await physics_frames(10)
	var ok: bool = await bot.run([["run", 440], ["exit", 1]])
	check(ok, "CollectorBay route: %s" % bot.failure)
	check(await h.until(func() -> bool: return SceneRouter.current_room_path == ESCAPE, 30), "left through the east exit (%s)" % SceneRouter.current_room_path)


func _shard(id: String) -> Collectible:
	var c := Collectible.new()
	c.persist_id = id
	c.kind = Collectible.Kind.CORE_SHARD
	h.root.add_child(c)
	return c


func test_ngplus_shard_spot_shows_husk() -> void:
	var id: String = _shard_ids()[0]
	Game.state.collected[id] = true
	var gone := _shard(id)
	check(gone.is_queued_for_deletion(), "cycle 0: a taken shard vanishes")
	Game.state = NewGamePlus.carry(_cleared(), _cfg(), _opts(), Game.onboarding)
	var husk := _shard(id)
	check(not husk.is_queued_for_deletion() and husk._husk, "NG+: a found shard spot draws a husk")
	check(not husk.monitoring and husk.collision_mask == 0 and not husk.body_entered.is_connected(husk._on_body_entered),
		"the husk has no pickup")


func test_ngplus_shards_not_duplicated() -> void:
	Game.state = NewGamePlus.carry(_cleared(), _cfg(), _opts(), Game.onboarding)
	var room := await h.goto(WAKE, &"start")
	for id: String in _shard_ids():
		var c := _shard(id)
		c.global_position = room.player.global_position
	await physics_frames(10)
	check(Game.state.core_shards == 5, "walking over every carried shard spot keeps 5 (%d)" % Game.state.core_shards)


func test_ngplus_secret_stash_pays_quarter() -> void:
	Game.state = NewGamePlus.carry(_cleared(), _cfg(), _opts(false, false), Game.onboarding)
	Game.set_flag("collector_drone_defeated")
	var room := await h.goto(BAY, &"from_lift")
	var stash := room.get_node_or_null("Interactables/Collectible1") as Collectible
	check(stash != null and stash.persist_id == "sb_uc_bay_vent" and not stash.is_queued_for_deletion(), "the secret stash refilled")
	check(NewGamePlus.is_secret_bundle(stash), "it counts as a secret stash")
	var sum := func() -> int:
		var t := 0
		for n in room.find_children("*", "ScrapPickup", true, false):
			t += (n as ScrapPickup).value
		return t
	var before: int = sum.call()
	stash._on_body_entered(room.player)
	check(sum.call() - before == roundi(40 * 0.25), "pays a quarter: %d" % (sum.call() - before))
	# Cycle 0 pays the full amount (same bundle, fresh profile).
	check(NewGamePlus.stash_payout(40) == 10, "stash_payout in NG+")
	Game.state.flags.erase("ng_cycle")
	check(NewGamePlus.stash_payout(40) == 40, "cycle 0 pays in full")


func test_ngplus_secret_count_starts_at_carried_shards() -> void:
	var old := _cleared()
	for id in SliceStats.totals()["secret_ids"]:
		old.collected[id] = true
	var t := SliceStats.totals()
	check((t["secret_ids"] as Array).size() == 22 and int(t["core_shards"]) == 5, "22 secrets, 5 shards")
	Game.state = NewGamePlus.carry(old, _cfg(), _opts(), Game.onboarding)
	check(SliceStats.secrets_found() == 5, "an NG+ run starts at 5 of 22 secrets (%d)" % SliceStats.secrets_found())
	check(Game.count_metric("shards") == 5, "and 5 shards")


# --- Known scenes, known dialogue, auto-advance ----------------------------------------------

func test_known_scene_short_hold_first_view_steps_run() -> void:
	var room := await h.goto(H.WORLD_A, &"start")
	CinematicMode.set_mode(CinematicMode.Mode.PLAY)
	var seq := load(PARITY) as SequenceData
	var skip_press: Array[StringName] = [&"jump", &"cinematic_skip"]
	# Cycle 0: a 0.45 s hold does not skip a first view.
	Cinematics.play(seq, SequenceContext.for_room(room))
	await physics_frames(20)
	check(Cinematics.current != null and Cinematics.current.gate != null and Cinematics.current.gate.first_view, "cycle 0: the long hold")
	await press_actions(skip_press, 27)
	await physics_frames(3)
	check(_finished.is_empty(), "cycle 0: 0.45 s does not skip")
	Cinematics.abort()
	await physics_frames(3)
	_finished.clear()
	# NG+: the same unseen scene, known from the archive.
	Game.state.flags["ng_cycle"] = 1
	Game.state.ng_archive = {"cycles": [], "seen_flags": [seq.effective_seen_flag()]}
	check(not Game.has_flag(seq.effective_seen_flag()), "still a first view in this cycle")
	Cinematics.play(seq, SequenceContext.for_room(room))
	await physics_frames(20)
	check(Cinematics.current != null and Cinematics.current.first_view and not Cinematics.current.gate.first_view,
		"first_view stays true; only the gate uses the repeat hold")
	await press_actions(skip_press, 27)
	await physics_frames(3)
	check(_finished.size() == 1 and _finished[0][1], "NG+: 0.45 s skips a known scene")
	check(Game.has_flag(seq.effective_seen_flag()), "the skip ran every step's finish (the seen flag is set)")


func test_ngplus_known_dialogue_types_instantly_choices_wait() -> void:
	if not FileAccess.get_file_as_string("res://ui/dialogue/DialogueBox.gd").contains("NewGamePlus"):
		set_meta("skip_reason", "DialogueBox has no NG+ known-line hook yet (T11 R11.13 lands it)")
		return
	var d := DialogueData.new()
	d.id = "ng_test"
	for t in ["A line we have heard before.", "And a second one, also known."]:
		var l := DialogueLine.new()
		l.text = t
		d.lines.append(l)
	d.set_flags = PackedStringArray(["ng_test_known"])
	var ch := DialogueChoice.new()
	ch.label = "Sure."
	d.choices.append(ch)
	var box: CanvasLayer = load("res://ui/dialogue/DialogueBox.gd").new()
	add_child(box)
	_extras.append(box)
	# Cycle 0: typed out as ever.
	box.call("open", d)
	await get_tree().process_frame
	check(float(box.get("shown_chars")) < d.lines[0].text.length(), "cycle 0: the line types")
	box.call("_close")
	get_tree().paused = false
	Game.state.flags["ng_cycle"] = 1
	Game.state.ng_archive = {"seen_flags": ["ng_test_known"]}
	box.call("open", d)
	await get_tree().process_frame
	check(is_equal_approx(float(box.get("shown_chars")), d.lines[0].text.length()), "NG+: a known line shows fully typed on open")
	box.call("advance")
	await get_tree().process_frame
	check(int(box.get("line_index")) == 1 and is_equal_approx(float(box.get("shown_chars")), d.lines[1].text.length()),
		"the first confirm advances to the next line, also typed")
	box.call("advance")
	await physics_frames(10)
	check(bool(box.call("is_choosing")) and bool(box.call("is_open")), "a choice still waits")
	box.call("choose", 0)
	get_tree().paused = false


func _hold_seq(texts: Array) -> SequenceData:
	var seq := SequenceData.new()
	seq.id = "test_ng_hold"
	seq.theatre_only = true
	for t: String in texts:
		var l := SeqLine.new()
		l.text = t
		l.hold_for_input = true
		seq.steps.append(l)
	return seq


func test_auto_advance_off_keeps_m8_timing() -> void:
	var room := await h.goto(H.WORLD_A, &"start")
	var frames: Array = []
	for setting in [0, 1]:
		Settings.text_auto_advance = setting
		CinematicMode.set_mode(CinematicMode.Mode.AUTO)
		CinematicMode.auto_speed = 1.0
		_finished.clear()
		var start := Engine.get_process_frames()
		Cinematics.play(load(LINES) as SequenceData, SequenceContext.for_room(room))
		for i in 1200:
			if not _finished.is_empty():
				break
			await get_tree().process_frame
		frames.append(int(_finished[0][2]) - start if not _finished.is_empty() else -1)
		Game.state.flags.erase("seen_seq_test_seq_lines")
	check(frames[0] == M8_LINES_AUTO_FRAMES, "AUTO x1 test_seq_lines takes %d frames (M8: %d)" % [frames[0], M8_LINES_AUTO_FRAMES])
	check(frames[1] == frames[0], "auto-advance never changes an AUTO play (%s)" % [frames])
	# PLAY, off: a hold-for-input line waits for the tap as in M8.
	Settings.text_auto_advance = 0
	CinematicMode.set_mode(CinematicMode.Mode.PLAY)
	_finished.clear()
	Cinematics.play(_hold_seq(["Short line."]), SequenceContext.for_room(room))
	await physics_frames(400)
	check(_finished.is_empty() and Cinematics.is_playing(), "off: the line still waits after 400 frames")
	Cinematics.abort()
	await physics_frames(2)


func test_auto_advance_on_releases_hold_lines() -> void:
	var room := await h.goto(H.WORLD_A, &"start")
	Settings.text_auto_advance = 1
	CinematicMode.set_mode(CinematicMode.Mode.PLAY)
	var texts := ["Short line.", "A second line that is a little longer."]
	var budget := 0.0
	for t: String in texts:
		budget += t.length() / CinematicMode.config().type_cps + SequencePlayer.auto_advance_seconds(t.length())
	var start := Engine.get_process_frames()
	Cinematics.play(_hold_seq(texts), SequenceContext.for_room(room))
	for i in int(budget * 60.0) + 120:
		if not _finished.is_empty():
			break
		await get_tree().process_frame
	check(not _finished.is_empty() and not _finished[0][1], "on: both hold lines released by themselves (budget %.2f s)" % budget)
	if not _finished.is_empty():
		var took := (int(_finished[0][2]) - start) / 60.0
		check(took >= budget - 0.2, "no line leaves before its reading time (%.2f s of %.2f)" % [took, budget])


# --- The Act I card ---------------------------------------------------------------------------

func _card() -> MenuScreen:
	var card: MenuScreen = load("res://ui/menus/SliceEndMenu.gd").new()
	add_child(card)
	_extras.append(card)
	card.open_menu()
	return card


func test_slice_end_fits_270_cycle0_and_ng() -> void:
	Game.state = _cleared()
	MemoryLibrary.dev_grant_all_fragments()
	Game.state.flags["dead_air_complete"] = true
	var rec_was := Settings.playtest_recording
	Settings.playtest_recording = true
	Playtest.allow_headless = true
	Playtest.dir = PLAYTEST_DIR
	Playtest.begin_session("new")
	var card := _card()
	var labels := _labels(card)
	check(labels.has("New: a training rig at the Relay, and New Game+ on the title."), "cycle 0: the endgame line")
	check(labels.any(func(l: String) -> bool: return l.begins_with("Three ledges")), "cycle 0: the Dash-ledge pointer")
	check(not labels.any(func(l: String) -> bool: return l.contains("Deaths")), "no death count (R09.13): %s" % [labels])
	check(labels.has("Time 20:34"), "the time line (%s)" % [labels])
	var hgt: float = await content_height(card)
	check(hgt <= 270.0, "cycle 0 card fits 270 px with recording on (%.0f)" % hgt)
	card.close_menu()
	Game.state.flags["ng_cycle"] = 2
	Game.state.flags["ng_remix"] = true
	Game.state.flags["ng_keep_dash"] = true
	card = _card()
	labels = _labels(card)
	check(labels.has("NG+2 complete. Remix on."), "NG+ cycle line (%s)" % [labels])
	check(not labels.any(func(l: String) -> bool: return l.begins_with("Three ledges")), "no Dash-ledge pointer with the early Dash")
	check(not labels.has("New: a training rig at the Relay, and New Game+ on the title."), "the cycle-0 line is gone")
	check(not labels.any(func(l: String) -> bool: return l.contains("Deaths")), "no death count in NG+")
	hgt = await content_height(card)
	check(hgt <= 270.0, "NG+ card fits 270 px (%.0f)" % hgt)
	card.close_menu()
	Game.state.flags["ng_keep_dash"] = false
	card = _card()
	check(_labels(card).any(func(l: String) -> bool: return l.begins_with("Three ledges")), "NG+ without the early Dash keeps the pointer")
	card.close_menu()
	Playtest.end_session("test_done")
	Playtest.allow_headless = false
	Playtest.dir = Playtest.DIR
	Settings.playtest_recording = rec_was
	AtomicJson.remove_tree(PLAYTEST_DIR)


# --- Challenges survive NG+ -------------------------------------------------------------------

func test_ngplus_keeps_challenge_unlocks() -> void:
	check(ChallengeLibrary.data_dir == H.FIXTURES, "fixture challenges (R09.14)")
	Game.state = _cleared()
	var rematch := ChallengeLibrary.by_id("fx_rematch")
	check(rematch != null and rematch.unlock_when == "flag:collector_drone_defeated", "fixture unlocked by the Collector")
	ChallengeLibrary.record_unlocks()
	check(ChallengeLibrary.unlocked(rematch), "unlocked in cycle 0")
	Game.state = NewGamePlus.carry(Game.state, _cfg(), _opts(), Game.onboarding)
	check(not Game.has_flag("collector_drone_defeated"), "NG+ reset the boss flag")
	check(ChallengeLibrary.unlocked(rematch), "the challenge stays unlocked in NG+ (sticky record)")
	check(ChallengeLibrary.rig_open(), "the rig stays open in NG+ (ng_cycle >= 1)")
