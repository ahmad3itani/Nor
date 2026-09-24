class_name MapProgress
extends RefCounted
## Fog of discovery (bible §20): each room is a grid of cells (map.cell_size);
## a cell is explored once Rook has been within reveal_radius of its centre.
## Explored cells live in GameState.map_explored as one bitset per room.
## Room outlines are known once the room is visited or its district's base
## map was bought from Nix (flag "map_<district>").


static func grid(map: WorldMapData, room_path: String) -> Vector2i:
	var b: Rect2 = WorldMapIndex.room_info(room_path).get("bounds", Rect2())
	return Vector2i(ceili(b.size.x / map.cell_size), ceili(b.size.y / map.cell_size))


static func cell_rect(map: WorldMapData, room_path: String, index: int) -> Rect2:
	var b: Rect2 = WorldMapIndex.room_info(room_path)["bounds"]
	var g := grid(map, room_path)
	var c := Vector2(index % g.x, index / g.x)
	return Rect2(b.position + c * map.cell_size, Vector2.ONE * map.cell_size).intersection(b)


## Marks cells around `local_pos` explored. Returns the number newly revealed.
static func reveal(state: GameState, map: WorldMapData, room_path: String, local_pos: Vector2) -> int:
	var info := WorldMapIndex.room_info(room_path)
	if info.is_empty():
		return 0
	var b: Rect2 = info["bounds"]
	var g := grid(map, room_path)
	var id := room_path.get_file().get_basename()
	var bits: PackedByteArray = state.map_explored.get(id, PackedByteArray())
	if bits.size() < (g.x * g.y + 7) / 8:
		bits.resize((g.x * g.y + 7) / 8)
	var r := map.reveal_radius
	var lo := ((local_pos - Vector2(r, r) - b.position) / map.cell_size).floor()
	var hi := ((local_pos + Vector2(r, r) - b.position) / map.cell_size).floor()
	var fresh := 0
	for cy in range(maxi(0, int(lo.y)), mini(g.y - 1, int(hi.y)) + 1):
		for cx in range(maxi(0, int(lo.x)), mini(g.x - 1, int(hi.x)) + 1):
			var centre := b.position + (Vector2(cx, cy) + Vector2(0.5, 0.5)) * map.cell_size
			if centre.distance_to(local_pos) > r:
				continue
			var i := cy * g.x + cx
			if bits[i >> 3] & (1 << (i & 7)) == 0:
				bits[i >> 3] |= 1 << (i & 7)
				fresh += 1
	state.map_explored[id] = bits
	return fresh


static func is_explored(state: GameState, room_id: String, index: int) -> bool:
	var bits: PackedByteArray = state.map_explored.get(room_id, PackedByteArray())
	return (index >> 3) < bits.size() and bits[index >> 3] & (1 << (index & 7)) != 0


static func explored_count(state: GameState, room_id: String) -> int:
	var n := 0
	for byte in state.map_explored.get(room_id, PackedByteArray()):
		var v: int = byte
		while v:
			n += v & 1
			v >>= 1
	return n


static func room_ratio(state: GameState, map: WorldMapData, room_path: String) -> float:
	var g := grid(map, room_path)
	return float(explored_count(state, room_path.get_file().get_basename())) / maxi(1, g.x * g.y)


static func district_ratio(state: GameState, map: WorldMapData, district: String) -> float:
	var total := 0
	var seen := 0
	for r in map.rooms_in(district):
		var g := grid(map, r.room_path)
		total += g.x * g.y
		seen += explored_count(state, r.room_id())
	return float(seen) / maxi(1, total)


static func knows_outline(state: GameState, room: MapRoomData) -> bool:
	return state.visited_rooms.has(room.room_path) or state.flags.has("map_%s" % room.district)
