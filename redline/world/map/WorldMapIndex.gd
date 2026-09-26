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
	RoomTemplate.expand_all(inst)
	var info := {
		"bounds": inst.bounds, "name": inst.room_name, "district_name": inst.district_name,
		"blocks": [], "anchors": [], "npcs": [], "gates": [], "exits": [], "secrets": [],
		"bosses": [], "markers": [], "spawns": {},
		# Generous checkpoints (D4 §8.5): 0 = the entry is a fair respawn,
		# 1 = never. A chase room always says never (its entries sit inside
		# the chase), so no scene edit is needed.
		"respawn_policy": inst.respawn_policy,
	}
	for n in inst.find_children("*", "", true, false):
		var p := local_pos(n, inst)
		if n is GrayboxBlock:
			info["blocks"].append({"rect": Rect2(p, (n as GrayboxBlock).size), "one_way": (n as GrayboxBlock).one_way})
		elif n is Anchor:
			info["anchors"].append({"id": String((n as Anchor).anchor_id), "pos": p})
		elif n is NPC and (n as NPC).profile:
			var prof := (n as NPC).profile
			info["npcs"].append({"id": prof.npc_id, "name": prof.display_name, "role": prof.map_label, "pos": p,
				"present_when": (n as NPC).present_when.duplicate()})
		elif n is Gate:
			info["gates"].append({"rect": Rect2(p, (n as Gate).size), "flag": (n as Gate).open_flag, "closed": (n as Gate).closed})
		elif n is RoomExit:
			var e := n as RoomExit
			info["exits"].append({"rect": Rect2(p, e.size), "target": e.target_room, "entry": String(e.target_entry), "flag": e.requires_flag})
		elif n is Collectible and (n as Collectible).kind != Collectible.Kind.SCRAP_BUNDLE:
			info["secrets"].append({"id": (n as Collectible).persist_id, "pos": p})
		elif n is BreakableWall:
			info["secrets"].append({"id": (n as BreakableWall).persist_id, "pos": p})
		elif n is BossArena:
			var a := n as BossArena
			info["bosses"].append({"flag": a.defeated_flag(), "title": a.boss_title, "pos": p + a.size * 0.5})
		elif n is MapMarker:
			var m := n as MapMarker
			info["markers"].append({"kind": m.kind, "label": m.label, "resolved_when": m.resolved_when,
				"shown_when": m.shown_when, "pos": p})
		elif n is SpawnMarker:
			info["spawns"][String((n as SpawnMarker).spawn_id)] = p
		elif n is ChaseDirector:
			info["respawn_policy"] = 1
	inst.free()
	_cache[room_path] = info
	return info


## The room's generous-checkpoint policy (0 entry OK, 1 never). A path that
## is not a room answers 1, so a bad entry never becomes a respawn point.
static func respawn_policy(room_path: String) -> int:
	if room_path == "" or not ResourceLoader.exists(room_path):
		return 1
	var info := room_info(room_path)
	return int(info.get("respawn_policy", 1)) if not info.is_empty() else 1


## The scan is static (cached per scene), so presence is evaluated when the
## map draws: an NPC whose present_when fails has no pin and no hover text.
static func npc_present(n: Dictionary) -> bool:
	return NPC.conditions_pass(n.get("present_when", PackedStringArray()))


## Whether a scanned marker shows now. Gates and landmarks show until
## resolved; a NOTE shows once shown_when holds and until resolved_when does.
static func marker_active(m: Dictionary) -> bool:
	var resolved: String = m.get("resolved_when", "")
	if int(m.get("kind", MapMarker.Kind.ABILITY_GATE)) == MapMarker.Kind.NOTE:
		return Game.check_condition(m.get("shown_when", "")) and (resolved == "" or not Game.check_condition(resolved))
	return not Game.check_condition(resolved)


static func local_pos(n: Node, root: Node) -> Vector2:
	var p := (n as Node2D).position if n is Node2D else Vector2.ZERO
	var cur := n.get_parent()
	while cur and cur != root:
		if cur is Node2D:
			p += (cur as Node2D).position
		cur = cur.get_parent()
	return p


## Drops the static cache (Cinematics clears every story cache at exit, so
## no Resource outlives its script and the engine reports no leaks).
static func clear_cache() -> void:
	_cache = {}
