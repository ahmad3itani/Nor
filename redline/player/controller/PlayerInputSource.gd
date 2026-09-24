class_name PlayerInputSource
extends RefCounted
## Samples the live InputMap each physics tick. Keyboard and controller share
## actions, so parity is structural (bible §24, §37.8).


func sample(config: PlayerMovementConfig) -> PlayerInputFrame:
	var f := PlayerInputFrame.new()
	f.move = Input.get_vector("move_left", "move_right", "move_up", "move_down", 0.0)
	f.move_x = 0 if absf(f.move.x) < config.stick_deadzone else int(signf(f.move.x))
	f.down_held = f.move.y >= config.down_threshold
	f.jump_pressed = Input.is_action_just_pressed("jump")
	f.jump_held = Input.is_action_pressed("jump")
	f.dodge_pressed = Input.is_action_just_pressed("dodge")
	f.up_held = f.move.y <= -config.down_threshold
	f.light_pressed = Input.is_action_just_pressed("attack_light")
	f.heavy_pressed = Input.is_action_just_pressed("attack_heavy")
	f.ranged_pressed = Input.is_action_just_pressed("ranged")
	f.interact_pressed = Input.is_action_just_pressed("interact")
	f.heal_pressed = Input.is_action_just_pressed("heal")
	return f
