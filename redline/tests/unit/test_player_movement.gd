extends RedlineTestCase
## Physics-level movement tests: drive the real Player scene with scripted input
## on graybox geometry and measure outcomes (M1 acceptance: reliable coyote,
## buffer, slide transitions, no geometry sticking).

const PLAYER_SCENE := preload("res://player/Player.tscn")

var world: Node2D
var player: Player
var input: ScriptedInputSource
var cfg: PlayerMovementConfig


func before_each() -> void:
	world = Node2D.new()
	add_child(world)
	cfg = load("res://data/movement/default_movement.tres")


func after_each() -> void:
	world.queue_free()
	await physics_frames(1)


func _block(pos: Vector2, size: Vector2, one_way := false) -> void:
	var b := GrayboxBlock.new()
	b.size = size
	b.one_way = one_way
	b.position = pos
	world.add_child(b)


func _spawn(pos: Vector2, dash := false) -> void:
	player = PLAYER_SCENE.instantiate()
	player.abilities = PlayerAbilities.new()
	player.abilities.dash = dash
	input = ScriptedInputSource.new()
	player.input_source = input
	world.add_child(player)
	player.respawn(pos)


## Spawns on a wide floor (top at y=0) and waits until grounded.
func _spawn_grounded(x: float = 0.0, dash := false) -> void:
	_block(Vector2(-400, 0), Vector2(1600, 64))
	_spawn(Vector2(x, -2), dash)
	await physics_frames(5)


func _run_until_airborne(max_frames: int) -> bool:
	for i in max_frames:
		await physics_frames(1)
		if not player.is_on_floor():
			return true
	return false


func test_falls_and_settles_idle() -> void:
	await _spawn_grounded()
	await physics_frames(20)
	check(player.is_on_floor(), "not grounded")
	check(player.current_state_id() == &"idle", "state is %s" % player.current_state_id())
	check_near(player.global_position.y, 0.0, 0.6, "feet on floor")


func test_full_jump_reaches_authored_height() -> void:
	await _spawn_grounded()
	input.press_jump()
	var min_y := 0.0
	for i in 60:
		await physics_frames(1)
		min_y = minf(min_y, player.global_position.y)
	check_near(-min_y, cfg.jump_height, 1.5, "held jump height")
	check(player.is_on_floor(), "did not land again")
	check_near(player.metrics.last_jump_height, -min_y, 0.5, "metrics overlay height matches measured")


func test_short_hop_is_much_lower() -> void:
	await _spawn_grounded()
	input.press_jump()
	await physics_frames(2)
	input.release_jump()
	var min_y := 0.0
	for i in 60:
		await physics_frames(1)
		min_y = minf(min_y, player.global_position.y)
	check(-min_y < cfg.jump_height * 0.5, "short hop too high: %.1f" % -min_y)
	check(-min_y > 8.0, "short hop too low: %.1f" % -min_y)


func _setup_ledge() -> void:
	_block(Vector2(-200, 0), Vector2(300, 64))  # floor ends at x=100
	_spawn(Vector2(40, -2))
	await physics_frames(5)


func test_coyote_jump_after_leaving_ledge() -> void:
	await _setup_ledge()
	input.move_x = 1
	check(await _run_until_airborne(60), "never left the ledge")
	await physics_frames(3)  # 3 frames = 0.05s < coyote_time
	input.press_jump()
	await physics_frames(1)
	check(player.velocity.y < -200.0, "coyote jump did not fire (vy=%.1f)" % player.velocity.y)


func test_no_jump_after_coyote_expires() -> void:
	await _setup_ledge()
	input.move_x = 1
	check(await _run_until_airborne(60), "never left the ledge")
	await physics_frames(int(ceil(cfg.coyote_time * 60.0)) + 3)
	input.press_jump()
	await physics_frames(1)
	check(player.velocity.y > 0.0, "jumped after coyote expired (vy=%.1f)" % player.velocity.y)


func test_jump_buffer_fires_on_landing() -> void:
	_block(Vector2(-200, 0), Vector2(400, 64))
	_spawn(Vector2(0, -80))
	# Press while still falling, a few frames before touching down.
	for i in 120:
		await physics_frames(1)
		if player.global_position.y > -14.0:
			break
	check(not player.is_on_floor(), "landed before the buffered press could be tested")
	input.press_jump()
	var jumped := false
	for i in int(cfg.jump_buffer_time * 60.0) + 2:
		await physics_frames(1)
		if player.velocity.y < -200.0:
			jumped = true
			break
	check(jumped, "buffered jump did not fire on landing")


func test_slide_through_low_tunnel_without_sticking() -> void:
	_block(Vector2(-200, 0), Vector2(1200, 64))
	_block(Vector2(200, -200), Vector2(200, 176))  # tunnel: 24px clearance, x 200..400
	_spawn(Vector2(0, -2))
	await physics_frames(5)
	input.move_x = 1
	for i in 120:  # run up to speed, then slide just before the entrance
		await physics_frames(1)
		if player.global_position.x >= 130.0:
			break
	input.down_held = true
	await physics_frames(2)
	check(player.current_state_id() == &"slide", "did not slide (state %s)" % player.current_state_id())
	for i in 60:
		await physics_frames(1)
		if player.global_position.x > 215.0:
			break
	input.down_held = false  # release inside the tunnel: must stay low, not pop up
	var was_blocked_crouch := false
	for i in 400:
		await physics_frames(1)
		var x := player.global_position.x
		if x > 210.0 and x < 390.0:
			check(player.is_low, "stood up inside tunnel at x=%.1f" % x)
			if player.current_state_id() == &"crouch":
				was_blocked_crouch = true
		if x > 440.0:
			break
	check(was_blocked_crouch, "never crouch-walked under the ceiling")
	check(player.global_position.x > 420.0, "stuck in tunnel at x=%.1f" % player.global_position.x)
	await physics_frames(3)
	check(not player.is_low, "did not stand up after exiting")
	check_near(player.global_position.y, 0.0, 0.6, "left the floor")


