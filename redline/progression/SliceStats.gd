class_name SliceStats
extends RefCounted
## Counts discoverables across the slice's rooms (for the journal and the end
## card) by scanning the room scenes, so totals never drift from content.

const ROOM_DIR := "res://world/rooms/lowlight"

static var _totals: Dictionary = {}


static func totals() -> Dictionary:
	if not _totals.is_empty():
		return _totals
	var secrets: Array[String] = []
	var fragments := 0
	var shards := 0
	for f in DirAccess.get_files_at(ROOM_DIR):
		if not f.ends_with(".tscn"):
			continue
		var inst := (load("%s/%s" % [ROOM_DIR, f]) as PackedScene).instantiate()
		for n in inst.find_children("*", "", true, false):
			if n is Collectible:
				var c := n as Collectible
				# Scrap stashes are the loot inside secrets, not secrets themselves.
				if c.kind == Collectible.Kind.SCRAP_BUNDLE:
					continue
				secrets.append(c.persist_id)
				if c.kind == Collectible.Kind.MEMORY_FRAGMENT:
					fragments += 1
				elif c.kind == Collectible.Kind.CORE_SHARD:
					shards += 1
			elif n is BreakableWall:
				secrets.append((n as BreakableWall).persist_id)
		inst.free()
	_totals = {"secret_ids": secrets, "fragments": fragments, "core_shards": shards}
	return _totals


static func secrets_found() -> int:
	var found := 0
	for id in totals()["secret_ids"]:
		if Game.is_collected(id):
			found += 1
	return found


static func format_time(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]
