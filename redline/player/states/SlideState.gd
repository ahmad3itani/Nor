extends PlayerState
## Committed low dash along the ground. Converts run speed into a burst,
## then bleeds it by friction. Jumping out keeps the momentum (slide-jump).

var _dir: int = 1


func enter(_previous: StringName) -> void:
	player.set_low(true)
	_dir = int(signf(player.velocity.x)) if not is_zero_approx(player.velocity.x) else player.facing
	player.facing = _dir
	var speed := minf(maxf(absf(player.velocity.x), config.max_run_speed) + config.slide_entry_boost, config.slide_max_speed)
	player.velocity.x = _dir * speed
	player.metrics.slides += 1


func exit(_next: StringName) -> void:
	player.slide_cooldown = config.slide_cooldown


func physics_update(input: PlayerInputFrame, delta: float) -> StringName:
	if not player.is_on_floor():
		return &"air"
	if player.jump_buffered() and player.set_low(false):
		player.start_jump(&"slide", config.slide_jump_height_ratio)
		player.velocity.x += _dir * config.slide_jump_bonus
		return &"air"
	if player.wants_evade():
		return player.evade_state()
	# Slide attack: the swing keeps part of the slide's momentum (momentum_keep).
	if player.combat.wants_melee() and player.set_low(false):
		return &"melee"

	player.velocity.x = move_toward(player.velocity.x, 0.0, config.slide_friction * delta)
	player.apply_gravity(delta, input)

	var released := time_in_state >= config.slide_min_duration and not input.down_held
	var done := time_in_state >= config.slide_max_duration \
		or absf(player.velocity.x) < config.slide_exit_speed or released
	if done:
		if player.set_low(false):
			return settle_state(input)
		return &"crouch"
	return &""
