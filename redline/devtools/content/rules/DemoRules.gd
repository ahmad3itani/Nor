class_name DemoRules
extends RefCounted
## Demo scope rules (M9 D6 §5.2, D-165) over data/release/demo.tres and the
## room pass. DemoConfig.validate()/content_check() cover the single-file
## parts (DM-1 structure, DM-5, DM-6 lengths); this module does the cross-file
## ones. DM-4 (demo achievement reachability) lands with the achievements
## (T14).
##   DM-1 the campaign start room and the title backdrop are allowed
##   DM-2 border exits: a BORDER demo has >= 1; each has a size and sits on
##        the room's bounds edge (the barrier plugs a real gap)
##   DM-3 every exit into an allowed room resolves to a SpawnMarker there
##   DM-6 card text passes the Act I knowledge lint
##   DM-7 an ACT_CLOSE demo allows the room of the act's close sequence
##   DM-8 web demos redirect their files (BuildInfo source + its test)

## An exit rect this close to the room's bounds edge counts as "on the edge".
const EDGE_SLACK := 16.0
const BUILD_INFO_SOURCE := "res://release/BuildInfo.gd"
const WEB_TEST_SOURCE := "res://tests/unit/test_build_info.gd"
const TITLE_BACKDROP := "res://world/rooms/TitleBackdrop.tscn"

## [room path, exit name, target] of the last run (the report section).
static var last_borders: Array = []
## id -> "" (earnable in the demo) or the reason it is not (report, DM-4).
static var last_earnable: Dictionary = {}

## DM-4: what a stat needs inside the demo to move. "" (or absent) = any
## play; "flag:<x>" = x has a producer inside the demo; "node:<Class>" = an
## allowed room holds such a node; "detail" = a memory with a detail is
## reachable. boss_nohit_/boss_time_<boss> need "flag:<boss>_intro_seen".
## challenge_silver_medals needs the training rig, which opens with the Act I
## close (ChallengeLibrary.rig_open): a demo that stops before the Relay
## never opens it.
const STAT_NEEDS := {"chase_clean": "flag:chase_rainline_done", "clamp_boss_staggers": "flag:warden_krail_intro_seen",
	"shutter_close_calls": "node:PowerShutter", "challenge_silver_medals": "flag:act1_complete",
	"act1_clear_time": "flag:act1_complete", "memory_details_found": "detail"}


static func run(v: ContentValidator) -> void:
	var c := BuildInfo.config()
	if c == null:
		v.errors.append("[DM-1] %s is missing or not a DemoConfig" % BuildInfo.DEMO_CONFIG_PATH)
		return
	check(c, v, BuildInfo.DEMO_CONFIG_PATH)
	# DM-4 reads the flag graph of the full room pass (a partial validator
	# from a test has no producers to judge by).
	if int(v.stats.get("rooms", 0)) > 0:
		var r := achievement_check(c, v, AchievementLibrary.all(), scope(c), BuildInfo.DEMO_CONFIG_PATH)
		v.errors.append_array(r["errors"])
		v.warnings.append_array(r["warnings"])
	check_web_redirect(v, FileAccess.get_file_as_string(BUILD_INFO_SOURCE), FileAccess.get_file_as_string(WEB_TEST_SOURCE))