func test_dodge_distance_iframes_and_cooldown() -> void:
	await _spawn_grounded()
	var start_x := player.global_position.x
	input.press_dodge()
	var saw_iframes := false
	var frames := int(round(cfg.dodge_duration * 60.0))
	for i in frames:
		await physics_frames(1)
		check(player.current_state_id() == &"dodge", "left dodge early at frame %d" % i)
		saw_iframes = saw_iframes or player.invulnerable
	check(saw_iframes, "no i-frames during dodge")
	check_near(player.global_position.x - start_x, cfg.dodge_speed * cfg.dodge_duration, 8.0, "dodge distance")
	await physics_frames(2)
	input.press_dodge()
	await physics_frames(1)
	check(player.current_state_id() != &"dodge", "cooldown did not block an immediate re-dodge")


func test_evade_is_dodge_until_dash_unlocked() -> void:
	await _spawn_grounded(0.0, false)
	input.press_dodge()
	await physics_frames(1)
	check(player.current_state_id() == &"dodge", "expected dodge without unlock")
	player.abilities.dash = true
	await physics_frames(40)
	input.press_dodge()
	await physics_frames(1)
	check(player.current_state_id() == &"dash", "expected dash with unlock")


func test_dash_exit_preserves_momentum() -> void:
	await _spawn_grounded(0.0, true)
	input.move_x = 1
	input.press_dodge()
	await physics_frames(int(ceil(cfg.dash_duration * 60.0)) + 1)
	check(player.velocity.x > cfg.max_run_speed + 20.0, "momentum lost on dash exit (vx=%.1f)" % player.velocity.x)
	await physics_frames(60)
	check_near(player.velocity.x, cfg.max_run_speed, 1.0, "overspeed should settle at run speed")


func test_corner_correction_slips_past_ceiling_edge() -> void:
	_block(Vector2(-200, 0), Vector2(600, 64))
	_block(Vector2(0, -76), Vector2(100, 16))  # ceiling underside at y=-60, right edge x=100
	_spawn(Vector2(103, -2))  # body overlaps the edge by 3px
	await physics_frames(5)
	input.press_jump()
	var min_y := 0.0
	for i in 40:
		await physics_frames(1)
		min_y = minf(min_y, player.global_position.y)
	check(min_y < -45.0, "jump was blocked by the ceiling corner (peak %.1f)" % min_y)
	check(player.global_position.x >= 106.0, "not nudged clear (x=%.1f)" % player.global_position.x)


func test_ledge_forgiveness_steps_onto_ledge() -> void:
	_block(Vector2(-200, 0), Vector2(600, 64))
	_block(Vector2(200, -60), Vector2(64, 60))  # ledge top at y=-60
	_spawn(Vector2(192, -57))  # feet 3px below the ledge top, touching its wall
	player.velocity = Vector2(cfg.max_run_speed, 0.0)
	input.move_x = 1
	await physics_frames(20)
	check(player.global_position.x > 205.0, "did not get onto the ledge (x=%.1f)" % player.global_position.x)
	check_near(player.global_position.y, -60.0, 1.0, "not standing on ledge top")


func test_drop_through_one_way() -> void:
	_block(Vector2(-200, 0), Vector2(600, 64))
	_block(Vector2(-50, -48), Vector2(100, 8), true)
	_spawn(Vector2(0, -60))
	await physics_frames(20)
	check_near(player.global_position.y, -48.0, 0.6, "not standing on one-way platform")
	input.down_held = true
	input.press_jump()
	await physics_frames(40)
	input.down_held = false
	check_near(player.global_position.y, 0.0, 0.6, "did not drop to the floor")


func test_one_way_can_be_jumped_through_from_below() -> void:
	_block(Vector2(-200, 0), Vector2(600, 64))
	_block(Vector2(-50, -40), Vector2(100, 8), true)
	_spawn(Vector2(0, -2))
	await physics_frames(5)
	input.press_jump()
	await physics_frames(60)
	check_near(player.global_position.y, -40.0, 0.6, "did not land on the one-way platform")


func test_jump_height_holds_at_120hz() -> void:
	# Tuning must not depend on tick rate (the F8 high-refresh experiment).
	Engine.physics_ticks_per_second = 120
	await physics_frames(2)
	await _spawn_grounded()
	input.press_jump()
	var min_y := 0.0
	for i in 120:
		await physics_frames(1)
		min_y = minf(min_y, player.global_position.y)
	Engine.physics_ticks_per_second = 60
	check_near(-min_y, cfg.jump_height, 1.5, "held jump height at 120 Hz")
