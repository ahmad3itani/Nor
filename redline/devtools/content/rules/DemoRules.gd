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


static func run(v: ContentValidator) -> void:
	var c := BuildInfo.config()
	if c == null:
		v.errors.append("[DM-1] %s is missing or not a DemoConfig" % BuildInfo.DEMO_CONFIG_PATH)
		return
	check(c, v, BuildInfo.DEMO_CONFIG_PATH)
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
	return "\n".join(md)
