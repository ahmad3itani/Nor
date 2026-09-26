extends RedlineTestCase
## M9 D6: BuildInfo (what build this is, what a demo allows) and the demo
## save isolation (D-165). The TestRunner teardown calls set_force_demo(-1)
## after every test; these tests also restore what they touch.

const UNDERCITY := "res://world/rooms/undercity"
const LOWLIGHT := "res://world/rooms/lowlight"
const RELAY := "res://world/rooms/lowlight/Relay.tscn"
const LABS := ["res://world/rooms/CombatLab.tscn", "res://world/rooms/MovementLab.tscn"]

var _saved: Dictionary = {}


func before_each() -> void:
	# Every redirect only replaces a default, so start from the defaults.
	_saved = {"save": SaveManager.save_dir, "platform": Platform.store_dir, "settings": Settings._path,
		"playtest": Playtest.dir, "recording": Settings.playtest_recording}
	SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR
	Platform.store_dir = "user://platform"
	Settings._path = Settings.SETTINGS_PATH
	Playtest.dir = Playtest.DIR


func after_each() -> void:
	BuildInfo.set_force_demo(-1)
	SaveManager.save_dir = _saved["save"]
	Platform.store_dir = _saved["platform"]
	Settings._path = _saved["settings"]
	Playtest.dir = _saved["playtest"]
	Settings.playtest_recording = _saved["recording"]


func test_default_is_full_in_tests() -> void:
	check(not BuildInfo.is_demo() and BuildInfo.kind() == "full", "tests run the full game")
	check(BuildInfo.demo() == null, "no demo config in the full game")
	check(BuildInfo.config() is DemoConfig, "the shipped demo config loads (%s)" % BuildInfo.DEMO_CONFIG_PATH)
	check(BuildInfo.room_allowed(RELAY), "every room allowed")
	check(BuildInfo.recording_default(), "recording defaults on in the full game")
	check(BuildInfo.title_tag() == "", "no title tag")
	check(BuildInfo.title_subtitle() == Game.onboarding.title_subtitle, "full title subtitle from onboarding")
	check(not BuildInfo.redirects_dirs(), "the full game keeps its dirs")


func test_force_demo_toggles_and_clears_caches() -> void:
	SliceStats.totals()
	var builds := SliceStats.build_count
	var full_secrets := (SliceStats.totals()["secret_ids"] as Array).size()
	BuildInfo.set_force_demo(1)
	check(BuildInfo.is_demo() and BuildInfo.kind() == "demo", "force_demo 1 = demo")
	check(BuildInfo.demo() is DemoConfig, "demo() is the config in a demo")
	var demo_secrets := (SliceStats.totals()["secret_ids"] as Array).size()
	check(SliceStats.build_count == builds + 1, "the room totals were rebuilt for the demo")
	check(demo_secrets < full_secrets and demo_secrets > 0, "demo totals are the Undercity's (%d of %d)" % [demo_secrets, full_secrets])
	BuildInfo.set_force_demo(0)
	check(not BuildInfo.is_demo(), "force_demo 0 = full")
	check((SliceStats.totals()["secret_ids"] as Array).size() == full_secrets, "full totals again")
	BuildInfo._config = DemoConfig.new()
	BuildInfo.clear_cache()
	check(BuildInfo._config == null, "clear_cache drops the config")
	BuildInfo.set_force_demo(-1)
	check(BuildInfo.force_demo == -1 and not BuildInfo.is_demo(), "back to the real build")


func test_room_allowed_matrix() -> void:
	var undercity := DataDir.list_scenes(UNDERCITY)
	var lowlight := DataDir.list_scenes(LOWLIGHT)
	check(undercity.size() == 7 and lowlight.size() == 11, "7 Undercity and 11 Lowlight rooms (%d, %d)" % [undercity.size(), lowlight.size()])
	BuildInfo.set_force_demo(1)
	for p in undercity:
		check(BuildInfo.room_allowed(p), "demo allows %s" % p.get_file())
	check(BuildInfo.room_allowed("res://world/rooms/TitleBackdrop.tscn"), "demo allows the title backdrop")
	for p in Array(lowlight) + LABS:
		check(not BuildInfo.room_allowed(p), "demo refuses %s" % String(p).get_file())
	BuildInfo.force_allowed[RELAY] = true
	check(BuildInfo.room_allowed(RELAY), "force_allowed wins")
	BuildInfo.force_allowed.clear()
	BuildInfo.set_force_demo(0)
	for p in Array(undercity) + Array(lowlight) + LABS:
		check(BuildInfo.room_allowed(p), "full allows %s" % String(p).get_file())


