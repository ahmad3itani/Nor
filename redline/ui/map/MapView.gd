class_name MapView
extends Control
## The world map (bible §20), drawn from WorldMapData + WorldMapIndex + the
## profile's discovery state. Controller-first: move = pan the cursor,
## ranged/grapple (RB/LB, O/U) = zoom, jump (A/Space) = toggle a pin.
##
## What shows, and when (so the map rewards exploring, never replaces it):
## - room outline + exits: room visited, or the district's base map owned;
## - geometry and Anchors / gates / ability gates: only in explored cells;
## - NPC and boss pins: once the room was visited (boss crossed out when won);
## - "?" secret hint: with the Surveyor's lens, rooms with secrets left
##   (never the exact spot);
## - quest notes, player pins, the dropped Scrap cache, Rook himself.

signal hover_changed(text: String)

const ZOOMS: Array[float] = [0.025, 0.05, 0.1, 0.2]
const PAN_SPEED := 260.0  # screen px per second at any zoom
const COL_BG := Color(0.05, 0.04, 0.08)
const COL_OUTLINE := Color(0.45, 0.42, 0.55)
const COL_CELL := Color(0.12, 0.11, 0.18)
const COL_BLOCK := Color(0.55, 0.53, 0.66)
const COL_ONEWAY := Color(0.4, 0.62, 0.7)
const COL_ANCHOR := Color("e8283c")
const COL_NPC := Color("ffcf5a")
const COL_GATE := Color("7fd7ff")
const COL_PIN := Color("ffd36b")
const COL_NOTE := Color("9fd8ff")

var map: WorldMapData
var state: GameState
var zoom_index: int = 2
var cursor: Vector2 = Vector2.ZERO  # world-map px
var current_room: String = ""
var player_pos: Vector2 = Vector2.ZERO  # room-local
var _t: float = 0.0
var _last_hover: String = ""


func setup(p_map: WorldMapData, p_state: GameState, room_id: String, local_pos: Vector2) -> void:
	map = p_map
	state = p_state
	current_room = room_id
	player_pos = local_pos
	var r := map.room(room_id)
	cursor = r.offset + local_pos if r else Vector2.ZERO
	queue_redraw()


func zoom() -> float:
	return ZOOMS[zoom_index]


func to_screen(p: Vector2) -> Vector2:
	return (p - cursor) * zoom() + size * 0.5


func _process(delta: float) -> void:
	if not is_visible_in_tree() or map == null:
		return
	_t += delta
	var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if move == Vector2.ZERO:
		move = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	cursor += move * PAN_SPEED * delta / zoom()
	if Input.is_action_just_pressed("ranged"):
		zoom_index = mini(zoom_index + 1, ZOOMS.size() - 1)
	if Input.is_action_just_pressed("grapple"):
		zoom_index = maxi(zoom_index - 1, 0)
	if Input.is_action_just_pressed("jump"):
		toggle_pin_at_cursor()
	var hover := hover_text()
	if hover != _last_hover:
		_last_hover = hover
		hover_changed.emit(hover)
	queue_redraw()


## Pins go in the room under the cursor; outside known rooms nothing happens.
func toggle_pin_at_cursor() -> bool:
	var r := room_at(cursor)
	if r == null:
		return false
	Game.toggle_pin(r.room_id(), cursor - r.offset)
	return true


func room_at(p: Vector2) -> MapRoomData:
	for r in map.rooms:
		var b: Rect2 = WorldMapIndex.room_info(r.room_path)["bounds"]
		if Rect2(b.position + r.offset, b.size).has_point(p) and _known(r):
			return r
	return null


func hover_text() -> String:
	var r := room_at(cursor)
	if r == null:
		return ""
	var info := WorldMapIndex.room_info(r.room_path)
	var text := "%s  —  %s" % [info["district_name"], info["name"]]
	var best := 18.0 / zoom()
	for n: Dictionary in visible_npcs(info):
		if _visited(r) and (r.offset + n["pos"]).distance_to(cursor) < best:
			text += "   ·   %s (%s)" % [n["name"], n["role"]] if n["role"] != "" else ""
	for a: Dictionary in info["anchors"]:
		if _cell_seen(r, a["pos"]) and (r.offset + a["pos"]).distance_to(cursor) < best:
			text += "   ·   Anchor%s" % ("  (transit)" if state.anchors_rested.has("%s|%s" % [r.room_path, a["id"]]) else "")
	for m: Dictionary in info["markers"]:
		if int(m["kind"]) == MapMarker.Kind.NOTE and WorldMapIndex.marker_active(m) and (r.offset + m["pos"]).distance_to(cursor) < best:
			text += "   ·   " + String(m["label"])
	return text


# --- Visibility rules ---------------------------------------------------------

