extends RedlineTestCase
## M9 foundation seams (T01): the endgame EventBus signals and their Playtest
## records, the save seams (held profile, derived flags, dev taint), the run
## director and demo hooks in Room/SceneRouter, the menu registry, the title,
## pause and dev-console layouts, and the inert stubs later tasks fill.
## Every stub is inert: the game behaves as before M9.

const ROOM_A := "res://tests/fixtures/WorldA.tscn"
const TEST_DIR := "user://test_m9_foundation"
const SAVE_DIR := "user://test_m9_foundation_saves"
const SAVE_V3 := "res://tests/fixtures/save_v3_slice.json"

## signal name -> argument names, exactly as the plan's events table.
const M9_SIGNALS := {
	"achievement_unlocked": ["achievement_id", "retroactive"],
	"challenge_started": ["challenge_id", "attempt"],
	"challenge_finished": ["challenge_id", "outcome", "value", "medal", "new_best"],
	"challenge_reset": ["challenge_id", "reason"],
	"challenge_stage_cleared": ["challenge_id", "stage_id", "frames", "hits", "deaths", "medal"],
	"speedrun_split": ["split_id", "igt_frames", "delta_frames"],
	"ng_plus_started": ["cycle"],
	"input_bindings_changed": ["action"],
	"assist_suggested": ["context", "cause", "deaths"],
	"assist_suggestion_answered": ["context", "answer", "setting_key"],
	"locale_changed": ["locale"],
	"demo_boundary_reached": ["from_room", "target_room"],
}

var root: Node2D
var _extras: Array[Node] = []
var _saved_recording: bool
var _saved_variant: String


func before_each() -> void:
	_saved_recording = Settings.playtest_recording
	_saved_variant = Settings.playtest_variant
	get_tree().paused = false
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	SaveManager.save_dir = SAVE_DIR
	Game.new_game()


func after_each() -> void:
	for n in _extras:
		if is_instance_valid(n):
			n.queue_free()
	_extras.clear()
	# Let a booted Main leave the tree before the router forgets its room.
	await get_tree().process_frame
	get_tree().paused = false
	Playtest.end_session("test_done")
	Playtest.allow_headless = false
	Playtest.dir = Playtest.DIR
	Settings.playtest_recording = _saved_recording
	Settings.playtest_variant = _saved_variant
	Game.held_profile = null
	Game.onboarding = Game.ONBOARDING
	for dir in [TEST_DIR, SAVE_DIR]:
		AtomicJson.remove_tree(dir)
	SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR
	SceneRouter.current_room = null
	SceneRouter.current_room_path = ""
	SceneRouter.world_root = null
	root.queue_free()
	Game.new_game()
	await physics_frames(2)


func _record() -> void:
	Settings.playtest_recording = true
	Settings.playtest_variant = "baseline"
	Playtest.dir = TEST_DIR
	Playtest.allow_headless = true
	Playtest.begin_session("new")


func _events(type: String) -> Array:
	return Playtest.session.events_of(type) if Playtest.session else []


func _extra(n: Node) -> Node:
	add_child(n)
	_extras.append(n)
	return n


# --- EventBus and Playtest (T01b) ---------------------------------------------------

func test_eventbus_m9_signals_typed() -> void:
	var by_name := {}
	for s in (EventBus.get_script() as GDScript).get_script_signal_list():
		by_name[s["name"]] = s
	for sig: String in M9_SIGNALS:
		check(by_name.has(sig), "EventBus.%s exists" % sig)
		if not by_name.has(sig):
			continue
		var args: Array = by_name[sig]["args"]
		var names: Array = args.map(func(a: Dictionary) -> String: return a["name"])
		check(names == M9_SIGNALS[sig], "%s arguments %s" % [sig, names])
		for a: Dictionary in args:
			check(int(a["type"]) != TYPE_NIL, "%s.%s is typed" % [sig, a["name"]])


func test_playtest_records_m9_signals() -> void:
	_record()
	EventBus.achievement_unlocked.emit("first_blood", false)
	EventBus.challenge_started.emit("br_krail", 1)
	EventBus.challenge_finished.emit("br_krail", 0, 3600, 2, true)
	EventBus.challenge_reset.emit("br_krail", &"menu")
	EventBus.challenge_stage_cleared.emit("null_descent", "static_lane", 900, 0, 0, 3)
	EventBus.speedrun_split.emit("collector", 1800, -60)
	EventBus.ng_plus_started.emit(1)
	EventBus.input_bindings_changed.emit(&"jump")
	EventBus.assist_suggested.emit("boss:warden_krail", "boss", 5)
	EventBus.assist_suggestion_answered.emit("boss:warden_krail", &"later", "")
	EventBus.locale_changed.emit("en_XA")
	EventBus.demo_boundary_reached.emit("res://a.tscn", "res://b.tscn")
	for t in ["achievement", "challenge_start", "challenge_end", "challenge_reset", "challenge_stage", "split",
			"ng_plus", "rebind", "assist_suggested", "assist_answered", "locale", "demo_end"]:
		check(_events(t).size() == 1, "one '%s' event (%d)" % [t, _events(t).size()])
	var end: Array = _events("challenge_end")
	if not end.is_empty():
		var e: Dictionary = end[0]
		check(e.get("id") == "br_krail" and int(e.get("medal", -9)) == 2 and e.get("new_best") == true, "challenge_end payload %s" % [e])