func test_enabled_features() -> void:
	for f in BuildInfo.KNOWN_FEATURES:
		check(BuildInfo.enabled(f), "full: %s on" % f)
	BuildInfo.set_force_demo(1)
	for f: StringName in [&"labs", &"lab_cycle", &"relay_start", &"ngplus", &"null", &"transit"]:
		check(not BuildInfo.enabled(f), "demo: %s off" % f)
	check(BuildInfo.enabled(&"challenges"), "demo keeps challenges (the list is filtered instead)")
	check(BuildInfo.enabled(&"no_such_feature"), "an unknown feature warns and stays enabled")


func test_label_formats() -> void:
	var v := str(ProjectSettings.get_setting("application/config/version"))
	var debug := " (debug)" if OS.is_debug_build() else ""
	check(BuildInfo.version() == v, "version from project.godot")
	check(BuildInfo.label() == v + debug, "full label '%s'" % BuildInfo.label())
	BuildInfo.set_force_demo(1)
	check(BuildInfo.label() == v + " DEMO" + debug, "demo label '%s'" % BuildInfo.label())
	check(BuildInfo.title_tag() == "DEMO", "demo title tag")
	check(BuildInfo.title_subtitle() == BuildInfo.config().title_subtitle, "demo subtitle from the config")
	check(BuildInfo.info()["kind"] == "demo" and BuildInfo.info()["demo_id"] == "undercity", "info() %s" % [BuildInfo.info()])


func test_project_has_demo_user_dir_override() -> void:
	check(ProjectSettings.has_setting("application/config/custom_user_dir_name.demo"), "custom_user_dir_name.demo is set")
	check(ProjectSettings.has_setting("application/config/use_custom_user_dir.demo"), "use_custom_user_dir.demo is set")
	check(str(ProjectSettings.get_setting("application/config/custom_user_dir_name.demo")) == "REDLINE Demo", "the demo dir is 'REDLINE Demo'")
	# Without the demo feature the override does not apply: the base (empty) name.
	check(BuildInfo.expected_user_dir_name() == "", "editor run expects the default user dir ('%s')" % BuildInfo.expected_user_dir_name())


func test_can_quit_false_on_web_simulated() -> void:
	check(BuildInfo.can_quit(), "desktop can quit")
	BuildInfo.force_web = 1
	check(BuildInfo.is_web() and not BuildInfo.can_quit(), "web has no Quit")
	BuildInfo.force_web = 0
	check(not BuildInfo.is_web(), "force_web 0 = desktop")
	BuildInfo.set_force_demo(-1)
	check(BuildInfo.force_web == -1, "set_force_demo(-1) resets the web seam")


func test_slice_card_id_act_close() -> void:
	check(BuildInfo.slice_card_id() == &"slice_end", "full: the Act I card")
	BuildInfo.set_force_demo(1)
	check(BuildInfo.slice_card_id() == &"slice_end", "BORDER demo keeps the Act I card id")
	var c := (BuildInfo.config().duplicate() as DemoConfig)
	c.end_mode = DemoConfig.EndMode.ACT_CLOSE
	BuildInfo._config = c
	check(BuildInfo.slice_card_id() == &"demo_end", "ACT_CLOSE demo: the demo card replaces the Act I card")
	BuildInfo.set_force_demo(0)
	check(BuildInfo.slice_card_id() == &"slice_end", "full again")


## The redirect only replaces the autoloads' own defaults, so these must match.
func test_redirect_defaults_match_autoloads() -> void:
	check(BuildInfo.DEFAULT_SAVE_DIR == SaveManager.DEFAULT_SAVE_DIR, "save dir default")
	check(BuildInfo.DEFAULT_SETTINGS_PATH == Settings.SETTINGS_PATH, "settings path default")
	check(BuildInfo.DEFAULT_PLAYTEST_DIR == Playtest.DIR, "playtest dir default")
	Platform.reset_after_tests()
	check(BuildInfo.DEFAULT_PLATFORM_DIR == Platform.store_dir, "platform dir default")


