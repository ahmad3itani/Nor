class_name BossBot
extends RefCounted
## Plays the Collector Drone fight with scripted input (bible §34 "boss
## validation"; test_boss_collector's benchmark). It binds a
## ScriptedInputSource the way RouteBot does and reacts each physics frame
## to what the drone shows: its AI state, current attack id, ai_time and
## telegraph_scale, i.e. only what a player can read on screen. Run with
## --fixed-fps 60; the drone's deck is seeded, so a run is deterministic.
##
## Defence (checked first):
##   Press WINDUP  run out of the spotlight until |dx| >= 56
##   Wave WINDUP   jump when ai_time >= scaled startup - 0.1
##   Dive          near the X: dodge toward the drone at ACTIVE + 0.33 s
##   Sweep         jump (held 0.3 s) when the hook's front edge is 40 px out
##   Volley        from the freeze point: stay 24 px clear of every pellet line
## Offence: blade combos on a grounded drone, jump + air light on the sag and
## low lanes, otherwise hold 120 px away; heal at <= 2 pips when safe.
## Profiles: "blade", or "pistol" (fires up when overhead, flat when grounded).

const PRESS_CLEAR := 56.0
const DIVE_ZONE := 40.0
const DIVE_DODGE_AT := 0.33
const SWEEP_JUMP_GAP := 40.0
const PELLET_CLEAR := 24.0
const HOLD := 120.0
const PLAYER_HALF := 6.0

var tree: SceneTree
var player: Player
var input: ScriptedInputSource
var boss: Enemy
var behavior: EnemyBehavior
var profile: String = "blade"
## Room-space x limits Rook can stand in.
var arena: Vector2 = Vector2(64, 440)
var log: PackedStringArray = []

var _jump_hold: int = 0
var _dodged_this_dive: bool = false
var _air_attack_in: int = -1
var _light_cooldown: int = 0
var _chain: int = 0
var _last_attack_id: StringName = &""


func _init(p_tree: SceneTree, p_player: Player, p_boss: Enemy, p_profile: String = "blade") -> void:
	tree = p_tree
	boss = p_boss
	behavior = p_boss.behavior
	profile = p_profile
	player = p_player
	input = ScriptedInputSource.new()
	player.input_source = input


## Fights until the boss dies (won), Rook dies, or max_seconds pass.
## Returns {won, seconds, health}.
func run(max_seconds: float) -> Dictionary:
	var frames := 0
	var limit := int(max_seconds * 60.0)
	var prev_ai := -1
	var prev_hp := boss.health
	var prev_pips := player.combat.health
	while frames < limit:
		if not is_instance_valid(boss) or boss.is_dead():
			break
		if player.combat.dead:
			break
		step()
		await tree.physics_frame
		frames += 1
		if not is_instance_valid(boss):
			break
		var id := String(boss.current_attack.id) if boss.current_attack else "-"
		if boss.ai != prev_ai:
			log.append("%.2f %s %s y%.0f" % [frames / 60.0, Enemy.AI.keys()[boss.ai], id, _bpos().y])
			prev_ai = boss.ai
		if boss.health < prev_hp:
			log.append("%.2f dmg %.0f in %s %s" % [frames / 60.0, prev_hp - boss.health, Enemy.AI.keys()[boss.ai], id])
			prev_hp = boss.health
		if player.combat.health < prev_pips:
			log.append("%.2f HURT by %s" % [frames / 60.0, player.combat.last_damage_source])
		prev_pips = player.combat.health
	var won := (not is_instance_valid(boss) or boss.is_dead()) and not player.combat.dead
	input.move_x = 0
	input.up_held = false
	input.release_jump()
	return {"won": won, "seconds": frames / 60.0, "health": player.combat.health}


func _room(p: Vector2) -> Vector2:
	return behavior.to_room(p) if behavior.has_method("to_room") else p


## One frame of decisions.
func step() -> void:
	input.move_x = 0
	input.up_held = false
	if _jump_hold > 0:
		_jump_hold -= 1
		if _jump_hold == 0:
			input.release_jump()
	_light_cooldown = maxi(_light_cooldown - 1, 0)
	if _air_attack_in >= 0:
		_air_attack_in -= 1
		if _air_attack_in == 0:
			_fire_or_swing_air()
	var attack := boss.current_attack
	var id := attack.id if attack else &""
	if id != _last_attack_id:
		_dodged_this_dive = false
		_last_attack_id = id
	if _defend(id):
		return
	_offend()