## NPCs currently in the room (present_when, M7): a character who moved on
## loses their pin here and gains one where they went.
static func visible_npcs(info: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n: Dictionary in info.get("npcs", []):
		if WorldMapIndex.npc_present(n):
			out.append(n)
	return out


func _visited(r: MapRoomData) -> bool:
	return state.visited_rooms.has(r.room_path)


func _known(r: MapRoomData) -> bool:
	return MapProgress.knows_outline(state, r)


func _cell_seen(r: MapRoomData, local: Vector2) -> bool:
	var info := WorldMapIndex.room_info(r.room_path)
	var b: Rect2 = info["bounds"]
	var g := MapProgress.grid(map, r.room_path)
	var c := ((local - b.position) / map.cell_size).floor()
	if c.x < 0 or c.y < 0 or c.x >= g.x or c.y >= g.y:
		return false
	return MapProgress.is_explored(state, r.room_id(), int(c.y) * g.x + int(c.x))


# --- Drawing --------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	if map == null:
		return
	var z := zoom()
	for r in map.rooms:
		if _known(r):
			_draw_room(r, z)
	_draw_transit_links()
	for r in map.rooms:
		if _known(r):
			_draw_room_icons(r, z)
	_draw_pins()
	_draw_player()
	# Cursor crosshair.
	var c := size * 0.5
	draw_line(c + Vector2(-6, 0), c + Vector2(-2, 0), Color.WHITE)
	draw_line(c + Vector2(2, 0), c + Vector2(6, 0), Color.WHITE)
	draw_line(c + Vector2(0, -6), c + Vector2(0, -2), Color.WHITE)
	draw_line(c + Vector2(0, 2), c + Vector2(0, 6), Color.WHITE)


func _draw_room(r: MapRoomData, z: float) -> void:
	var info := WorldMapIndex.room_info(r.room_path)
	var b: Rect2 = info["bounds"]
	var g := MapProgress.grid(map, r.room_path)
	for i in g.x * g.y:
		if MapProgress.is_explored(state, r.room_id(), i):
			var cr := MapProgress.cell_rect(map, r.room_path, i)
			draw_rect(Rect2(to_screen(cr.position + r.offset), cr.size * z), COL_CELL)
	for blk: Dictionary in info["blocks"]:
		var rect: Rect2 = blk["rect"]
		for piece in _explored_parts(r, rect):
			draw_rect(Rect2(to_screen(piece.position + r.offset), (piece.size * z).max(Vector2.ONE)), COL_ONEWAY if blk["one_way"] else COL_BLOCK)
	draw_rect(Rect2(to_screen(b.position + r.offset), b.size * z), COL_OUTLINE, false, 1.0)
	for e: Dictionary in info["exits"]:
		var er: Rect2 = e["rect"]
		draw_rect(Rect2(to_screen(er.position + r.offset), (er.size * z).max(Vector2(2, 2))), COL_OUTLINE.lightened(0.3))


## The parts of a geometry rect that lie in explored cells.
func _explored_parts(r: MapRoomData, rect: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var b: Rect2 = WorldMapIndex.room_info(r.room_path)["bounds"]
	var g := MapProgress.grid(map, r.room_path)
	var lo := ((rect.position - b.position) / map.cell_size).floor()
	var hi := ((rect.end - b.position) / map.cell_size).floor()
	for cy in range(maxi(0, int(lo.y)), mini(g.y - 1, int(hi.y)) + 1):
		for cx in range(maxi(0, int(lo.x)), mini(g.x - 1, int(hi.x)) + 1):
			if MapProgress.is_explored(state, r.room_id(), cy * g.x + cx):
				var part := rect.intersection(MapProgress.cell_rect(map, r.room_path, cy * g.x + cx))
				if part.has_area():
					out.append(part)
	return out


func _draw_room_icons(r: MapRoomData, z: float) -> void:
	var info := WorldMapIndex.room_info(r.room_path)
	var font := get_theme_default_font()
	for a: Dictionary in info["anchors"]:
		if _cell_seen(r, a["pos"]):
			var p := to_screen(r.offset + a["pos"] + Vector2(0, -16))
			var pts := PackedVector2Array([p + Vector2(0, -4), p + Vector2(4, 0), p + Vector2(0, 4), p + Vector2(-4, 0)])
			if state.anchors_rested.has("%s|%s" % [r.room_path, a["id"]]):
				draw_colored_polygon(pts, COL_ANCHOR)
			else:
				draw_polyline(pts + PackedVector2Array([pts[0]]), COL_ANCHOR)
	for g: Dictionary in info["gates"]:
		var closed: bool = bool(g["closed"]) and (g["flag"] == "" or not Game.has_flag(g["flag"]))
		var rect: Rect2 = g["rect"]
		if closed and _cell_seen(r, rect.get_center()):
			var p := to_screen(r.offset + rect.get_center())
			draw_rect(Rect2(p - Vector2(3, 4), Vector2(6, 8)), COL_GATE, false, 1.0)
			draw_line(p + Vector2(-3, 0), p + Vector2(3, 0), COL_GATE)
	for m: Dictionary in info["markers"]:
		if not WorldMapIndex.marker_active(m):
			continue
		if int(m["kind"]) == MapMarker.Kind.NOTE:
			# Rumours: shown once the room's outline is known (someone told
			# Rook), in the quest-note look.
			if _known(r):
				var p := to_screen(r.offset + m["pos"])
				draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), COL_NOTE)
				draw_string(font, p + Vector2(5, 3), m["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 6, COL_NOTE)
		elif _cell_seen(r, m["pos"]):
			var p := to_screen(r.offset + m["pos"])
			draw_circle(p, 4.0, COL_GATE)
			draw_string(font, p + Vector2(-2, 3), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, COL_BG)
	if _visited(r):
		for n: Dictionary in visible_npcs(info):
			if n["role"] == "":
				continue
			var p := to_screen(r.offset + n["pos"] + Vector2(0, -14))
			draw_circle(p, 3.5, COL_NPC)
			draw_string(font, p + Vector2(-2.5, 3), String(n["name"]).left(1), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, COL_BG)
		for boss: Dictionary in info["bosses"]:
			var p := to_screen(r.offset + boss["pos"])
			draw_circle(p, 5.0, COL_ANCHOR, false, 1.5)
			if Game.has_flag(boss["flag"]):
				draw_line(p + Vector2(-4, -4), p + Vector2(4, 4), COL_ANCHOR, 1.5)
				draw_line(p + Vector2(-4, 4), p + Vector2(4, -4), COL_ANCHOR, 1.5)
			else:
				draw_circle(p, 2.0, COL_ANCHOR)
	# Secret hint: that something is left, never where (bible §20).
	if Game.has_flag("map_lens"):
		var left := 0
		for s: Dictionary in info["secrets"]:
			if not Game.is_collected(s["id"]):
				left += 1
		if left > 0:
			var b: Rect2 = info["bounds"]
			var p := to_screen(r.offset + b.get_center())
			draw_string(font, p + Vector2(-3, 4), "?" if left == 1 else "?%d" % left, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_NOTE)
	# Quest map notes for active stages in this room.
	for q in Game.quests.active_quests():
		var i := q.current_stage()
		if i < q.stages.size() and q.stages[i].map_room == r.room_id():
			var p := to_screen(r.offset + q.stages[i].map_pos)
			draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), COL_NOTE)
			draw_string(font, p + Vector2(5, 3), q.stages[i].map_note, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, COL_NOTE)
	# The dropped Scrap cache (bible §7: recoverable).
	var drop := state.dropped_scrap
	if drop.get("room", "") == r.room_path and int(drop.get("amount", 0)) > 0:
		var p := to_screen(r.offset + Vector2(float(drop["x"]), float(drop["y"]) - 8))
		draw_circle(p, 3.0, COL_PIN)