## CrossRules X-3 today: every EventBus signal is recorded by Playtest or
## listed in UNRECORDED_SIGNALS with a reason.
func test_x3_scan_clean_today() -> void:
	var src := FileAccess.get_file_as_string("res://autoload/Playtest.gd")
	var unrecorded: Dictionary = Playtest.UNRECORDED_SIGNALS
	for s in (EventBus.get_script() as GDScript).get_script_signal_list():
		var sig: String = s["name"]
		var connected := src.contains("EventBus.%s." % sig)
		var listed := unrecorded.has(sig) and str(unrecorded[sig]).strip_edges() != ""
		check(connected or listed, "EventBus.%s is neither recorded nor listed in UNRECORDED_SIGNALS" % sig)
		check(not (connected and unrecorded.has(sig)), "%s is recorded AND listed as unrecorded" % sig)


# --- Stubs, autoloads, directories (T01c) --------------------------------------------

## Every M9 directory a later task names exists (with a .gdkeep), so no
## literal res:// path to it is ever a broken reference.
const M9_DIRS := ["platform", "challenges", "accessibility", "input", "l10n", "release", "locale",
	"world/rooms/challenge", "world/challenge", "world/remix", "data/achievements", "data/challenges",
	"data/challenges/kits", "data/challenges/splits", "data/challenges/ghosts", "data/challenges/waves",
	"data/platform", "data/settings", "data/input", "data/accessibility", "data/l10n", "data/release",
	"data/ngplus", "data/remix", "ui/menus/dev", "devtools/content/rules", "devtools/dev_actions", "devtools/l10n"]
const STUBS := ["res://autoload/Platform.gd", "res://autoload/Challenges.gd", "res://release/BuildInfo.gd",
	"res://release/DemoGate.gd", "res://release/BuildProbe.gd", "res://l10n/Loc.gd",
	"res://progression/NewGamePlus.gd", "res://world/remix/RemixLibrary.gd", "res://progression/AtomicJson.gd"]
## save_fields.settings_keys_new: key -> default.
const SETTINGS_CONTRACT := {
	"ui_volume": 0.8, "high_contrast": false, "colorblind_mode": 0, "background_dim": 0, "ui_scale": 0,
	"aim_assist": 0, "damage_assist": 0, "burnout_hurts": true, "generous_checkpoints": false, "jump_hold_mode": 0,
	"map_hints": 1, "assist_suggestions": true, "pad_glyphs": 0, "bindings": {}, "achievement_toasts": true,
	"locale": "", "speedrun_timer": 0, "challenge_ghost": 1, "fast_reset_hold": true, "text_auto_advance": 0,
}


func test_m9_dirs_exist() -> void:
	for d: String in M9_DIRS:
		check(DirAccess.dir_exists_absolute("res://" + d), "res://%s exists" % d)


func test_stub_scripts_load_and_are_inert() -> void:
	for path: String in STUBS:
		var s := load(path) as GDScript
		check(s != null and s.can_instantiate(), "%s loads" % path)
	for path: String in ["res://autoload/Platform.gd", "res://autoload/Challenges.gd"]:
		# An autoload's script must not declare a class_name (4.3 parse error).
		check((load(path) as GDScript).get_global_name() == "", "%s declares no class_name" % path)
	check(not Platform.is_unlocked("x") and Platform.unlocked_ids().is_empty() and not Platform.earning_allowed(), "Platform is inert")
	check(not Challenges.active() and Challenges.current_id() == "" and not Challenges.finishing(), "Challenges is inert")
	check(BuildInfo.kind() == "full" and not BuildInfo.is_demo() and BuildInfo.room_allowed("res://x.tscn"), "full build")
	BuildInfo.set_force_demo(1)
	check(BuildInfo.is_demo() and BuildInfo.kind() == "demo", "force_demo seam")
	BuildInfo.set_force_demo(-1)
	check(Loc.t("Hello") == "Hello" and Loc.f("A {x}", {"x": "B"}) == "A B", "Loc returns the source")
	check(Loc.tn("{n} run", "{n} runs", 2) == "2 runs" and Loc.tn("{n} run", "{n} runs", 1) == "1 run", "Loc.tn plural")
	check(NewGamePlus.cycle_label(0) == "" and NewGamePlus.cycle_label(1) == "NG+" and NewGamePlus.cycle_label(3) == "NG+3", "cycle labels")
	check(NewGamePlus.cycle_of({"flags": {"ng_cycle": 2.0}}) == 2, "cycle_of casts JSON floats")
	var inst := Node.new()
	check(RemixLibrary.apply(inst, "res://x.tscn") == 0, "no remix ops")
	inst.free()
	check(BuildProbe.info()["kind"] == "full", "build probe info")