func _px() -> float:
	return _room(player.global_position).x


func _bpos() -> Vector2:
	return _room(boss.global_position)


func _move_to(x: float, tolerance: float = 3.0) -> void:
	x = clampf(x, arena.x, arena.y)
	var dx := x - _px()
	input.move_x = 0 if absf(dx) < tolerance else int(signf(dx))


func _face(x: float) -> void:
	# A one-frame tap turns Rook without really moving him.
	var dir := int(signf(x - _px()))
	if dir != 0 and dir != player.facing:
		input.move_x = dir


func _jump(frames: int) -> void:
	if not player.is_on_floor() or _jump_hold > 0:
		return
	input.press_jump()
	_jump_hold = frames


# --- Defence ---------------------------------------------------------------------

func _defend(id: StringName) -> bool:
	var ai := boss.ai
	var t := boss.ai_time
	var s := maxf(boss.telegraph_scale, 0.6)
	var b := _bpos()
	var dx := b.x - _px()
	# Live projectiles first: pellets and waves already in the air.
	if _dodge_projectiles():
		return true
	match id:
		&"collector_drop_press", &"collector_drop_press_p2":
			if ai == Enemy.AI.WINDUP or (ai == Enemy.AI.ACTIVE and not boss.is_on_floor()):
				if absf(dx) < PRESS_CLEAR:
					var left := b.x - PRESS_CLEAR - 4.0
					var right := b.x + PRESS_CLEAR + 4.0
					var go_left := absf(left - _px()) <= absf(right - _px())
					if left < arena.x:
						go_left = false
					elif right > arena.y:
						go_left = true
					_move_to(left if go_left else right, 1.0)
				return true
		&"collector_press_wave":
			if ai == Enemy.AI.WINDUP:
				if t >= boss.current_attack.startup * s - 0.1:
					_jump(24)
				return true
		&"collector_claw_dive":
			if ai == Enemy.AI.WINDUP or ai == Enemy.AI.ACTIVE:
				var land: float = behavior.dive_landing_x() if behavior.has_method("dive_landing_x") else b.x
				if absf(_px() - land) <= DIVE_ZONE + PLAYER_HALF:
					if ai == Enemy.AI.ACTIVE and t >= DIVE_DODGE_AT and not _dodged_this_dive:
						input.move_x = int(signf(dx)) if absf(dx) > 1.0 else player.facing
						input.press_dodge()
						_dodged_this_dive = true
					return true
		&"collector_hook_sweep":
			if (ai == Enemy.AI.WINDUP or ai == Enemy.AI.ACTIVE) and player.is_on_floor():
				var dir := boss.facing
				var front := b.x + dir * 24.0
				var gap := (_px() - dir * PLAYER_HALF - front) * dir
				if ai == Enemy.AI.ACTIVE and gap >= -4.0 and gap <= SWEEP_JUMP_GAP:
					_jump(18)
				# Hands off until the 48 px hook has fully passed under Rook:
				# steering after the drone mid-jump would ride the hook down.
				if gap >= -(48.0 + 2.0 * PLAYER_HALF + 4.0):
					return true
			elif ai == Enemy.AI.ACTIVE and not player.is_on_floor():
				return true
	return false


