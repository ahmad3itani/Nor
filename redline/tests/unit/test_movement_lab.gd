extends RedlineTestCase
## Traversal validation for the lab room itself: every spawn station must drop
## the player onto solid ground without embedding them in geometry, and the
## kill plane must respawn instantly (bible §34 "traversal validation").

var room: Room


func before_each() -> void:
	room = load("res://world/rooms/MovementLab.tscn").instantiate()
	add_child(room)
	room.player.input_source = ScriptedInputSource.new()
	await physics_frames(2)


func after_each() -> void:
	room.queue_free()
	await physics_frames(1)


func test_every_spawn_lands_cleanly() -> void:
	for i in room.spawns.size():
		room.active_spawn_index = i
		room.respawn()
		await physics_frames(30)
		var marker := room.spawns[i]
		check(room.player.is_on_floor(), "spawn %s: not grounded" % marker.spawn_id)
		check_near(room.player.global_position.y, marker.global_position.y, 1.0,
			"spawn %s: feet not at marker height" % marker.spawn_id)
		check(room.bounds.has_point(room.player.global_position), "spawn %s outside bounds" % marker.spawn_id)


func test_falling_out_of_bounds_respawns() -> void:
	room.player.global_position = Vector2(room.player.global_position.x, room.bounds.end.y + room.kill_margin + 10.0)
	await physics_frames(2)
	check(room.bounds.has_point(room.player.global_position), "player not returned to a spawn")


func test_camera_stays_inside_bounds() -> void:
	for i in room.spawns.size():
		room.active_spawn_index = i
		room.respawn()
		await physics_frames(10)
		var half := room.camera.get_viewport_rect().size * 0.5
		var view := Rect2(room.camera.global_position - half, half * 2.0)
		var grown := room.bounds.grow(1.0)
		check(grown.encloses(view), "camera view leaves bounds at spawn %s" % room.spawns[i].spawn_id)
