extends PlayerState
## Also covers deceleration to a stop, so releasing input never pops to Idle
## while still sliding across the floor.


func physics_update(input: PlayerInputFrame, delta: float) -> StringName:
	var next := ground_transitions(input)
	if next:
		return next
	if input.down_held:
		if player.can_slide():
			return &"slide"
		return &"crouch"
	if input.move_x != 0:
		player.facing = input.move_x
	player.apply_horizontal(delta, input.move_x, true)
	player.apply_gravity(delta, input)
	if input.move_x == 0 and is_zero_approx(player.velocity.x):
		return &"idle"
	return &""