func _draw_transit_links() -> void:
	for link in map.transit_links:
		var a := map.room(link.get_slice(">", 0))
		var b := map.room(link.get_slice(">", 1))
		if a == null or b == null or not (_visited(a) and _visited(b)):
			continue
		for e: Dictionary in WorldMapIndex.room_info(a.room_path)["exits"]:
			if String(e["target"]).get_file().get_basename() == b.room_id() and (e["flag"] == "" or Game.has_flag(e["flag"])):
				var spawns: Dictionary = WorldMapIndex.room_info(b.room_path)["spawns"]
				var from := to_screen(a.offset + (e["rect"] as Rect2).get_center())
				var to := to_screen(b.offset + spawns.get(e["entry"], Vector2.ZERO))
				draw_dashed_line(from, to, COL_OUTLINE, 1.0, 4.0)


func _draw_pins() -> void:
	for pin: Dictionary in state.map_pins:
		var r := map.room(pin["room"])
		if r == null:
			continue
		var p := to_screen(r.offset + Vector2(float(pin["x"]), float(pin["y"])))
		draw_line(p, p + Vector2(0, -8), COL_PIN, 1.0)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -8), p + Vector2(5, -6), p + Vector2(0, -4)]), COL_PIN)


func _draw_player() -> void:
	var r := map.room(current_room)
	if r == null:
		return
	var p := to_screen(r.offset + player_pos + Vector2(0, -16))
	var a := 0.55 + 0.45 * sin(_t * 6.0)
	draw_circle(p, 4.0, Color(COL_ANCHOR, a))
	draw_circle(p, 1.5, Color.WHITE)
