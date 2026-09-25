class_name SliceStats
extends RefCounted
## Counts discoverables across the slice's rooms (for the journal and the end
## card) by scanning the room scenes, so totals never drift from content.

## District room folders come from ContentValidator.WORLD_ROOM_DIRS (labs
## and backdrops in res://world/rooms are not content).

static var _totals: Dictionary = {}
## How many times totals() actually scanned the rooms (the cache is per
## session); tests read it to prove a warm-up happened once.
static var build_count: int = 0


static func totals() -> Dictionary:
	if not _totals.is_empty():
		return _totals
	build_count += 1
	var secrets: Array[String] = []
	var fragments := 0
	var shards := 0
	for path in room_paths():
		var inst := (load(path) as PackedScene).instantiate()
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


## Every district room scene, sorted per folder. DataDir also accepts the
## ".tscn.remap" names an exported build lists (otherwise totals are empty
## there and every secrets count reads 0).
static func room_paths() -> PackedStringArray:
	var out := PackedStringArray()
	for dir in ContentValidator.WORLD_ROOM_DIRS:
		out.append_array(DataDir.list_scenes(dir))
	return out


static func secrets_found() -> int:
	var found := 0
	for id in totals()["secret_ids"]:
		if Game.is_collected(id):
			found += 1
	return found


static func format_time(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]
