extends PlayerState
## Low stance. Entered by holding down, or forced when a slide ends under a
## ceiling. Standing up only happens when there is room (no geometry popping).


func enter(_previous: StringName) -> void:
	player.set_low(true)


func physics_update(input: PlayerInputFrame, delta: float) -> StringName:
	var next := ground_transitions(input)
	if next:
		return next
	if not input.down_held and player.set_low(false):
		return settle_state(input)
	if input.move_x != 0:
		player.facing = input.move_x
	player.apply_horizontal(delta, input.move_x, true, config.crouch_move_speed)
	player.apply_gravity(delta, input)
	return &""


func debug_label() -> String:
	return "crouch" if player.can_stand() else "crouch (blocked)"