## Every cross-file rule for one config (tests pass fixture configs).
static func check(c: DemoConfig, v: ContentValidator, where: String) -> void:
	var tag := where.get_file()
	var start := Game.onboarding.campaign_start_room
	if not c.allows(start):
		v.errors.append("[DM-1] %s: the campaign start room %s is outside the demo" % [tag, start])
	if not c.allows(TITLE_BACKDROP):
		v.errors.append("[DM-1] %s: the title backdrop is outside the demo" % tag)
	last_borders = []
	var rooms: Dictionary = {}
	for path in c.room_paths():
		var room := _load_room(path)
		if room == null:
			continue
		for n in room.find_children("*", "RoomExit", true, false):
			var e := n as RoomExit
			if e.target_room == "":
				continue
			if c.allows(e.target_room):
				_check_entry(v, tag, path, e, rooms)
				continue
			last_borders.append([path, String(e.name), e.target_room])
			if e.size.x <= 0.0 or e.size.y <= 0.0:
				v.errors.append("[DM-2] %s: border exit %s/%s has no size" % [tag, path.get_file(), e.name])
			elif not _on_edge(_rect_in(room, e), room.bounds):
				v.warnings.append("[DM-2] %s: border exit %s/%s is not on the room's bounds edge (the barrier would stand mid-room)" % [
					tag, path.get_file(), e.name])
		room.free()
	for r: Node in rooms.values():
		if r:
			r.free()
	if c.end_mode == DemoConfig.EndMode.BORDER and last_borders.is_empty():
		v.errors.append("[DM-2] %s: a BORDER demo has no border exit, so it has no end" % tag)
	var lint := v._knowledge_lint()
	if lint:
		for line: Array in c.text_lines():
			for term in lint.hits(String(line[1])):
				v.warnings.append("[DM-6] %s: %s uses '%s' (knowledge lint)" % [tag, line[0], term])
	if c.end_mode == DemoConfig.EndMode.ACT_CLOSE:
		var act := ActLibrary.act(1)
		var room_path: String = act.close_sequence.room if act and act.close_sequence else ""
		if room_path == "":
			v.warnings.append("[DM-7] %s: the Act I close sequence names no room to check" % tag)
		elif not c.allows(room_path):
			v.errors.append("[DM-7] %s: ACT_CLOSE demo, but the act close room %s is outside it" % [tag, room_path])


## DM-3: an exit into an allowed room lands on a SpawnMarker there.
static func _check_entry(v: ContentValidator, tag: String, from: String, e: RoomExit, rooms: Dictionary) -> void:
	if e.target_entry == &"":
		return
	if not rooms.has(e.target_room):
		rooms[e.target_room] = _load_room(e.target_room)
	var target: Node = rooms[e.target_room]
	if target == null:
		v.errors.append("[DM-3] %s: %s/%s leads to missing room %s" % [tag, from.get_file(), e.name, e.target_room])
		return
	for m in target.find_children("*", "SpawnMarker", true, false):
		if (m as SpawnMarker).spawn_id == e.target_entry:
			return
	v.errors.append("[DM-3] %s: %s/%s: no SpawnMarker '%s' in %s" % [tag, from.get_file(), e.name, e.target_entry, e.target_room.get_file()])


## DM-4 over `list` for one config. Returns {errors, warnings, earnable}
## (earnable: id -> "" or the reason it is not earnable in the demo).
static func achievement_check(c: DemoConfig, v: ContentValidator, list: Array[AchievementData], sc: Dictionary,
		where: String) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var earnable := {}
	var by_id := {}
	for a in list:
		by_id[a.id] = a
		earnable[a.id] = unearnable_reason(a, v, sc, c)
	var tag := where.get_file()
	for id in c.achievements:
		if not by_id.has(id):
			errors.append("[DM-4] %s: achievement '%s' does not exist" % [tag, id])
		elif String(earnable[id]) != "":
			errors.append("[DM-4] %s: achievement '%s' cannot be earned in the demo (%s)" % [tag, id, earnable[id]])
	for id: String in earnable:
		if String(earnable[id]) == "" and not c.achievements.has(id):
			warnings.append("[DM-4] %s: achievement '%s' is earnable in the demo but not listed (add it to demo.tres)" % [tag, id])
	last_earnable = earnable
	return {"errors": errors, "warnings": warnings, "earnable": earnable}


