extends PlayerState
## Dash unlock (Lowlight boss reward, bible §15). Replaces the ground dodge once
## owned: faster, shorter, gravity-free, and it exits above run speed so
## overspeed decel carries the momentum. Air use requires the Air Dash unlock.

var _dir: int = 1


func enter(_previous: StringName) -> void:
	player.consume_evade_buffer()
	player.set_low(false)
	_dir = player.last_move_x if player.last_move_x != 0 else player.facing
	player.facing = _dir
	if not player.is_on_floor():
		player.air_dodges_left -= 1
	player.velocity = Vector2(_dir * config.dash_speed, 0.0)
	player.metrics.dashes += 1
	EventBus.camera_shake_requested.emit(0.08)


func exit(_next: StringName) -> void:
	player.invulnerable = false
	player.evade_cooldown = config.dash_cooldown


func physics_update(input: PlayerInputFrame, _delta: float) -> StringName:
	player.invulnerable = time_in_state < config.dash_iframe_end

	# Dash-jump: jumping out keeps full dash speed; air overspeed decel bleeds it.
	if time_in_state >= config.dash_jump_cancel_time and player.jump_buffered() \
			and (player.is_on_floor() or player.coyote_timer > 0.0):
		player.start_jump(&"dash")
		return &"air"

	if time_in_state >= config.dash_duration:
		player.velocity.x = _dir * config.dash_exit_speed
		return &"air" if not player.is_on_floor() else settle_state(input)

	player.velocity = Vector2(_dir * config.dash_speed, 0.0)
	return &""