## Stays clear of volley pellet lines (live or, from the freeze point, about
## to fire) and jumps ground waves.
func _dodge_projectiles() -> bool:
	var lines: Array = []  # [origin (room), direction]
	for n in boss.get_parent().get_children():
		var p := n as Projectile
		if p == null or not is_instance_valid(p) or p.attacker != boss:
			continue
		if p.attack.projectile.ground_wave:
			var wx := _room(p.global_position).x
			var toward := signf(_px() - wx) == signf(p.velocity.x)
			var gap := absf(_px() - wx) - PLAYER_HALF
			if toward and gap < 34.0 and player.is_on_floor():
				_jump(24)
			continue
		lines.append([_room(p.global_position), p.velocity.normalized()])
	var a := boss.current_attack
	if a and a.lock_aim and boss.ai == Enemy.AI.WINDUP:
		var s := maxf(boss.telegraph_scale, 0.6)
		if boss.ai_time >= a.startup * s - 0.3:
			var muzzle := _room(boss.global_position) + Vector2(0, -boss.data.body_size.y * 0.5)
			var proj := a.projectile
			for i in proj.pellets:
				var off := 0.0 if proj.pellets == 1 else lerpf(-proj.spread_deg * 0.5, proj.spread_deg * 0.5, float(i) / (proj.pellets - 1))
				lines.append([muzzle, boss.attack_aim.rotated(deg_to_rad(off))])
	if lines.is_empty():
		return false
	var danger := func(x: float) -> bool:
		for l in lines:
			var o: Vector2 = l[0]
			var d: Vector2 = l[1]
			if d.y <= 0.01:
				if o.y > -40.0 and o.y < 4.0 and signf(x - o.x) == signf(d.x):
					return true
				continue
			# x range where the line crosses Rook's body (feet 0 .. head -34).
			var x_top := o.x + d.x * (-34.0 - o.y) / d.y
			var x_bot := o.x + d.x * (0.0 - o.y) / d.y
			var lo := minf(x_top, x_bot) - PLAYER_HALF - PELLET_CLEAR
			var hi := maxf(x_top, x_bot) + PLAYER_HALF + PELLET_CLEAR
			if x >= lo and x <= hi:
				return true
		return false
	if not danger.call(_px()):
		return false
	# Nearest safe spot, searched outward in 8 px steps.
	for k in range(1, 60):
		for sgn in [1.0, -1.0]:
			var x: float = _px() + sgn * k * 8.0
			if x < arena.x or x > arena.y:
				continue
			if not danger.call(x):
				_move_to(x, 1.0)
				return true
	return false


# --- Offence -------------------------------------------------------------------------

func _offend() -> void:
	var b := _bpos()
	var dx := b.x - _px()
	var ai := boss.ai
	var busy := ai == Enemy.AI.WINDUP or ai == Enemy.AI.ACTIVE
	if player.combat.health <= 2 and not busy and player.combat.injectors > 0 and player.is_on_floor() and absf(dx) > 60.0:
		input.press_heal()
		return
	if player.current_state_id() == &"heal":
		return
	var grounded := b.y > -12.0
	var low := b.y > -100.0 and b.y <= -12.0
	if profile == "pistol":
		_pistol(b, dx, grounded)
		return
	if grounded:
		if absf(dx) <= 28.0:
			_face(b.x)
			if _light_cooldown == 0:
				# One three-hit chain, then a breath (the chain's reset time):
				# how a player actually strings a "light combo".
				input.press_light()
				_chain += 1
				_light_cooldown = 10 if _chain % 3 != 0 else 10 + int(player.combat.config.combo_reset_time * 60.0)
		else:
			_move_to(b.x - signf(dx) * 18.0)
		return
	if low and ai != Enemy.AI.ACTIVE:
		if absf(dx) <= 24.0:
			_face(b.x)
			if player.is_on_floor() and _air_attack_in < 0:
				_jump(20)
				_air_attack_in = 12
		else:
			_move_to(b.x - signf(dx) * 12.0)
		return
	_hold(b)


func _hold(b: Vector2) -> void:
	var side := -1.0 if _px() < b.x else 1.0
	var x := b.x + side * HOLD
	if x < arena.x or x > arena.y:
		x = b.x - side * HOLD
	# A loose hold (+-30 px): shadowing every drift would drag the drone's
	# dive setup point around and time its cards out.
	if absf(_px() - x) > 30.0:
		_move_to(x, 8.0)


func _fire_or_swing_air() -> void:
	if profile == "blade":
		input.press_light()


func _pistol(b: Vector2, dx: float, grounded: bool) -> void:
	if grounded:
		if absf(dx) > 200.0:
			_move_to(b.x - signf(dx) * 150.0)
			return
		_face(b.x)
		if input.move_x == 0:
			input.press_ranged()
		return
	if absf(dx) <= 12.0:
		input.up_held = true
		input.press_ranged()
		return
	_hold(b)
