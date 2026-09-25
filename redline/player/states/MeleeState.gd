extends PlayerState
## Executes one melee AttackData: startup -> active (hit queries) -> recovery.
## Movement during the swing comes from the attack data (lunge, friction, air
## hang on hit). Cancels: into the next attack or a jump after cancel_time, into an
## evade after evade_cancel_time (bible §5 "sensible cancels").

var attack: AttackData
var _hit_ids: Dictionary = {}
var _started_on_floor: bool = true
## True once this airborne swing has taken one of the airtime's air hangs:
## on its first hit (AttackData.air_velocity_on_hit), or at the start for a
## dive. Only a hung swing gets the attack's air gravity scale; a whiff (or a
## grounded swing that left the floor on the jump frame) falls like a jump.
## M7 D2b: whiffed hangs let a jump + chained air lights (+ an air dodge)
## glide past every Dash gate and lift a floor jump ~30 px.
var _hung: bool = false


func enter(_previous: StringName) -> void:
	var combat := player.combat
	var input := player.last_input
	if input.move_x != 0:
		player.facing = input.move_x
	_started_on_floor = player.is_on_floor()
	_hung = false
	attack = combat.consume_melee(_started_on_floor, input.up_held)
	_hit_ids.clear()
	player.set_low(false)
	if _started_on_floor:
		var carried := absf(player.velocity.x) * attack.momentum_keep
		player.velocity.x = player.facing * maxf(attack.lunge_speed, carried)
	elif attack.sets_air_velocity and not attack.air_velocity_on_hit:
		_take_hang()
	SlashArc.spawn(player.get_parent(), attack.world_hitbox(player.global_position, player.facing),
		player.facing, Color("ffe9ef"), attack.hitstop >= 0.08)


func exit(_next: StringName) -> void:
	player.combat.on_attack_finished()


func physics_update(input: PlayerInputFrame, delta: float) -> StringName:
	var t := time_in_state
	if t >= attack.evade_cancel_time and player.wants_evade():
		return player.evade_state()
	if t >= attack.cancel_time:
		if player.combat.wants_melee():
			return &"melee"
		if player.jump_buffered() and (player.is_on_floor() or player.coyote_timer > 0.0):
			player.start_jump(&"attack_cancel")
			return &"air"

	if attack.is_active_at(t):
		var landed := player.combat.melee_query(attack, _hit_ids)
		# The air hang: a connecting air swing holds Rook up (limited uses).
		if landed > 0 and not _started_on_floor and not player.is_on_floor() \
				and attack.sets_air_velocity and attack.air_velocity_on_hit:
			_take_hang()

	if player.is_on_floor():
		player.velocity.x = move_toward(player.velocity.x, 0.0, attack.ground_friction * delta)
		player.apply_gravity(delta, input)
	else:
		var vy := player.velocity.y
		player.apply_gravity(delta, input)
		if _hung:
			player.velocity.y = vy + (player.velocity.y - vy) * attack.air_gravity_scale
		player.apply_horizontal(delta, input.move_x, false, config.max_run_speed, 0.3)

	if t >= attack.total_time():
		return &"air" if not player.is_on_floor() else settle_state(input)
	return &""


func _take_hang() -> void:
	if not _hung and player.combat.take_air_hang():
		player.velocity.y = attack.air_velocity_y
		_hung = true


func debug_label() -> String:
	if attack == null:
		return "melee"
	var phase := "startup"
	if attack.is_active_at(time_in_state):
		phase = "ACTIVE"
	elif time_in_state >= attack.startup + attack.active:
		phase = "recovery"
	return "melee %s (%s)" % [attack.id, phase]
