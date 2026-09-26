class_name BuildProbe
extends RefCounted
## `--print-build-info` (Main.gd, M9 D6 §3.6): prints one line
## `BUILD_INFO {json}` about the running build and quits, so
## tools/build/build.py --smoke can check an exported binary headless, with
## no display and no network. Read-only: it writes no file.
## Every data count goes through DataDir, the exported-build pitfall
## (K-M8-22): an export that lists no .remap files reports 0 and fails here.

## Minimum counts an exported build must report (test_build_probe_minimums
## checks the editor run meets them). Raise them when content grows; the
## achievement and challenge minimums are raised by their content tasks.
const MINIMUMS := {"quests": 3, "sequences": 10, "memories": 5, "npcs": 5, "endings": 4}
const DATA_DIRS := {"quests": "quests", "sequences": "sequences", "memories": "memories", "npcs": "npcs",
	"endings": "endings", "achievements": "achievements", "challenges": "challenges"}
const RELAY_ROOM := "res://world/rooms/lowlight/Relay.tscn"


static func info() -> Dictionary:
	var d := BuildInfo.info()
	var features := {}
	for f: String in ["demo", "release", "debug", "editor", "web", "linuxbsd", "windows", "macos"]:
		features[f] = OS.has_feature(f)
	d["features"] = features
	d["locales"] = Array(Loc.available_locales())
	var data := {}
	for key: String in DATA_DIRS:
		# Test sequences are excluded from exports (export_presets.cfg).
		var paths := DataDir.list("res://data/%s" % DATA_DIRS[key])
		data[key] = Array(paths).filter(func(p: String) -> bool: return not p.get_file().begins_with("test_")).size()
	data["ghosts"] = DataDir.list_files("res://data/challenges/ghosts", "ghost").size()
	d["data"] = data
	var rooms := {}
	for dir in ContentValidator.WORLD_ROOM_DIRS:
		rooms[dir.get_file()] = DataDir.list_scenes(dir).size()
	d["rooms"] = rooms
	var t := SliceStats.totals()
	d["totals"] = {"secrets": (t["secret_ids"] as Array).size(), "fragments": t["fragments"], "core_shards": t["core_shards"]}
	var start := _start_room()
	d["start_room"] = start
	d["start_room_loads"] = start != "" and ResourceLoader.exists(start) and load(start) is PackedScene
	var c := BuildInfo.config()
	d["demo"] = {"id": c.id if c else "", "allowed": c.room_paths().size() if c else 0,
		"relay_allowed": BuildInfo.room_allowed(RELAY_ROOM)}
	d["dev_console"] = DevActions.available()
	return d


## What is wrong with this build's info (empty = healthy).
static func problems(d: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var data: Dictionary = d.get("data", {})
	for key: String in MINIMUMS:
		if int(data.get(key, 0)) < int(MINIMUMS[key]):
			out.append("data %s: %d < %d" % [key, int(data.get(key, 0)), MINIMUMS[key]])
	if not d.get("start_room_loads", false):
		out.append("start room does not load: %s" % d.get("start_room", ""))
	var expected := str(d.get("user_dir_expected", ""))
	if expected != "" and not d.get("web", false) and str(d.get("user_dir", "")).get_file() != expected:
		out.append("user dir %s is not %s" % [d.get("user_dir", ""), expected])
	return out


static func run(tree: SceneTree) -> void:
	var d := info()
	var bad := problems(d)
	d["problems"] = Array(bad)
	print("BUILD_INFO " + JSON.stringify(d))
	for p in bad:
		printerr("BUILD_INFO problem: " + p)
	tree.quit(1 if not bad.is_empty() else 0)


## The campaign's first room, read through the tree (Game is an autoload).
static func _start_room() -> String:
	var game := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Game")
	if game == null or not game.has_method("campaign_start_room"):
		return ""
	return str(game.call("campaign_start_room"))
