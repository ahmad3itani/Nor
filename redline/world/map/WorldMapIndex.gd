class_name WorldMapIndex
extends RefCounted
## Reads what the map needs out of each room scene (geometry, Anchors, NPCs,
## gates, boss, secrets, exits, markers) once, and caches it. The map never
## needs hand-maintained icon lists: move an Anchor in the room and the map
## follows. Positions are room-local.

static var _cache: Dictionary = {}


static func room_info(room_path: String) -> Dictionary:
	if _cache.has(room_path):
		return _cache[room_path]
	var scene := load(room_path) as PackedScene
	if scene == null:
		return {}
	var inst := scene.instantiate() as Room
	var info := {
		"bounds": inst.bounds, "name": inst.room_name, "district_name": inst.district_name,
		"blocks": [], "anchors": [], "npcs": [], "gates": [], "exits": [], "secrets": [],
		"bosses": [], "markers": [], "spawns": {},
	}
	for n in inst.find_children("*", "", true, false):
		var p := local_pos(n, inst)
		if n is GrayboxBlock:
			info["blocks"].append({"rect": Rect2(p, (n as GrayboxBlock).size), "one_way": (n as GrayboxBlock).one_way})
		elif n is Anchor:
			info["anchors"].append({"id": String((n as Anchor).anchor_id), "pos": p})
		elif n is NPC and (n as NPC).profile:
			var prof := (n as NPC).profile
			info["npcs"].append({"id": prof.npc_id, "name": prof.display_name, "role": prof.map_label, "pos": p})
		elif n is Gate:
			info["gates"].append({"rect": Rect2(p, (n as Gate).size), "flag": (n as Gate).open_flag, "closed": (n as Gate).closed})
		elif n is RoomExit:
			var e := n as RoomExit
			info["exits"].append({"rect": Rect2(p, e.size), "target": e.target_room, "entry": String(e.target_entry), "flag": e.requires_flag})
		elif n is Collectible:
			info["secrets"].append({"id": (n as Collectible).persist_id, "pos": p})
		elif n is BreakableWall:
			info["secrets"].append({"id": (n as BreakableWall).persist_id, "pos": p})
		elif n is BossArena:
			var a := n as BossArena
			info["bosses"].append({"flag": a.defeated_flag(), "title": a.boss_title, "pos": p + a.size * 0.5})
		elif n is MapMarker:
			var m := n as MapMarker
			info["markers"].append({"kind": m.kind, "label": m.label, "resolved_when": m.resolved_when, "pos": p})
		elif n is SpawnMarker:
			info["spawns"][String((n as SpawnMarker).spawn_id)] = p
	inst.free()
	_cache[room_path] = info
	return info


static func local_pos(n: Node, root: Node) -> Vector2:
	var p := (n as Node2D).position if n is Node2D else Vector2.ZERO
	var cur := n.get_parent()
	while cur and cur != root:
		if cur is Node2D:
			p += (cur as Node2D).position
		cur = cur.get_parent()
	return p
