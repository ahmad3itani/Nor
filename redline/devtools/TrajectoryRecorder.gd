class_name TrajectoryRecorder
extends RefCounted
## Records each jump technique with the real Player on flat ground and
## returns TraversalMetrics (bible §34 traversal validation). The techniques
## are timed "well" (slide 3 frames in, dodge/dash at their jump-cancel time),
## i.e. what a skilled player does at a lip.

const PLAYER_SCENE := preload("res://player/Player.tscn")


static func record(host: Node, cfg: PlayerMovementConfig) -> TraversalMetrics:
	var m := TraversalMetrics.new()
	m.preset_name = cfg.preset_name
	m.body_width = cfg.standing_size.x
	for t in TraversalMetrics.TECHNIQUES:
		m.trajectories[t] = await _record_one(host, cfg, t)
	return m


static func _record_one(host: Node, cfg: PlayerMovementConfig, technique: String) -> PackedVector2Array:
	var tree := host.get_tree()
	var world := Node2D.new()
	host.add_child(world)
	var floor_block := GrayboxBlock.new()
	floor_block.size = Vector2(6000, 64)
	floor_block.position = Vector2(-1000, 0)
	world.add_child(floor_block)
	var p: Player = PLAYER_SCENE.instantiate()
	p.config = cfg
	p.abilities = PlayerAbilities.new()
	p.abilities.dash = technique == "dash_jump"
	var input := ScriptedInputSource.new()
	p.input_source = input
	world.add_child(p)
	p.respawn(Vector2(0, -2))
	for i in 5:
		await tree.physics_frame
	input.move_x = 1
	for i in 30:
		await tree.physics_frame
	match technique:
		"slide_jump":
			input.down_held = true
			for i in 3:
				await tree.physics_frame
		"dodge_jump", "dash_jump":
			input.press_dodge()
			var cancel := cfg.dash_jump_cancel_time if technique == "dash_jump" else cfg.dodge_jump_cancel_time
			for i in int(ceil(cancel * 60.0)) + 1:
				await tree.physics_frame
	var origin := p.global_position
	input.press_jump()
	var pts := PackedVector2Array([Vector2.ZERO])
	for i in 240:
		await tree.physics_frame
		if i == 1:
			input.down_held = false
		pts.append((p.global_position - origin).round())
		if p.is_on_floor() and i > 3:
			break
	world.queue_free()
	await tree.physics_frame
	return pts
