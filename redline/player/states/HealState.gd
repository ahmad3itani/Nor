extends PlayerState
## Channel an injector while standing still (bible §7). Committing to a heal
## is a risk: getting hit forces HurtState and the injector is not used.
## Jump or dodge cancel it early, also without using the injector.


func enter(_previous: StringName) -> void:
	player.combat.heal_buffer = 0.0
	AudioManager.play_sfx(&"heal_start")


func physics_update(input: PlayerInputFrame, delta: float) -> StringName:
	if not player.is_on_floor():
		return &"air"
	if player.wants_evade():
		return player.evade_state()
	if player.jump_buffered():
		player.start_jump(&"ground")
		return &"air"
	player.velocity.x = move_toward(player.velocity.x, 0.0, config.ground_decel * delta)
	player.apply_gravity(delta, input)
	if time_in_state >= player.combat.config.heal_time:
		player.combat.finish_heal()
		return settle_state(input)
	return &""


func debug_label() -> String:
	return "heal %.0f%%" % (100.0 * time_in_state / player.combat.config.heal_time)
