class_name BuildInfo
extends RefCounted
## What kind of build this is (M9 D6, D-165): full or demo, web or desktop,
## its version label, and which rooms and features it allows. Everything that
## differs between the full game and the demo asks here, never OS feature tags
## directly, so tests and the dev console can force either kind. The demo is
## data (data/release/demo.tres) plus one feature tag ("demo") on the demo
## export presets: content is gated at runtime, never stripped or forked.

const DEMO_CONFIG_PATH := "res://data/release/demo.tres"
## Features a demo may switch off. The validator (DM-5) rejects any other name.
const KNOWN_FEATURES: Array[StringName] = [&"labs", &"lab_cycle", &"relay_start", &"ngplus", &"null", &"transit", &"challenges"]
## Where a redirected demo keeps its files (debug --demo, force_demo, Web).
## Desktop exports with the "demo" feature get their own user dir instead
## (project.godot config/custom_user_dir_name.demo), so they need none of it.
const DEMO_SAVE_DIR := "user://demo/saves"
const DEMO_PLATFORM_DIR := "user://demo/platform"
const DEMO_SETTINGS_PATH := "user://demo/settings.cfg"
const DEMO_PLAYTEST_DIR := "user://demo/playtests"
## The defaults each redirect replaces (the autoloads' own constants; a test
## keeps them in step with SaveManager, Platform, Settings and Playtest).
const DEFAULT_SAVE_DIR := "user://saves"
const DEFAULT_PLATFORM_DIR := "user://platform"
const DEFAULT_SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_PLAYTEST_DIR := "user://playtests"
const SLICE_STATS := "res://progression/SliceStats.gd"

## Test seam: -1 = follow the build (--demo / feature tag), 0 = full, 1 = demo.
static var force_demo: int = -1
## Test seam: room path -> allowed (checked first by room_allowed).
static var force_allowed: Dictionary = {}
## Test seam: -1 = OS.has_feature("web"), 0 = desktop, 1 = web.
static var force_web: int = -1
## Test seam: a forced demo behaves like an exported demo (the "demo" feature
## tag, with its own desktop user dir) instead of a debug --demo session.
static var force_feature_tag: bool = false
## Tests may inject a config (e.g. ACT_CLOSE mode); clear_cache() drops it.
static var _config: DemoConfig = null
## [node name, property, value before, value set] for every redirect applied,
## so leaving the demo restores exactly what it changed.
static var _applied: Array = []
## Autoloads not yet in the tree when Settings._ready redirects (boot order):
## node name -> [[property, value, only_if]].
static var _pending: Dictionary = {}
static var _pending_hook: Callable = Callable()


static func is_demo() -> bool:
	if force_demo >= 0:
		return force_demo == 1
	return OS.has_feature("demo") or (OS.is_debug_build() and "--demo" in OS.get_cmdline_user_args())


## The DemoConfig of a demo build (null in the full game).
static func demo() -> Resource:
	return config() if is_demo() else null


## The shipped demo config whatever the build (dev page, probe, validator).
## load(), not preload(): a preloaded const's typed use can fail to parse (CLAUDE.md).
static func config() -> DemoConfig:
	if _config == null and ResourceLoader.exists(DEMO_CONFIG_PATH):
		_config = load(DEMO_CONFIG_PATH) as DemoConfig
	return _config


static func kind() -> String:
	return "demo" if is_demo() else "full"


static func is_web() -> bool:
	if force_web >= 0:
		return force_web == 1
	return OS.has_feature("web")


## Web builds have no Quit (the browser tab owns the window).
static func can_quit() -> bool:
	return not is_web()


static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


## "0.8.0-m8", "0.8.0-m8 DEMO", "... (debug)": the title and dev page line.
static func label() -> String:
	return version() + (" DEMO" if is_demo() else "") + (" (debug)" if OS.is_debug_build() else "")


## Feature switches (KNOWN_FEATURES): all on in the full game; a demo turns
## off the ones its config lists. An unknown name warns and stays enabled.
static func enabled(feature: StringName) -> bool:
	if not feature in KNOWN_FEATURES:
		push_warning("BuildInfo.enabled: unknown feature '%s'" % feature)
		return true
	if not is_demo():
		return true
	var c := config()
	return c == null or not feature in c.disabled_features


static func room_allowed(path: String) -> bool:
	if force_allowed.has(path):
		return bool(force_allowed[path])
	if not is_demo():
		return true
	var c := config()
	return c == null or c.allows(path)


## Whether playtest recording defaults on in this build (D-039: off in demos).
static func recording_default() -> bool:
	var c := config()
	return c.recording_default if is_demo() and c else true


## Appended to the title wordmark ("DEMO" in a demo build).
static func title_tag() -> String:
	var c := config()
	return Loc.t(c.title_tag) if is_demo() and c else ""


## Read through the tree, not the Game identifier: Settings (the second
## autoload) compiles BuildInfo, and naming Game here would compile Game.gd
## (and preload its data) mid-cycle, leaving its resources untyped.
static func title_subtitle() -> String:
	var c := config()
	if is_demo() and c:
		return Loc.t(c.title_subtitle)
	var game := _autoload("Game")
	return str(game.get("onboarding").get("title_subtitle")) if game else ""


## The menu id slice_completed opens (the demo end card in an ACT_CLOSE demo).
static func slice_card_id() -> StringName:
	var c := config()
	if is_demo() and c and c.end_mode == DemoConfig.EndMode.ACT_CLOSE:
		return &"demo_end"
	return &"slice_end"


