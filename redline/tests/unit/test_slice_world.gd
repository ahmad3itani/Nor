extends RedlineTestCase
## Slice validation (bible §34 traversal validation, broken-reference
## scanner): every Lowlight room loads, exits point at real entries, spawns
## land on solid ground, persistent ids are unique, quest switches exist.

const ROOM_DIR := "res://world/rooms/lowlight"
## Deliberate one-way links. The post-boss lift drops you at the Relay; the
## Relay's lift goes to the Bell Tower, not back up to the arena.
const ONE_WAY_OK := ["WardenTower.tscn>Relay.tscn"]

var root: Node2D


func before_each() -> void:
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	Game.new_game()


func after_each() -> void:
	SceneRouter.current_room = null
	SceneRouter.world_root = null
	root.queue_free()
	Game.new_game()
	await physics_frames(2)


func _room_paths() -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(ROOM_DIR):
		if f.ends_with(".tscn"):
			out.append("%s/%s" % [ROOM_DIR, f])
	return out


func _spawn_ids(scene: PackedScene) -> Array[String]:
	var inst := scene.instantiate()
	var ids: Array[String] = []
	for m in inst.find_children("*", "SpawnMarker", true, false):
		ids.append(String((m as SpawnMarker).spawn_id))
	inst.free()
	return ids


func test_rooms_exist() -> void:
	check(_room_paths().size() >= 7, "expected Relay + 6 Lowlight rooms, got %d" % _room_paths().size())
	check(ResourceLoader.exists(Game.START_ROOM), "Game.START_ROOM missing")


func test_exits_link_to_real_entries_and_back() -> void:
	var links := {}
	for path in _room_paths():
		var inst := (load(path) as PackedScene).instantiate()
		for e in inst.find_children("*", "RoomExit", true, false):
			var exit := e as RoomExit
			check(ResourceLoader.exists(exit.target_room), "%s: exit to missing room %s" % [path, exit.target_room])
			if ResourceLoader.exists(exit.target_room):
				var ids := _spawn_ids(load(exit.target_room))
				check(ids.has(String(exit.target_entry)), "%s: entry '%s' missing in %s" % [path.get_file(), exit.target_entry, exit.target_room.get_file()])
			links[path + ">" + exit.target_room] = true
		inst.free()
	for key: String in links:
		var parts := key.split(">")
		if ONE_WAY_OK.has(parts[0].get_file() + ">" + parts[1].get_file()):
			continue
		check(links.has(parts[1] + ">" + parts[0]), "one-way link %s -> %s has no way back" % [parts[0].get_file(), parts[1].get_file()])


func test_every_spawn_lands_on_ground_and_is_clear_of_exits() -> void:
	for path in _room_paths():
		var ids := _spawn_ids(load(path))
		for id in ids:
			SceneRouter.goto_room(path, StringName(id))
			var room := SceneRouter.current_room as Room
			room.player.input_source = ScriptedInputSource.new()
			await physics_frames(25)
			if SceneRouter.current_room != room:
				check(false, "%s:%s spawn touches an exit" % [path.get_file(), id])
				continue
			check(room.player.is_on_floor(), "%s:%s spawn not on the floor" % [path.get_file(), id])
			check(room.bounds.has_point(room.player.global_position), "%s:%s spawn outside bounds" % [path.get_file(), id])


func test_persistent_ids_unique_and_quest_switches_present() -> void:
	var seen := {}
	var repeater_flags: Array[String] = []
	for path in _room_paths():
		var inst := (load(path) as PackedScene).instantiate()
		for n in inst.find_children("*", "", true, false):
			var pid := ""
			if n is Collectible:
				pid = (n as Collectible).persist_id
			elif n is BreakableWall:
				pid = (n as BreakableWall).persist_id
			elif n is SignalRepeater:
				repeater_flags.append((n as SignalRepeater).flag_id)
			if pid != "":
				check(not seen.has(pid), "duplicate persist_id %s (%s and %s)" % [pid, seen.get(pid, ""), path.get_file()])
				seen[pid] = path.get_file()
			if n is Collectible and (n as Collectible).kind == Collectible.Kind.MEMORY_FRAGMENT:
				check((n as Collectible).fragment != null, "%s: fragment pickup without data" % path.get_file())
		inst.free()
	var quest: QuestData = load("res://data/quests/dead_air.tres")
	for f in quest.stages[0].complete_flags:
		check(repeater_flags.has(f), "quest flag %s has no repeater in the world" % f)


func test_anchors_have_matching_spawns() -> void:
	for path in _room_paths():
		var inst := (load(path) as PackedScene).instantiate()
		var ids: Array[String] = []
		for m in inst.find_children("*", "SpawnMarker", true, false):
			ids.append(String((m as SpawnMarker).spawn_id))
		for a in inst.find_children("*", "Anchor", true, false):
			check(ids.has(String((a as Anchor).anchor_id)), "%s: anchor %s has no spawn marker" % [path.get_file(), (a as Anchor).anchor_id])
		inst.free()


func test_boss_room_is_wired() -> void:
	var inst := (load("%s/WardenTower.tscn" % ROOM_DIR) as PackedScene).instantiate()
	add_child(inst)
	var arenas := inst.find_children("*", "BossArena", true, false)
	check(arenas.size() == 1, "boss arena missing")
	if arenas.size() == 1:
		var arena := arenas[0] as BossArena
		check(arena.boss != null, "boss arena has no boss")
		check(arena.reward_scene != null, "boss arena has no reward")
	inst.queue_free()
	await physics_frames(1)
