class_name TourSandbox
extends RefCounted
## The endgame tour's file and session sandbox (M9 D6 §7.1, T14). The endgame
## tour writes saves (NG+ archives, a cleared profile, a full-game save for
## the refused demo Continue), records, ghosts and playtest files, and flips
## the build kind, and the locale. begin() points every
## one of them at `root` (wiped first) or at its neutral value; end() puts
## back exactly what it found and wipes `root`, so a second run on the same
## machine starts from the same nothing and produces the same frames, and the
## developer's own user:// files are never touched.
##
## CaptureTour.prepare_session (T01) has already reset Settings to defaults
## (saved to TOUR_SETTINGS_PATH) and moved the platform store to
## user://tour_sandbox; this sandbox sits on top of that.
##
## Every property is read and written through `in` checks and Object.get/set,
## so a missing field (an older checkout) is skipped instead of breaking the
## tour.

const ROOT := "user://capture_tour"
## Where a redirected demo session would put its files (BuildInfo): the tour
## removes it at the end when it did not exist before.
const DEMO_DIR := "user://demo"


## Redirects the session into `root` and returns the snapshot end() needs.
static func begin(root: String = ROOT) -> Dictionary:
	var snap := {"root": root, "props": [], "demo_dir_existed": DirAccess.dir_exists_absolute(DEMO_DIR)}
	AtomicJson.remove_tree(root)
	DirAccess.make_dir_recursive_absolute(root)
	for p: Array in paths(root):
		_swap(snap, p[0], p[1], p[2])
	var platform := _autoload("Platform")
	if platform and "store_dir" in platform:
		snap["platform_dir"] = platform.get("store_dir")
		snap["platform_headless"] = platform.get("allow_headless")
		platform.call("reset_for_tests", root + "/platform")
	_reload_records()
	snap["force_demo"] = BuildInfo.force_demo
	snap["demo_session"] = DemoDevActions.demo_session_on()
	snap["dev_bypass"] = DemoGate.dev_bypass
	snap["debug_draw"] = DemoBarrier.debug_draw
	snap["locale"] = Loc.locale()
	snap["flag_missing"] = Loc.flag_missing
	# Neutral values: a full build, no gate bypass, no barrier drawing,
	# English.
	if BuildInfo.force_demo != 0:
		BuildInfo.set_force_demo(0)
	DemoGate.set_dev_bypass(false)
	DemoBarrier.set_debug_draw(false)
	Loc.flag_missing = false
	if Loc.locale() != Loc.SOURCE_LOCALE:
		LocaleDevActions.set_locale(Loc.SOURCE_LOCALE)
	return snap


## Puts back everything begin() changed and wipes the sandbox root.
static func end(snap: Dictionary) -> void:
	# A demo session the tour started (not one it found) goes first: its
	# settle step puts the router gate and the barriers back to the full game.
	if DemoDevActions.demo_session_on() and not bool(snap.get("demo_session", false)):
		DemoDevActions.set_demo_session(false)
	if BuildInfo.force_demo != int(snap.get("force_demo", -1)):
		BuildInfo.set_force_demo(int(snap.get("force_demo", -1)))
	DemoGate.set_dev_bypass(bool(snap.get("dev_bypass", false)))
	DemoBarrier.set_debug_draw(bool(snap.get("debug_draw", false)))
	Loc.flag_missing = bool(snap.get("flag_missing", false))
	var loc := String(snap.get("locale", Loc.SOURCE_LOCALE))
	if Loc.locale() != loc:
		LocaleDevActions.set_locale(loc)
	for p: Array in snap.get("props", []):
		var node := _autoload(String(p[0]))
		if node:
			node.set(String(p[1]), p[2])
	var platform := _autoload("Platform")
	if platform and snap.has("platform_dir"):
		platform.call("reset_for_tests", String(snap["platform_dir"]))
		platform.set("allow_headless", bool(snap.get("platform_headless", false)))
	_reload_records()
	AtomicJson.remove_tree(String(snap.get("root", ROOT)))
	if not bool(snap.get("demo_dir_existed", true)):
		AtomicJson.remove_tree(DEMO_DIR)


## [autoload, property, sandbox value] for every file location the tour
## writes through (the platform store is handled apart: it has a reset API).
static func paths(root: String) -> Array:
	return [["SaveManager", "save_dir", root + "/saves"], ["Playtest", "dir", root + "/playtest"]]


static func _swap(snap: Dictionary, autoload: String, prop: String, value: Variant) -> void:
	var node := _autoload(autoload)
	if node == null or not prop in node:
		return
	(snap["props"] as Array).append([autoload, prop, node.get(prop)])
	node.set(prop, value)


static func _reload_records() -> void:
	var ch := _autoload("Challenges")
	if ch and "records" in ch and ch.get("records") != null:
		(ch.get("records") as Object).call("reload")


static func _autoload(name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(name) if tree else null
