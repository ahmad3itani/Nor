extends RedlineTestCase
## Combat Lab room validation: spawns land, enemies exist, flow zones and
## director are present, and nothing errors while the lab runs unattended.

var room: Room


func before_each() -> void:
	room = load("res://world/rooms/CombatLab.tscn").instantiate()
	add_child(room)
	room.player.input_source = ScriptedInputSource.new()
	await physics_frames(3)


func after_each() -> void:
	room.queue_free()
	await physics_frames(2)


func test_lab_has_enemies_zones_and_director() -> void:
	var enemies := get_tree().get_nodes_in_group(&"enemies")
	check(enemies.size() >= 9, "expected >= 9 enemies, got %d" % enemies.size())
	check(room.find_children("*", "FlowZone", true, false).size() >= 3, "missing flow zones")
	check(get_tree().get_first_node_in_group(&"encounter_director") != null, "no encounter director")


func test_every_spawn_lands_cleanly() -> void:
	for i in room.spawns.size():
		room.active_spawn_index = i
		room.respawn()
		await physics_frames(20)
		check(room.player.is_on_floor(), "spawn %s: not grounded" % room.spawns[i].spawn_id)


func test_flow_zone_toggles_reactor_drain() -> void:
	room.active_spawn_index = 0
	room.respawn()
	await physics_frames(5)
	check(not room.player.reactor.in_flow(), "safe start should be outside flow")
	for i in room.spawns.size():
		if room.spawns[i].spawn_id == &"arena1":
			room.active_spawn_index = i
	room.respawn()
	await physics_frames(5)
	check(room.player.reactor.in_flow(), "arena 1 spawn should be inside flow")


func test_unattended_arena_kills_idle_player_and_respawns() -> void:
	for i in room.spawns.size():
		if room.spawns[i].spawn_id == &"arena1":
			room.active_spawn_index = i
	room.respawn()
	# Stand right among the needles so they aggro immediately.
	room.player.respawn(Vector2(730, -2))
	# Lambdas capture locals by value, so record into a shared array.
	var deaths: Array[int] = []
	var on_died := func() -> void: deaths.append(1)
	EventBus.player_died.connect(on_died)
	for i in 60 * 20:
		await physics_frames(1)
		if not deaths.is_empty() and not room.player.combat.dead:
			break
	EventBus.player_died.disconnect(on_died)
	check(not deaths.is_empty(), "idle player never died in arena 1 (enemies not attacking?)")
	check(not room.player.combat.dead, "player did not respawn after death")