func test_settings_contract_keys_exist() -> void:
	for k: String in SETTINGS_CONTRACT:
		check(k in Settings, "Settings.%s exists" % k)
	var snap := Settings.snapshot()
	Settings.apply_defaults()
	for k: String in SETTINGS_CONTRACT:
		check(k in Settings and Settings.get(k) == SETTINGS_CONTRACT[k], "Settings.%s defaults to %s" % [k, SETTINGS_CONTRACT[k]])
	check(Settings.active_assists().is_empty(), "no assists in use")
	check(not snap.has("_path") and not snap.has("first_run") and not snap.has("_locale_override")
		and not snap.has("_subtitle_size_override"), "snapshot skips session-only fields")
	Settings.restore(snap)


func test_settings_snapshot_restore_roundtrip() -> void:
	var snap := Settings.snapshot()
	var path := Settings._path
	Settings.ui_scale = 2
	Settings.locale = "en_XA"
	Settings.high_contrast = true
	Settings.subtitle_size = 2
	Settings.apply_defaults()
	check(Settings.ui_scale == 0 and Settings.locale == "" and not Settings.high_contrast and Settings.subtitle_size == 0, "defaults applied")
	check(Settings._path == path, "apply_defaults keeps the session path")
	Settings.restore(snap)
	check(Settings.snapshot() == snap, "restore puts every key back")


func test_ui_cancel_has_backspace() -> void:
	var keys: Array[int] = []
	var pad_b := false
	for ev in InputMap.action_get_events(&"ui_cancel"):
		if ev is InputEventKey:
			keys.append((ev as InputEventKey).physical_keycode)
		elif ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == JOY_BUTTON_B:
			pad_b = true
	check(KEY_ESCAPE in keys and KEY_BACKSPACE in keys and pad_b, "ui_cancel lists Esc, Backspace and pad B (%s)" % [keys])
	var pause_keys: Array[int] = []
	for ev in InputMap.action_get_events(&"pause"):
		if ev is InputEventKey:
			pause_keys.append((ev as InputEventKey).physical_keycode)
	check(KEY_ESCAPE in pause_keys and KEY_P in pause_keys, "pause has Esc and P (%s)" % [pause_keys])


func test_playtest_challenge_room_clears_room() -> void:
	_record()
	SceneRouter.goto_room(ROOM_A, &"start")
	await physics_frames(3)
	check(Playtest._room == "WorldA", "a world room is tracked (%s)" % Playtest._room)
	var enters := _events("room_enter").size()
	Challenges.force_active = true
	SceneRouter.goto_room(ROOM_A, &"start")
	await physics_frames(3)
	check(Playtest._room == "", "a challenge room clears the tracked room")
	check(_events("room_enter").size() == enters, "no room_enter inside a run")
	var exits := _events("room_exit").size()
	Challenges.force_active = false
	SceneRouter.goto_room(ROOM_A, &"start")
	await physics_frames(3)
	check(_events("room_exit").size() == exits, "leaving the challenge room logs no second room_exit")
	check(_events("room_enter").size() == enters + 1, "back in the world: room_enter again")


func test_world_transition_frames_keep_leaving_room() -> void:
	_record()
	SceneRouter.goto_room(ROOM_A, &"start")
	await physics_frames(3)
	EventBus.room_leaving.emit(SceneRouter.current_room)
	EventBus.hint_requested.emit("between rooms", 1.0)
	var hints: Array = _events("hint")
	check(not hints.is_empty() and hints[-1]["room"] == "WorldA", "an event between room_leaving and room_entered keeps the leaving room (%s)" % [hints])
	var exits: Array = _events("room_exit")
	check(exits.size() == 1 and exits[0]["room"] == "WorldA", "one room_exit for the leaving room")


func test_playtest_variant_skipped_in_run() -> void:
	Settings.playtest_variant = "strong_slide_jump"
	Settings.playtest_recording = true
	Playtest.dir = TEST_DIR
	Playtest.allow_headless = true
	Playtest.begin_session("new")
	check(Playtest.variant != null and not Playtest.variant.movement_overrides.is_empty(), "a variant with overrides is active")
	Challenges.force_active = true
	SceneRouter.goto_room(ROOM_A, &"start")
	await physics_frames(2)
	var p := (SceneRouter.current_room as Room).player
	check(p.config.resource_path != "", "inside a run the player keeps the shipped movement config")
	Challenges.force_active = false
	SceneRouter.goto_room(ROOM_A, &"start")
	await physics_frames(2)
	p = (SceneRouter.current_room as Room).player
	check(p.config.resource_path == "", "outside a run the variant applies (a copy)")


