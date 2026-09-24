extends PlayerState
## Short, generous evade (bible §8). Fixed distance, i-frame window for M2
## combat, momentum kept on exit. In the air it briefly suspends gravity.

var _dir: int = 1
var _airborne: bool = false


func enter(_previous: StringName) -> void:
	player.consume_evade_buffer()
	player.set_low(false)
	_dir = player.last_move_x if player.last_move_x != 0 else player.facing
	player.facing = _dir
	_airborne = not player.is_on_floor()
	if _airborne:
		player.air_dodges_left -= 1
		player.velocity.y = 0.0
	player.velocity.x = _dir * config.dodge_speed
	player.metrics.dodges += 1


func exit(_next: StringName) -> void:
	player.invulnerable = false
	player.evade_cooldown = config.dodge_cooldown


func physics_update(input: PlayerInputFrame, delta: float) -> StringName:
	var iframe_end := minf(config.dodge_iframe_end * Game.circuit_mult(&"iframe_time"), config.dodge_duration)
	player.invulnerable = time_in_state >= config.dodge_iframe_start and time_in_state < iframe_end

	if time_in_state >= config.dodge_jump_cancel_time and player.jump_buffered() \
			and (player.is_on_floor() or player.coyote_timer > 0.0):
		player.start_jump(&"dodge")
		return &"air"

	if time_in_state >= config.dodge_duration:
		player.velocity.x = _dir * config.max_run_speed * config.dodge_exit_speed_ratio
		return &"air" if not player.is_on_floor() else settle_state(input)

	player.velocity.x = _dir * config.dodge_speed
	if _airborne:
		player.velocity.y = 0.0
	else:
		player.apply_gravity(delta, input)
	return &""


func debug_label() -> String:
	return "dodge (iframes)" if player.invulnerable else "dodge"
