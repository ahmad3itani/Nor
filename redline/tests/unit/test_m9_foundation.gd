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
	get_tree().paused = false
	Playtest.end_session("test_done")
	Playtest.allow_headless = false
	Playtest.dir = Playtest.DIR
	Settings.playtest_recording = _saved_recording
	Settings.playtest_variant = _saved_variant
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
	check(RemixLibrary.apply(Node.new(), "res://x.tscn") == 0, "no remix ops")
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