# --- Game, Room, SceneRouter, BossArena seams (T01d) ---------------------------------

func test_held_profile_redirects_save() -> void:
	var profile := GameState.new()
	profile.scrap_banked = 77
	Game.state.scrap_banked = 5  # the sandbox run state
	Game.held_profile = profile
	check(Game.save_game() == OK, "saved")
	Game.held_profile = null
	var data := SaveManager.load_profile(1)
	check(int(data.get("scrap_banked", -1)) == 77, "the file holds the held profile, never the sandbox (%s)" % data.get("scrap_banked"))
	check(Game.save_game() == OK and int(SaveManager.load_profile(1).get("scrap_banked", -1)) == 5, "without a held profile the live state saves")


func test_null_open_derived_on_load_and_flag() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE_V3))
	(raw["flags"] as Dictionary)["act1_complete"] = true
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open(SaveManager.profile_path(1), FileAccess.WRITE)
	f.store_string(JSON.stringify(raw))
	f.close()
	check(Game.load_game(1), "fixture loads")
	check(Game.has_flag("null_open"), "a pre-M9 save past Act I derives null_open on load")
	Game.new_game()
	check(not Game.has_flag("null_open"), "a new game has no null_open")
	Game.set_flag("act1_complete", false)
	check(not Game.has_flag("null_open"), "a false source flag derives nothing")
	Game.set_flag("act1_complete", true)
	check(Game.has_flag("null_open"), "setting act1_complete sets null_open")


func test_death_override_handles_death() -> void:
	SceneRouter.goto_room(ROOM_A, &"start")
	await physics_frames(3)
	var room := SceneRouter.current_room as Room
	var calls: Array = []
	room.death_override = func(p: Player) -> bool:
		calls.append(p)
		return true
	var deaths := Game.state.deaths
	room.player.combat.take_damage(999, Vector2.ZERO, 0.0, false, "test")
	await physics_frames(90)
	check(calls.size() == 1, "the override saw the death once (%d)" % calls.size())
	check(Game.state.deaths == deaths, "no Game.on_player_death")
	check(SceneRouter.current_room == room and not SceneRouter.transitioning, "no respawn transition")


func test_leave_capture_suppressed() -> void:
	SceneRouter.goto_room(ROOM_A, &"start")
	await physics_frames(3)
	var room := SceneRouter.current_room as Room
	Game.state.health = -1
	room.player.combat.health = 1
	Game.suppress_leave_capture = true
	SceneRouter.goto_room(ROOM_A, &"start")
	await physics_frames(2)
	check(Game.state.health == -1, "a suppressed leave never captures the player (%d)" % Game.state.health)
	Game.suppress_leave_capture = false
	(SceneRouter.current_room as Room).player.combat.health = 2
	SceneRouter.goto_room(ROOM_A, &"start")
	await physics_frames(2)
	check(Game.state.health == 2, "a normal leave captures (%d)" % Game.state.health)


func test_scene_router_demo_refusal_emits() -> void:
	SceneRouter.goto_room(ROOM_A, &"start")
	await physics_frames(2)
	var seen: Array = []
	var on_boundary := func(from: String, to: String) -> void: seen.append([from, to])
	EventBus.demo_boundary_reached.connect(on_boundary)
	BuildInfo.force_allowed["res://tests/fixtures/WorldB.tscn"] = false
	SceneRouter.transition_to("res://tests/fixtures/WorldB.tscn")
	check(not SceneRouter.transitioning, "the refused transition never starts")
	check(seen == [[ROOM_A, "res://tests/fixtures/WorldB.tscn"]], "demo_boundary_reached(from, to) (%s)" % [seen])
	DemoGate.dev_bypass = true
	SceneRouter.transition_to("res://tests/fixtures/WorldB.tscn")
	check(SceneRouter.transitioning, "the dev bypass walks past the boundary")
	while SceneRouter.transitioning:
		await get_tree().process_frame
	check(SceneRouter.current_room_path == "res://tests/fixtures/WorldB.tscn", "bypassed room loaded")
	EventBus.demo_boundary_reached.disconnect(on_boundary)


func test_boss_arena_id_of_matches_playtest() -> void:
	_record()
	SceneRouter.goto_room("res://tests/fixtures/boss_collector_arena.tscn")
	await physics_frames(2)
	var arena := SceneRouter.current_room.find_children("*", "BossArena", true, false)[0] as BossArena
	check(arena.boss != null, "the fixture has a boss")
	check(BossArena.id_of(arena.boss) == arena.boss_id and arena.boss_id != "", "id_of finds the arena's boss_id")
	var stray := Node2D.new()
	check(BossArena.id_of(stray) == "", "an unknown boss has no id")
	stray.free()
	EventBus.boss_started.emit(arena.boss, "TEST")
	var starts: Array = _events("boss_start")
	check(not starts.is_empty() and starts[-1]["id"] == arena.boss_id, "Playtest records the same id (%s)" % [starts])