## "" when every condition and the stat can be met inside the demo.
static func unearnable_reason(a: AchievementData, v: ContentValidator, sc: Dictionary, c: DemoConfig) -> String:
	for expr in a.conditions:
		var why := _condition_reason(expr.strip_edges(), v, sc, c)
		if why != "":
			return why
	if a.stat_id != &"":
		var id := String(a.stat_id)
		var need: String = STAT_NEEDS.get(id, "")
		for prefix in ["boss_nohit_", "boss_time_"]:
			if id.begins_with(prefix):
				need = "flag:%s_intro_seen" % id.trim_prefix(prefix)
		if need.begins_with("flag:"):
			if not flag_in_demo(need.trim_prefix("flag:"), v, sc, c):
				return "stat %s needs %s inside the demo" % [id, need]
		elif need.begins_with("node:"):
			if not (sc["classes"] as Dictionary).has(need.trim_prefix("node:")):
				return "stat %s needs a %s in a demo room" % [id, need.trim_prefix("node:")]
		elif need == "detail" and int(sc["details"]) == 0:
			return "stat %s needs a memory detail inside the demo" % id
	return ""


static func _condition_reason(expr: String, v: ContentValidator, sc: Dictionary, c: DemoConfig) -> String:
	if expr == "" or expr.begins_with("!"):
		return ""
	var kind := expr.get_slice(":", 0)
	var arg := expr.get_slice(":", 1)
	match kind:
		"flag":
			return "" if flag_in_demo(arg, v, sc, c) else "flag %s has no producer inside the demo" % arg
		"collected":
			return "" if (sc["collectibles"] as Dictionary).has(arg) else "%s is not placed in a demo room" % arg
		"ability":
			var f := "unlocked_%s" % arg
			return "" if flag_in_demo(f, v, sc, c) else "ability %s is not granted inside the demo" % arg
		"count":
			var n := int(expr.get_slice(":", 2))
			var total := int((sc["totals"] as Dictionary).get(arg, -1))
			if total < 0:
				return "no demo total for count:%s" % arg
			return "" if n <= total else "count:%s:%d but the demo holds %d" % [arg, n, total]
		"atleast":
			var n := int(expr.get_slice(":", 2))
			if arg == MemoryLibrary.REMEMBERED_FLAG:
				return "" if n <= int(sc["memories"]) else "atleast:%s:%d but the demo holds %d memories" % [arg, n, sc["memories"]]
			return "" if flag_in_demo(arg, v, sc, c) else "int flag %s has no producer inside the demo" % arg
	return "condition '%s' cannot be proven inside the demo" % expr


## A producer of `flag` lies inside the demo: an allowed room, a sequence
## set in an allowed room, or a data file an allowed room reaches through its
## references (an NPC profile, its dialogue). Code-set flags (CODE_FLAGS)
## count only for the demo's own flags.
static func flag_in_demo(flag: String, v: ContentValidator, sc: Dictionary, c: DemoConfig) -> bool:
	if flag in ["demo_build", "demo_end_seen"]:
		return true
	for p: String in v.producers.get(flag, []):
		if p.ends_with(".tscn") and c.allows(p):
			return true
		if (sc["reached"] as Dictionary).has(p):
			return true
		if p.ends_with(".tres") and ResourceLoader.exists(p):
			var res := load(p)
			if res is SequenceData and (res as SequenceData).room != "" and c.allows((res as SequenceData).room):
				return true
	return false


## What the demo's rooms hold (DM-4): collectible ids, secret totals, node
## classes, memories and every resource the rooms reach by reference.
static func scope(c: DemoConfig) -> Dictionary:
	var sc := {"collectibles": {}, "classes": {}, "reached": {}, "details": 0, "memories": 0,
		"totals": {"secrets": 0, "fragments": 0, "shards": 0}}
	var fragments := {}
	for path in c.room_paths():
		if not ContentValidator.WORLD_ROOM_DIRS.has(path.get_base_dir()):
			continue
		_reach(path, sc["reached"])
		var packed := load(path) as PackedScene if ResourceLoader.exists(path) else null
		if packed == null:
			continue
		var inst := packed.instantiate()
		for n in inst.find_children("*", "", true, false):
			var scr := n.get_script() as Script
			if scr and scr.get_global_name() != "":
				sc["classes"][String(scr.get_global_name())] = true
			if n is Collectible:
				var col := n as Collectible
				sc["collectibles"][col.persist_id] = true
				if col.kind == Collectible.Kind.SCRAP_BUNDLE:
					continue
				sc["totals"]["secrets"] += 1
				if col.kind == Collectible.Kind.MEMORY_FRAGMENT:
					sc["totals"]["fragments"] += 1
					if col.fragment:
						fragments[col.fragment.id] = true
				elif col.kind == Collectible.Kind.CORE_SHARD:
					sc["totals"]["shards"] += 1
			elif n is BreakableWall:
				sc["totals"]["secrets"] += 1
		inst.free()
	for s in MemoryLibrary.all_scenes():
		var reachable := s.source == MemorySceneData.Source.SURFACED or (s.fragment != null and fragments.has(s.fragment.id))
		if reachable:
			sc["memories"] += 1
			if s.detail_text != "":
				sc["details"] += 1
	return sc