## A debug --demo / forced session shares the full game's user dir, so it
## moves every file under user://demo/ and puts them back when it ends.
func test_force_demo_redirects_and_restores() -> void:
	Settings.playtest_recording = true
	BuildInfo.set_force_demo(1)
	check(SaveManager.save_dir == "user://demo/saves", "saves (%s)" % SaveManager.save_dir)
	check(Platform.store_dir == "user://demo/platform", "platform (%s)" % Platform.store_dir)
	check(Settings._path == "user://demo/settings.cfg", "settings (%s)" % Settings._path)
	check(Playtest.dir == "user://demo/playtests", "playtests (%s)" % Playtest.dir)
	check(not Settings.playtest_recording, "recording defaults off in a demo (D-039)")
	BuildInfo.set_force_demo(1)
	check(BuildInfo._applied.size() == 5, "idempotent (%d redirects)" % BuildInfo._applied.size())
	BuildInfo.set_force_demo(-1)
	check(SaveManager.save_dir == SaveManager.DEFAULT_SAVE_DIR and Platform.store_dir == "user://platform"
		and Settings._path == Settings.SETTINGS_PATH and Playtest.dir == Playtest.DIR, "every path restored")
	check(Settings.playtest_recording, "recording restored")


## A path a test (or tour) already pointed elsewhere is left alone.
func test_redirect_keeps_custom_dirs() -> void:
	SaveManager.save_dir = "user://test_build_info_saves"
	BuildInfo.set_force_demo(1)
	check(SaveManager.save_dir == "user://test_build_info_saves", "a custom save dir is kept")
	check(Platform.store_dir == "user://demo/platform", "defaults still move")
	BuildInfo.set_force_demo(-1)
	check(SaveManager.save_dir == "user://test_build_info_saves", "and never 'restored' to another value")


## R05.8: on Web user:// is the origin's storage and the per-feature user dir
## is ignored, so even a feature-tag demo redirects there; on desktop the
## feature-tag demo has its own user dir and redirects nothing.
func test_web_demo_redirects_dirs() -> void:
	BuildInfo.force_feature_tag = true
	BuildInfo.force_web = 0
	BuildInfo.set_force_demo(1)
	check(BuildInfo.is_demo() and not BuildInfo.redirects_dirs(), "desktop demo export: its own user dir")
	check(SaveManager.save_dir == SaveManager.DEFAULT_SAVE_DIR and Platform.store_dir == "user://platform"
		and Settings._path == Settings.SETTINGS_PATH and Playtest.dir == Playtest.DIR, "no redirect on desktop")
	BuildInfo.set_force_demo(-1)
	BuildInfo.force_feature_tag = true
	BuildInfo.force_web = 1
	BuildInfo.set_force_demo(1)
	check(BuildInfo.redirects_dirs(), "web demo redirects")
	check(SaveManager.save_dir == "user://demo/saves", "web saves (%s)" % SaveManager.save_dir)
	check(Platform.store_dir == "user://demo/platform", "web platform (%s)" % Platform.store_dir)
	check(Settings._path == "user://demo/settings.cfg", "web settings (%s)" % Settings._path)
	check(Playtest.dir == "user://demo/playtests", "web playtests (%s)" % Playtest.dir)
	BuildInfo.set_force_demo(-1)
	check(BuildInfo.force_web == -1 and not BuildInfo.force_feature_tag, "seams reset")
	check(SaveManager.save_dir == SaveManager.DEFAULT_SAVE_DIR and Platform.store_dir == "user://platform"
		and Settings._path == Settings.SETTINGS_PATH and Playtest.dir == Playtest.DIR, "all four restored")


## At boot Settings._ready redirects before the later autoloads are in the
## tree: those are set as they enter it, before their own _ready.
func test_redirect_waits_for_late_autoload() -> void:
	BuildInfo._redirect("BuildInfoLateProbe", "text", "redirected", "")
	check(BuildInfo._pending.has("BuildInfoLateProbe"), "pending until the node exists")
	var probe := Label.new()
	probe.name = "BuildInfoLateProbe"
	var seen: Array = []
	probe.ready.connect(func() -> void: seen.append(probe.text))
	get_tree().root.add_child(probe)
	check(seen == ["redirected"], "set before the node's _ready (%s)" % [seen])
	check(BuildInfo._pending.is_empty(), "nothing pending")
	BuildInfo._restore_dirs()
	check(probe.text == "", "restored")
	probe.queue_free()