func test_start_campaign_sets_igt_complete() -> void:
	Game.new_game()
	check(not Game.state.igt_complete, "new_game alone leaves igt_complete false")
	for enforce in [true, false]:
		var c := (Game.ONBOARDING as OnboardingConfig).duplicate() as OnboardingConfig
		c.enforce = enforce
		Game.onboarding = c
		Game.start_campaign()
		check(Game.state.igt_complete, "start_campaign sets igt_complete (enforce %s)" % enforce)
	Game.onboarding = Game.ONBOARDING


# --- Menus: registry, title, pause, dev hub, overlay, tour session (T01e) ------------

var _main: Node


## A full Main scene (menus, HUD, viewport). start_room "" boots to the title.
func _boot_main(start_room: String) -> MenuHost:
	_main = (load("res://Main.tscn") as PackedScene).instantiate()
	_main.set("start_room", start_room)
	_extra(_main)
	await physics_frames(3)
	return _main.get_node("Menus") as MenuHost


func _title_of(host: MenuHost) -> MenuScreen:
	return host.get_node("TitleMenu") as MenuScreen


func _labels(menu: MenuScreen) -> Array:
	var out: Array = []
	for c in menu._body.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append((c as Button).text)
	return out


func _button(menu: MenuScreen, text: String) -> Button:
	for c in menu._body.get_children():
		if c is Button and not c.is_queued_for_deletion() and (c as Button).text == text:
			return c as Button
	return null


func _bare_title() -> MenuScreen:
	var t: MenuScreen = load("res://ui/menus/TitleMenu.gd").new()
	_extra(t)
	t.open_menu()
	return t


func test_m9_scripts_load() -> void:
	for path: String in ["res://ui/debug/DebugOverlay.gd", "res://ui/menus/DevConsole.gd", "res://ui/menus/PauseMenu.gd",
			"res://ui/menus/MenuHost.gd", "res://ui/UiTheme.gd"] + STUBS:
		var s := load(path) as GDScript
		check(s != null and s.can_instantiate(), "%s loads" % path)
	for n: String in ["BuildInfo", "DemoGate", "BuildProbe", "Loc", "NewGamePlus", "RemixLibrary", "AtomicJson",
			"MenuHost", "PauseMenu", "DevConsole", "DebugOverlay"]:
		var found := ProjectSettings.get_global_class_list().any(func(c: Dictionary) -> bool: return c["class"] == n)
		check(found, "class_name %s is registered" % n)
	for path: String in ["res://autoload/Platform.gd", "res://autoload/Challenges.gd"]:
		check((load(path) as GDScript).get_global_name() == "", "%s declares no class_name" % path)


func test_map_refused_when_challenge_active() -> void:
	SceneRouter.goto_room(ROOM_A, &"start")
	await physics_frames(2)
	check(MenuHost.can_open(&"map", false, false), "map opens in a world room")
	Challenges.force_active = true
	check(not MenuHost.can_open(&"map", false, false), "no map inside a challenge run (D-151)")
	check(MenuHost.can_open(&"pause", false, false), "pause still opens in a run")


func test_open_when_free_opens_after_close() -> void:
	var host := await _boot_main(ROOM_A)
	check(host.open(&"pause"), "pause opens")
	host.open_when_free(&"journal", {"k": 1})
	check(not host.journal.is_open(), "queued while pause is open")
	host.pause.close_menu()
	check(host.journal.is_open(), "the queued screen opens once the last menu closes")
	check(host.journal.ctx == {"k": 1}, "with its context (%s)" % [host.journal.ctx])
	host.journal.close_menu()


func test_open_refused_clears_context() -> void:
	var host := await _boot_main(ROOM_A)
	host.open(&"pause")
	host.open_with(&"journal", {"stale": true})
	check(not host.journal.is_open(), "refused over an open menu")
	check(MenuHost.context.is_empty(), "a refused open clears the context")
	check(not host.open(&"no_such_menu") and MenuHost.context.is_empty(), "unknown ids are refused")
	host.pause.close_menu()


func test_pause_refused_while_finishing() -> void:
	SceneRouter.goto_room(ROOM_A, &"start")
	await physics_frames(2)
	Challenges.force_finishing = true
	check(not MenuHost.can_open(&"pause", false, false), "no pause between a run's end and its result card")
	Challenges.force_finishing = false
	check(MenuHost.can_open(&"pause", false, false), "pause opens again")


func test_menu_host_copies_context_to_screen() -> void:
	var host := await _boot_main(ROOM_A)
	host.open_with(&"journal", {"return_to": &"pause"})
	check(MenuHost.context.is_empty(), "the host context is cleared after open")
	check(host.journal.ctx == {"return_to": &"pause"}, "the screen keeps its copy")
	host.journal.rebuild()
	check(host.journal.ctx == {"return_to": &"pause"}, "and still has it after a rebuild")
	host.journal.close_menu()


