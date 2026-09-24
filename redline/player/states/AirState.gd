extends PlayerState
## Single airborne state for rising, apex and falling. Sub-phases only change
## gravity/air control, so splitting them into states would duplicate logic.


func enter(_previous: StringName) -> void:
	if player.is_low:
		player.set_low(false)


func physics_update(input: PlayerInputFrame, delta: float) -> StringName:
	if player.is_on_floor() and player.velocity.y >= 0.0:
		return _landing_state(input)
	if player.is_low:
		player.set_low(false)

	# Coyote jump: a buffered press shortly after walking off a ledge.
	if player.jump_buffered() and player.coyote_timer > 0.0:
		player.start_jump(&"coyote")
	elif player.wants_evade():
		return player.evade_state()

	# Variable jump: releasing early cuts the rise once.
	if player.jump_cut_available and player.velocity.y < 0.0 and not input.jump_held:
		player.velocity.y *= config.jump_cut_multiplier
		player.jump_cut_available = false
	if player.velocity.y >= 0.0:
		player.jump_cut_available = false

	if input.move_x != 0:
		player.facing = input.move_x
	var accel_scale := config.apex_air_accel_bonus if player.is_at_apex() else 1.0
	player.apply_horizontal(delta, input.move_x, false, config.max_run_speed, accel_scale)
	player.apply_gravity(delta, input)
	return &""


func _landing_state(input: PlayerInputFrame) -> StringName:
	# Landing while holding down at speed flows straight into a slide.
	if input.down_held and player.can_slide():
		return &"slide"
	if input.down_held:
		return &"crouch"
	return settle_state(input)


func debug_label() -> String:
	if player.is_at_apex():
		return "air (apex)"
	return "air (rise)" if player.velocity.y < 0.0 else "air (fall)"
