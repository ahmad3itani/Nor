extends PlayerState


func physics_update(input: PlayerInputFrame, delta: float) -> StringName:
	var next := ground_transitions(input)
	if next:
		return next
	if input.down_held:
		return &"crouch"
	if input.move_x != 0:
		return &"run"
	player.apply_horizontal(delta, 0, true)
	player.apply_gravity(delta, input)
	return &""