func test_menu_host_registry_ids() -> void:
	var host := await _boot_main(ROOM_A)
	for id: String in ["loadout", "pause", "journal", "settings", "slice_end", "moment", "survey", "map", "dev"]:
		check(host.has_screen(StringName(id)), "screen %s registered" % id)
		check(MenuHost.IDS.has(id), "IDS lists %s" % id)
	check(host.is_in_group(&"menu_host"), "the host is findable by group")


func test_title_fits_270_all_rows() -> void:
	var snap := Settings.snapshot()
	Settings.first_run = true
	Game.state.last_anchor_room = ROOM_A
	Game.save_game()
	var t := _bare_title()
	await get_tree().process_frame
	var labels := _labels(t)
	check(labels.has("Comfort & accessibility") and labels.has("Continue") and labels.has("New Game"), "rows %s" % [labels])
	check(labels.has("Labs & dev starts…") == OS.is_debug_build(), "labs row in debug builds")
	check(not labels.has("Combat Lab") and not labels.has("Slice (Relay start)"), "labs moved to the sub-page")
	var h := await menu_height(t)
	check(h <= 270.0, "title is %.0f px tall" % h)
	check(t.focused_index() == 1, "focus starts on Continue, never the first-run row (%d)" % t.focused_index())
	Settings.first_run = false
	Settings.restore(snap)


func test_title_labs_subpage_back() -> void:
	var t := _bare_title()
	if not OS.is_debug_build():
		return
	var labs := _button(t, "Labs & dev starts…")
	check(labs != null, "labs row")
	labs.pressed.emit()
	var labels := _labels(t)
	check(labels.has("Slice (Relay start)") and labels.has("Combat Lab") and labels.has("Movement Lab") and labels.has("Back"), "labs page %s" % [labels])
	await physics_frames(1)
	await press_action(&"ui_cancel", 2)
	check(_labels(t).has("New Game"), "ui_cancel returns to the main page")
	check((_body_buttons(t)[t.focused_index()] as Button).text == "Labs & dev starts…", "focus back on the labs row")
	await press_action(&"ui_cancel", 2)
	check(t.is_open() and _labels(t).has("New Game"), "ui_cancel does nothing on the main page")


func _body_buttons(m: MenuScreen) -> Array:
	return m._body.get_children().filter(func(n: Node) -> bool: return n is Button and not n.is_queued_for_deletion())


func test_first_run_row_gone_after_new_game() -> void:
	var snap := Settings.snapshot()
	var path := Settings._path
	Settings._path = TEST_DIR + "/settings.cfg"
	Settings.first_run = true
	var t := _bare_title()
	check(_labels(t).has("Comfort & accessibility"), "first run shows the row")
	var c := (Game.ONBOARDING as OnboardingConfig).duplicate() as OnboardingConfig
	c.enforce = true
	c.campaign_start_room = ROOM_A
	c.campaign_start_entry = &"start"
	Game.onboarding = c
	_button(t, "New Game").pressed.emit()
	check(not Settings.first_run, "the first title action retires the row")
	check(not FileAccess.file_exists(TEST_DIR + "/settings.cfg"), "only the real settings path is written")
	t.open_menu()
	check(not _labels(t).has("Comfort & accessibility"), "the row is gone")
	while SceneRouter.transitioning:
		await get_tree().process_frame
	Settings._path = path
	Settings.restore(snap)


func test_settings_back_from_title_refocuses_settings_row() -> void:
	var host := await _boot_main("")
	var t := _title_of(host)
	check(t.is_open(), "title up")
	var settings_row := _labels(t).find("Settings")
	t.focus_index(settings_row)
	_button(t, "Settings").pressed.emit()
	check(host.settings.is_open(), "settings open over the title")
	var closes: Array = []
	host.settings.closed.connect(func() -> void: closes.append(1))
	host.settings.close_menu()
	await get_tree().process_frame
	check(t.focused_index() == settings_row, "focus returns to the Settings row (%d, want %d)" % [t.focused_index(), settings_row])
	var handlers := host.settings.closed.get_connections().size()
	check(handlers == 2, "one host handler plus this test's (%d)" % handlers)


func test_pause_run_rows_with_force_active() -> void:
	SceneRouter.goto_room(ROOM_A, &"start")
	await physics_frames(2)
	var pm: MenuScreen = _extra(load("res://ui/menus/PauseMenu.gd").new())
	pm.open_menu()
	check(_labels(pm).has("Map") and _labels(pm).has("Save & Quit to Title"), "normal rows %s" % [_labels(pm)])
	pm.close_menu()
	Challenges.force_active = true
	pm.open_menu()
	var labels := _labels(pm)
	check(labels.has("Resume") and labels.has("Restart") and labels.has("Settings") and labels.has("Quit challenge"), "run rows %s" % [labels])
	check(labels.any(func(l: String) -> bool: return l.begins_with("Ghost: ")), "ghost row")
	check(not labels.has("Map") and not labels.has("Journal") and not labels.has("Save & Quit to Title"), "no map, journal or save in a run")
	check(not labels.has("Restart descent"), "no descent restart without stages")
	pm.close_menu()