## D-168 in a redirected demo: Settings decided first_run from the full
## game's settings.cfg; the demo's own file decides it instead, so a demo on
## an origin (or a dev machine) that already has full-game settings still
## shows the first-run row, and a demo that saved its file does not.
func test_demo_first_run_follows_demo_settings_file() -> void:
	var dir := "user://test_build_info_settings"
	var path := dir + "/settings.cfg"
	AtomicJson.remove_tree(dir)
	BuildInfo.set_force_demo(1)
	var s := (load("res://autoload/Settings.gd") as GDScript).new() as Node
	s.set("first_run", false)  # the full game's settings.cfg exists
	BuildInfo.load_demo_settings(s, path)
	check(bool(s.get("first_run")), "no demo settings file: first run")
	check(s.get("_path") == path, "reads and writes the demo file")
	check(not bool(s.get("playtest_recording")), "demo recording default applied")
	DirAccess.make_dir_recursive_absolute(dir)
	check(ConfigFile.new().save(path) == OK, "demo settings written")
	BuildInfo.load_demo_settings(s, path)
	check(not bool(s.get("first_run")), "a saved demo settings file retires the row")
	s.free()
	AtomicJson.remove_tree(dir)


## The boot order of a redirected demo (debug --demo, Web): Settings._ready
## calls apply_demo_dirs() and then load_settings() with its default path,
## which puts _path back to the full game's settings.cfg. is_node_ready() is
## already true inside _ready, so boot is told apart by the frame count; the
## one-shot `ready` hook then loads the demo's own file (review, T05).
func test_boot_order_ends_on_demo_settings() -> void:
	var s := (load("res://autoload/Settings.gd") as GDScript).new() as Node
	s.name = "BuildInfoBootSettings"
	BuildInfo.force_autoloads["Settings"] = s
	BuildInfo.force_boot = 1
	BuildInfo.force_demo = 1
	BuildInfo._config = null
	check(BuildInfo.redirects_dirs(), "a forced debug demo redirects")
	get_tree().root.add_child(s)  # _ready: apply_demo_dirs(), then load_settings()
	check(s.get("_path") == BuildInfo.DEMO_SETTINGS_PATH, "ends on the demo settings file (%s)" % s.get("_path"))
	check(bool(s.get("first_run")) == not FileAccess.file_exists(BuildInfo.DEMO_SETTINGS_PATH),
		"first_run follows the demo file")
	if not FileAccess.file_exists(BuildInfo.DEMO_SETTINGS_PATH):
		check(not bool(s.get("playtest_recording")), "demo recording default (D-039)")
	check(s.ready.get_connections().is_empty(), "one-shot hook gone")
	BuildInfo._restore_dirs()
	BuildInfo.force_autoloads.clear()
	s.queue_free()


## After boot (the dev console, tests) no ready hook is left behind: the
## redirect of _path already stands.
func test_runtime_force_demo_connects_no_ready_hook() -> void:
	var s := (load("res://autoload/Settings.gd") as GDScript).new() as Node
	s.name = "BuildInfoRuntimeSettings"
	get_tree().root.add_child(s)
	BuildInfo.force_autoloads["Settings"] = s
	BuildInfo.force_boot = 0
	BuildInfo.set_force_demo(1)
	check(s.get("_path") == BuildInfo.DEMO_SETTINGS_PATH, "redirected directly")
	check(s.ready.get_connections().is_empty(), "no ready hook at runtime")
	BuildInfo._restore_dirs()
	BuildInfo.force_autoloads.clear()
	s.queue_free()


## clear_cache (Cinematics._exit_tree) drops a redirect still waiting for an
## autoload that never entered the tree, and its root hook.
func test_clear_cache_drops_pending_hook() -> void:
	var before := get_tree().root.child_entered_tree.get_connections().size()
	BuildInfo._redirect("BuildInfoNeverArrives", "text", "x", "")
	check(BuildInfo._pending_hook.is_valid(), "hooked while pending")
	BuildInfo.clear_cache()
	check(BuildInfo._pending.is_empty() and not BuildInfo._pending_hook.is_valid(), "pending and hook dropped")
	check(get_tree().root.child_entered_tree.get_connections().size() == before, "root signal clean")