## Every res:// file `path` references, recursively (ext_resource lines).
static func _reach(path: String, seen: Dictionary) -> void:
	if seen.has(path) or not FileAccess.file_exists(path):
		return
	seen[path] = true
	if not (path.ends_with(".tscn") or path.ends_with(".tres")):
		return
	var re := RegEx.create_from_string("path=\"(res://[^\"]+\\.(?:tres|tscn))\"")
	for m in re.search_all(FileAccess.get_file_as_string(path)):
		_reach(m.get_string(1), seen)


## DM-8: on Web the per-feature user dir does not apply, so BuildInfo must
## redirect a web demo's files, and the test that proves it must exist.
static func check_web_redirect(v: ContentValidator, build_info_text: String, test_text: String) -> void:
	var i := build_info_text.find("static func redirects_dirs()")
	var body := build_info_text.substr(i, build_info_text.find("\nstatic func", i + 1) - i) if i >= 0 else ""
	if not body.contains("is_web()"):
		v.errors.append("[DM-8] BuildInfo.redirects_dirs() must redirect web demos (is_web())")
	if not test_text.contains("func test_web_demo_redirects_dirs"):
		v.errors.append("[DM-8] test_web_demo_redirects_dirs is missing from test_build_info.gd")


## A Room instance (the caller frees it), or null for a missing scene or a
## non-room (the title backdrop); DemoConfig.content_check reports missing ones.
static func _load_room(path: String) -> Room:
	var packed := load(path) as PackedScene if ResourceLoader.exists(path) else null
	if packed == null:
		return null
	var n := packed.instantiate()
	if n is Room:
		return n as Room
	n.free()
	return null


## The exit's rect in room space (the room is not in the tree here).
static func _rect_in(room: Node, e: RoomExit) -> Rect2:
	var pos := e.position
	var p := e.get_parent()
	while p != null and p != room:
		if p is Node2D:
			pos += (p as Node2D).position
		p = p.get_parent()
	return Rect2(pos, e.size)


static func _on_edge(r: Rect2, b: Rect2) -> bool:
	return r.position.x <= b.position.x + EDGE_SLACK or r.end.x >= b.end.x - EDGE_SLACK \
		or r.position.y <= b.position.y + EDGE_SLACK or r.end.y >= b.end.y - EDGE_SLACK


static func report(_v: ContentValidator) -> String:
	var c := BuildInfo.config()
	if c == null:
		return ""
	var md: PackedStringArray = ["## Demo scope", ""]
	md.append("Demo '%s' (%s): %d rooms allowed, features off: %s." % [c.id, DemoConfig.EndMode.keys()[c.end_mode],
		c.room_paths().size(), ", ".join(PackedStringArray(c.disabled_features))])
	md.append("")
	md.append("| Room | Border exit | Leads to |")
	md.append("|---|---|---|")
	for b: Array in last_borders:
		md.append("| %s | %s | %s |" % [String(b[0]).get_file(), b[1], String(b[2]).get_file()])
	if not last_earnable.is_empty():
		md.append("")
		md.append("| Achievement | Listed | Earnable in the demo |")
		md.append("|---|---|---|")
		var ids := last_earnable.keys()
		ids.sort()
		for id: String in ids:
			var why := String(last_earnable[id])
			md.append("| %s | %s | %s |" % [id, "yes" if c.achievements.has(id) else "no", "yes" if why == "" else "no: " + why])
	return "\n".join(md)