func test_save_and_quit_emits_to_title_once() -> void:
	var host := await _boot_main(ROOM_A)
	var t := _title_of(host)
	var opens: Array = []
	var early: Array = []
	var watch := func() -> void:
		if t.visible:
			opens.append(1)
			if SceneRouter.transitioning:
				early.append(1)
	t.visibility_changed.connect(watch)
	check(host.open(&"pause"), "pause opens")
	(host.pause as PauseMenu)._quit()
	for i in 120:
		await get_tree().process_frame
		if not SceneRouter.transitioning and t.visible:
			break
	check(opens.size() == 1, "the title opens once (%d)" % opens.size())
	check(early.is_empty(), "only after the transition")
	check(FileAccess.file_exists(SaveManager.profile_path(1)), "Save & Quit saved")


func test_dev_console_main_rows_le_page_rows() -> void:
	var c: DevConsole = _extra(load("res://ui/menus/DevConsole.gd").new())
	c.open_menu()
	check(_labels(c).has("Endgame & build…"), "main page has the endgame hub")
	check(_labels(c).size() <= DevConsole.PAGE_ROWS, "main page rows %d <= %d" % [_labels(c).size(), DevConsole.PAGE_ROWS])
	var h := await menu_height(c)
	check(h <= 270.0, "main page %.0f px" % h)
	c.close_menu()


func test_endgame_hub_fits() -> void:
	var c: DevConsole = _extra(load("res://ui/menus/DevConsole.gd").new())
	c.open_menu()
	c.go(&"endgame")
	var labels := _labels(c)
	check(labels.has("Endgame state: Act I complete") and labels.has("Back") and labels.has("Close"), "hub rows %s" % [labels])
	check(labels.size() <= DevConsole.PAGE_ROWS + 2, "hub rows fit")
	var h := await menu_height(c)
	check(h <= 270.0, "hub %.0f px" % h)
	c.set_detail("detail")
	check(c._detail != null and c._detail.text == "detail", "set_detail")
	c.close_menu()


func test_debug_overlay_providers() -> void:
	DebugOverlay.clear_cache()
	var p := func() -> PackedStringArray: return PackedStringArray(["M9 LINE"])
	DebugOverlay.providers.append(p)
	check(DebugOverlay.provider_lines().has("M9 LINE"), "provider lines drawn")
	var owner := Node.new()
	DebugOverlay.providers.append(Callable(owner, "get_class"))
	owner.free()
	DebugOverlay.provider_lines()
	check(DebugOverlay.providers.size() == 1, "invalid providers are removed (%d)" % DebugOverlay.providers.size())
	DebugOverlay.clear_cache()
	check(DebugOverlay.providers.is_empty(), "clear_cache empties the list")


func test_capture_session_resets_and_restores_m9_keys() -> void:
	var tour: GDScript = load("res://devtools/CaptureTour.gd")
	var none := PackedStringArray()
	var before := Settings.snapshot()
	Settings.ui_scale = 2
	Settings.locale = "en_XA"
	Settings.high_contrast = true
	var snap: Dictionary = tour.prepare_session("slice", none)
	check(Settings.ui_scale == 0 and Settings.locale == "" and not Settings.high_contrast, "M9 keys at defaults")
	check(not Settings.achievement_toasts and not Settings.assist_suggestions and not Settings.first_run, "no toasts, offers or first run")
	check(Platform.store_dir == "user://tour_sandbox/platform" and Platform.allow_headless, "platform store redirected")
	check(Challenges.quiet_notices, "group notices quiet")
	tour.restore_session(snap)
	check(Settings.ui_scale == 2 and Settings.locale == "en_XA" and Settings.high_contrast, "originals restored")
	check(Platform.store_dir == "user://platform" and not Platform.allow_headless and not Challenges.quiet_notices, "platform reset")
	CinematicMode.set_mode(CinematicMode.Mode.INSTANT)
	Settings.restore(before)


func test_capture_session_keeps_tour_path_and_subtitle_override() -> void:
	var tour: GDScript = load("res://devtools/CaptureTour.gd")
	var none := PackedStringArray()
	var override := Settings._subtitle_size_override
	var path := Settings._path
	Settings._subtitle_size_override = 2
	var snap: Dictionary = tour.prepare_session("slice", none)
	check(Settings._path == tour.TOUR_SETTINGS_PATH, "settings save to the tour file")
	check(Settings._subtitle_size_override == 2, "the --subtitle-size override survives prepare")
	tour.restore_session(snap)
	check(Settings._path == path, "path restored")
	Settings._subtitle_size_override = override
	CinematicMode.set_mode(CinematicMode.Mode.INSTANT)