## The user dir name this build should run in: the per-feature override
## ("REDLINE Demo" in a demo export), "" for the default app_userdata dir.
## get_setting_with_override: get_setting() returns the base value even in a
## demo export (measured, D6 §0.3).
static func expected_user_dir_name() -> String:
	if not bool(ProjectSettings.get_setting_with_override("application/config/use_custom_user_dir")):
		return ""
	return str(ProjectSettings.get_setting_with_override("application/config/custom_user_dir_name"))


## Tests and the dev console: 1 = demo, 0 = full, -1 = the real build (which
## also resets the other test seams). Moves the save, platform, settings and
## playtest paths with it, then drops the demo-filtered room totals.
static func set_force_demo(v: int) -> void:
	force_demo = v
	_config = null
	if v < 0:
		force_web = -1
		force_feature_tag = false
	_restore_dirs()
	if is_demo():
		apply_demo_dirs()
	# By path, not the class name: Settings (the second autoload) compiles
	# this script, and SliceStats names Game, which must not compile mid-cycle.
	(load(SLICE_STATS) as GDScript).call("clear_cache")


## Whether this demo keeps its files under user://demo/ (D-165, R05.8): a
## debug --demo or forced session shares the full game's user dir, and on Web
## user:// is always the origin's storage (the per-feature user dir is
## ignored), so both redirect. A desktop demo export has its own user dir.
static func redirects_dirs() -> bool:
	if not is_demo():
		return false
	if is_web():
		return true
	if force_demo == 1:
		return not force_feature_tag
	return not OS.has_feature("demo")


## Called first in Settings._ready (before any store loads) and by
## set_force_demo. Demo defaults (recording off) apply to every demo; the
## path redirects only where redirects_dirs(). A path a test already pointed
## elsewhere is left alone. Idempotent.
static func apply_demo_dirs() -> void:
	if not is_demo() or not _applied.is_empty() or not _pending.is_empty():
		return
	var c := config()
	if c:
		_redirect("Settings", "playtest_recording", c.recording_default, null)
	if not redirects_dirs():
		return
	_redirect("SaveManager", "save_dir", DEMO_SAVE_DIR, DEFAULT_SAVE_DIR)
	_redirect("Platform", "store_dir", DEMO_PLATFORM_DIR, DEFAULT_PLATFORM_DIR)
	_redirect("Settings", "_path", DEMO_SETTINGS_PATH, DEFAULT_SETTINGS_PATH)
	_redirect("Playtest", "dir", DEMO_PLAYTEST_DIR, DEFAULT_PLAYTEST_DIR)
	_reload_settings_after_boot()


## Boot only: Settings._ready calls load_settings() with its default path
## right after this, which would read (and later write) the full game's
## settings.cfg. Once Settings is ready, a demo whose path was put back loads
## its own file from the defaults instead. A no-op when Settings honours the
## redirected _path itself.
static func _reload_settings_after_boot() -> void:
	var s := _autoload("Settings")
	if s == null or s.is_node_ready():
		return
	s.ready.connect(func() -> void:
		if not redirects_dirs() or s.get("_path") == DEMO_SETTINGS_PATH:
			return
		if s.has_method("apply_defaults"):
			s.call("apply_defaults")
		var c := config()
		if c:
			s.set("playtest_recording", c.recording_default)
		s.call("load_settings", DEMO_SETTINGS_PATH), CONNECT_ONE_SHOT)


## Puts back every value apply_demo_dirs changed that nothing changed since.
static func _restore_dirs() -> void:
	_pending.clear()
	_drop_pending_hook()
	for a: Array in _applied:
		var n := _autoload(a[0])
		if n and n.get(a[1]) == a[3]:
			n.set(a[1], a[2])
	_applied.clear()


## Sets node.prop = value when it still holds only_if (null = always). At boot
## Settings._ready runs before the later autoloads enter the tree, so those
## are set as they enter it (child_entered_tree fires before their _ready).
static func _redirect(node_name: String, prop: String, value: Variant, only_if: Variant) -> void:
	var n := _autoload(node_name)
	if n == null:
		var list: Array = _pending.get(node_name, [])
		list.append([prop, value, only_if])
		_pending[node_name] = list
		_hook_pending()
		return
	var before: Variant = n.get(prop)
	if only_if != null and before != only_if:
		return
	n.set(prop, value)
	_applied.append([node_name, prop, before, value])


static func _hook_pending() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or _pending_hook.is_valid():
		return
	_pending_hook = func(node: Node) -> void:
		if not _pending.has(String(node.name)):
			return
		var list: Array = _pending[String(node.name)]
		_pending.erase(String(node.name))
		for p: Array in list:
			_redirect(String(node.name), p[0], p[1], p[2])
		if _pending.is_empty():
			_drop_pending_hook()
	tree.root.child_entered_tree.connect(_pending_hook)


static func _drop_pending_hook() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if _pending_hook.is_valid() and tree and tree.root.child_entered_tree.is_connected(_pending_hook):
		tree.root.child_entered_tree.disconnect(_pending_hook)
	_pending_hook = Callable()


static func _autoload(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(node_name) if tree else null


## Everything BuildProbe and the dev Demo page show about this build.
static func info() -> Dictionary:
	var c := config()
	return {
		"version": version(),
		"kind": kind(),
		"label": label(),
		"debug": OS.is_debug_build(),
		"web": is_web(),
		"user_dir": OS.get_user_data_dir(),
		"user_dir_expected": expected_user_dir_name(),
		"redirected": redirects_dirs(),
		"demo_id": c.id if c else "",
	}


## Drops the demo config (Cinematics._exit_tree clears every static cache, so
## no Resource outlives its script at exit).
static func clear_cache() -> void:
	_config = null
