extends PlayerState
## Brief loss of control after taking a hit. Knockback velocity is set by
## PlayerCombat before entering. While dead, Rook stays here until respawn.


func enter(_previous: StringName) -> void:
	player.set_low(false)


func physics_update(input: PlayerInputFrame, delta: float) -> StringName:
	player.apply_gravity(delta, input)
	player.velocity.x = move_toward(player.velocity.x, 0.0, config.air_decel * delta)
	if player.combat.dead:
		return &""
	if time_in_state >= player.combat.config.hurt_stun_time:
		return &"air" if not player.is_on_floor() else settle_state(input)
	return &""


func debug_label() -> String:
	return "dead" if player.combat.dead else "hurt"