func test_capture_session_wipes_tour_sandbox() -> void:
	var tour: GDScript = load("res://devtools/CaptureTour.gd")
	var none := PackedStringArray()
	AtomicJson.write("user://tour_sandbox/platform/stale.json", {"x": 1})
	var snap: Dictionary = tour.prepare_session("slice", none)
	check(not FileAccess.file_exists("user://tour_sandbox/platform/stale.json"), "a stale sandbox file is wiped")
	tour.restore_session(snap)
	check(not DirAccess.dir_exists_absolute("user://tour_sandbox"), "restore leaves no user://tour_sandbox")
	CinematicMode.set_mode(CinematicMode.Mode.INSTANT)


# --- ContentValidator, FlagSandbox, DevActions (T01f) --------------------------------

func test_menu_host_registry_ids_match_validator() -> void:
	check(Array(MenuHost.IDS) == Array(ContentValidator.MENU_IDS), "MenuHost.IDS == ContentValidator.MENU_IDS")
	for id: StringName in MenuHost.M9_SCREENS:
		check(MenuHost.IDS.has(String(id)), "M9 screen %s is a known id" % id)


func test_rule_modules_absent_is_ok() -> void:
	var v := ContentValidator.new()
	var before := v.errors.size()
	v.validate_m9()
	v.validate_m9(true)
	check(v.errors.size() == before and v.warnings.is_empty(), "no modules, no findings (%s)" % [v.errors])
	check(ContentValidator.RULE_MODULES.size() == 11, "eleven rule module slots")


func test_m9_dirs_exist_and_validator_clean() -> void:
	for d: String in M9_DIRS:
		check(DirAccess.dir_exists_absolute("res://" + d), "res://%s exists" % d)
	var v := ContentValidator.new()
	v.scan_references()
	var missing := Array(v.errors).filter(func(e: String) -> bool: return e.begins_with("broken reference"))
	check(missing.is_empty(), "no broken res:// reference: %s" % [missing])
	for d in ["res://platform", "res://challenges", "res://release", "res://accessibility", "res://input", "res://l10n"]:
		check(ContentValidator.SCAN_DIRS.has(d), "%s is scanned" % d)
	check(ContentValidator._off_map("res://world/rooms/challenge/NullFloor.tscn") and not ContentValidator._off_map("res://world/rooms/lowlight/Relay.tscn"),
		"challenge rooms are off the world map")


func test_validator_public_helpers() -> void:
	var v := ContentValidator.new()
	v.add_producer("m9_test_flag", "res://x/a.tres")
	v.add_consumer("m9_test_flag", "res://x/b.tres")
	v.consume_condition("flag:m9_other", "res://x/c.tres")
	check(v.producers["m9_test_flag"] == ["res://x/a.tres"] and v.consumed.has("m9_other"), "producers and consumers registered")
	v.add_shown_text("res://x/d.tres", "test", "shown line")
	check(v.extra_shown_text == [["res://x/d.tres", "test", "shown line"]], "shown text registered")
	var room := v.instantiate_room(ROOM_A)
	check(room is Room, "instantiate_room")
	room.free()


func test_dev_taint_set_by_unlock_all() -> void:
	check(not Game.state.dev_tainted, "a new game is clean")
	DevActions.unlock_all()
	check(Game.state.dev_tainted, "unlock_all taints the profile (D-145)")
	Game.new_game()
	DevActions.apply_story_preset("act1_complete")
	check(Game.state.dev_tainted, "a story preset taints")
	Game.new_game()
	DevActions.apply_endgame_state()
	check(Game.state.dev_tainted and Game.has_flag("act1_complete") and Game.has_flag("null_open"), "endgame state: Act I complete, null_open derived")


func test_satisfy_ending_does_not_taint() -> void:
	var restore := DevActions.satisfy_ending("crown")
	check(not Game.state.dev_tainted, "satisfy_ending runs in a FlagSandbox and does not taint")
	restore.call()


func test_flag_sandbox_restores_dev_tainted() -> void:
	var restore := FlagSandbox.begin()
	Game.state.dev_tainted = true
	restore.call()
	check(not Game.state.dev_tainted, "the sandbox puts the taint back")


func test_act1_max_state_leaves_ng_demo_unset() -> void:
	FlagSandbox.apply_act1_max_state()
	check(Game.state.dev_tainted, "the max state is dev-tainted")
	check(Game.has_flag("null_open"), "null_open is derived from act1_complete (D-154)")
	check(not Game.state.flags.has("ng_cycle"), "no ng_cycle")
	for f: String in Game.state.flags:
		check(not f.begins_with("ng_") and not f.begins_with("demo_"), "M9 system flag %s set" % f)
		check(not f.begins_with("null_") or f == "null_open", "null flag %s set" % f)
