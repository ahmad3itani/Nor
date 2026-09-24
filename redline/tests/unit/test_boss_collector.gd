extends RedlineTestCase
## M7 (M4): the Collector Drone, the Undercity's first boss (bible §23, D-064).
## Behaviour tests run in a hand-built copy of the boss_collector_arena
## fixture's solid geometry mid-fight (tools/roomgen/fixtures_boss.py): floor
## y 0, ceiling, VentRoof (x 16..64, y -224..-136), plugged doors,
## ArenaGateLeft closed (x 40..56) and ExitGate closed (x 448..464), so the
## right wall is at x 448; catwalks at y -40 / -80 and the vent lip at -92.
## The arena test loads the fixture itself. Positions are room space (the
## world sits at the origin).

const PLAYER_SCENE := preload("res://player/Player.tscn")
const DRONE := "res://bosses/CollectorDrone.tscn"
const ARENA_ROOM := "res://tests/fixtures/boss_collector_arena.tscn"
const REWARD_ID := "test_collector_reward"
const PRESS := &"collector_drop_press"
const PRESS_P2 := &"collector_drop_press_p2"
const WAVE := &"collector_press_wave"
const VOLLEY := &"collector_tag_volley"
const DIVE := &"collector_claw_dive"
const SWEEP := &"collector_hook_sweep"
const FRAME := 1.0 / 60.0
const BEHAVIOR := preload("res://bosses/CollectorDroneBehavior.gd")

var world: Node2D
var player: Player
var input: ScriptedInputSource
var root: Node2D


func before_each() -> void:
	Game.new_game()
	world = Node2D.new()
	add_child(world)
	_block(Vector2(0, -240), Vector2(480, 16))  # Ceiling
	_block(Vector2(0, -224), Vector2(16, 224))  # WallLeftUpper + DoorLeftPlug
	_block(Vector2(16, -224), Vector2(48, 88))  # VentRoof
	_block(Vector2(448, -224), Vector2(32, 128))  # WallRightUpper
	_block(Vector2(464, -96), Vector2(16, 96))  # DoorRightPlug
	_block(Vector2(40, -92), Vector2(16, 92))  # ArenaGateLeft (closed in the fight)
	_block(Vector2(448, -96), Vector2(16, 96))  # ExitGate (closed until the kill)
	_block(Vector2(0, 0), Vector2(480, 96))  # Floor
	for c: Vector3 in [Vector3(96, -40, 64), Vector3(200, -80, 104), Vector3(344, -40, 64), Vector3(16, -92, 56)]:
		var b := _block(Vector2(c.x, c.y), Vector2(c.z, 8))
		b.one_way = true
	player = PLAYER_SCENE.instantiate()
	player.abilities = PlayerAbilities.new()
	input = ScriptedInputSource.new()
	player.input_source = input
	world.add_child(player)
	player.add_to_group(&"player")
	player.respawn(Vector2(150, -2))
	player.combat.config = player.combat.config.duplicate()
	await physics_frames(3)


func after_each() -> void:
	if is_instance_valid(world):
		world.queue_free()
	if is_instance_valid(root):
		SceneRouter.current_room = null
		SceneRouter.world_root = null
		root.queue_free()
	Game.new_game()
	await physics_frames(2)


func _block(pos: Vector2, size: Vector2) -> GrayboxBlock:
	var b := GrayboxBlock.new()
	b.size = size
	b.position = pos
	world.add_child(b)
	return b


func _drone(pos: Vector2, ai := false) -> Enemy:
	var e: Enemy = load(DRONE).instantiate()
	e.ai_enabled = ai
	e.position = pos
	world.add_child(e)
	await physics_frames(2)
	if ai:
		e.set_ai(Enemy.AI.ENGAGE)
	return e


func _reset_player(x: float, face: int = 1) -> void:
	input.move_x = 0
	input.up_held = false
	input.release_jump()
	player.respawn(Vector2(x, -2), face)
	await physics_frames(3)


func _clear_projectiles() -> void:
	for n in world.get_children():
		if n is Projectile:
			n.queue_free()


func _wait_ai(e: Enemy, state: int, max_frames: int) -> bool:
	for i in max_frames:
		if e.ai == state:
			return true
		await physics_frames(1)
	return e.ai == state


func _opener_ids(e: Enemy) -> Array[StringName]:
	var ids: Array[StringName] = []
	for a in e.data.attacks:
		ids.append(a.id)
	return ids


## Result of one attack against Rook: contact (the drone resolved its hit on
## him), damage taken and whether it was a perfect evade.
class Outcome:
	var contact := false
	var damaged := false
	var perfect := false


func _watch_attack(e: Enemy, until_state: int, max_frames: int) -> Outcome:
	var out := Outcome.new()
	var perfects: Array = []
	var cb := func(_a: Node2D) -> void: perfects.append(1)
	EventBus.perfect_dodge.connect(cb)
	var hp := player.combat.health
	var box := player.get_node("Hurtbox").get_instance_id()
	for i in max_frames:
		await physics_frames(1)
		if e._attack_hit_ids.has(box):
			out.contact = true
		if e.ai == until_state:
			break
	EventBus.perfect_dodge.disconnect(cb)
	out.damaged = player.combat.health < hp
	out.perfect = not perfects.is_empty()
	return out


# --- 1. Data ----------------------------------------------------------------------

func test_collector_data_valid_and_first_boss_telegraphs() -> void:
	var data: EnemyData = load("res://data/enemies/collector_drone.tres")
	check(data.validate().is_empty(), "collector data invalid: %s" % [data.validate()])
	check(data.boss and data.min_telegraph == 0.5 and data.poise_locked_while_down and is_equal_approx(data.ranged_poise_scale, 0.3), "boss flags")
	check(data.max_health == 400.0 and data.max_poise == 90.0 and data.flying, "durability")
	check((load("res://data/enemies/warden_krail.tres") as EnemyData).boss, "Krail is a boss too")
	var openers := 0
	for a in data.attacks:
		openers += 1
		check(a.startup * 0.85 >= 0.5, "%s: phase-2 opener tell %.3f < 0.5" % [a.id, a.startup * 0.85])
		check(a.damage == 1.0, "%s: damage should be 1 pip" % a.id)
		var f := a.follow_up
		while f:
			check(f.startup * 0.85 >= 0.3, "%s: phase-2 follow-up tell %.3f < 0.3" % [f.id, f.startup * 0.85])
			check(f.damage == 1.0, "%s: damage should be 1 pip" % f.id)
			f = f.follow_up
	check(openers == 6, "six openers (four cards, two phase-2 variants)")


# --- 2. Telegraphs in play ------------------------------------------------------------

func test_collector_every_attack_telegraphs_in_play() -> void:
	player.invulnerable = true
	var e := await _drone(Vector2(252, -144), true)
	var openers := _opener_ids(e)
	var windups: Array = []  # [id, frames]
	var cur: StringName = &""
	var frames := 0
	for i in 60 * 45:
		await physics_frames(1)
		player.invulnerable = true
		if i == 60 * 28:
			e.health = e.data.max_health * 0.45
		var in_windup := e.ai == Enemy.AI.WINDUP and e.current_attack != null
		var id: StringName = e.current_attack.id if in_windup else &""
		if id != cur:
			if cur != &"":
				windups.append([cur, frames])
			cur = id
			frames = 0
		if in_windup:
			frames += 1
	var families := {}
	var saw_follow_up := false
	for w in windups:
		var id: StringName = w[0]
		var secs := float(w[1]) * FRAME
		families[BEHAVIOR.family_of(id)] = true
		if openers.has(id):
			check(secs >= 0.5 - FRAME * 0.5, "%s opener tell %.3f s < 0.5" % [id, secs])
		else:
			saw_follow_up = true
			check(secs >= 0.3 - FRAME * 0.5, "%s follow-up tell %.3f s < 0.3" % [id, secs])
	check(families.size() == 4, "all four families should play (saw %s)" % [families.keys()])
	check(saw_follow_up, "phase 2 should play the press wave within 45 s")
	var b = e.behavior
	var first: Array = []
	for i in mini(4, b.played.size()):
		first.append(String(b.played[i]))
	check(first == ["collector_drop_press", "collector_tag_volley", "collector_claw_dive", "collector_hook_sweep"],
		"first deck should teach press, volley, dive, sweep (got %s)" % [first])


# --- 3. No repeats, always reachable ---------------------------------------------------

func test_collector_never_repeats_and_stays_reachable() -> void:
	player.invulnerable = true
	var e := await _drone(Vector2(252, -144), true)
	var b = e.behavior
	var openers := _opener_ids(e)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var spots: Array[Vector2] = [Vector2(100, -2), Vector2(180, -2), Vector2(330, -2), Vector2(420, -2),
		Vector2(128, -42), Vector2(376, -42), Vector2(252, -82), Vector2(40, -94)]
	var attacks: Array = []  # [family, longest low run (frames)]
	var low_run := 0
	var best := 0
	var cur: StringName = &""
	var illegal: Array[String] = []
	for i in 60 * 70:
		if i % 180 == 0:
			player.teleport(spots[rng.randi_range(0, spots.size() - 1)])
		await physics_frames(1)
		player.invulnerable = true
		if e.ai == Enemy.AI.WINDUP and e.current_attack and openers.has(e.current_attack.id) and e.current_attack.id != cur:
			if cur != &"":
				attacks.append([BEHAVIOR.family_of(cur), best])
			cur = e.current_attack.id
			best = 0
			low_run = 0
			var f := BEHAVIOR.family_of(cur)
			if (f == &"dive" or f == &"sweep") and player.global_position.y < -2.0:
				illegal.append("%s with Rook at %s" % [cur, player.global_position.round()])
		if cur != &"":
			low_run = low_run + 1 if b.room_pos().y >= -76.0 - 0.001 else 0
			best = maxi(best, low_run)
	check(attacks.size() >= 8, "too few cards in 70 s: %d" % attacks.size())
	var floor_cards := attacks.filter(func(a: Array) -> bool: return a[0] == &"dive" or a[0] == &"sweep")
	check(not floor_cards.is_empty(), "dive/sweep should still play while Rook is on the floor")
	print("  cards: %s" % [attacks.map(func(a: Array) -> String: return "%s/%.2fs" % [a[0], a[1] * FRAME])])
	check(illegal.is_empty(), "dive/sweep started off the main floor: %s" % [illegal])
	for i in range(1, attacks.size()):
		check(attacks[i][0] != attacks[i - 1][0], "family %s played twice in a row (card %d)" % [attacks[i][0], i])
	for i in attacks.size():
		check(attacks[i][1] >= 36, "card %d (%s): drone low (feet >= -76) only %.2f s" % [i, attacks[i][0], attacks[i][1] * FRAME])


# --- 4. Dive landing -----------------------------------------------------------------

func test_collector_dive_lands_deterministically() -> void:
	player.invulnerable = true
	# The last start is the late-touchdown case: the drone is knocked 6 px
	# above the lock point on the final WINDUP frame, so the lunge ends just
	# above the floor, and a hit cancels its fall as RECOVER starts. Without
	# the settle rule in RECOVER the flyer brake would leave it hovering.
	for start: Vector2 in [Vector2(300, -136), Vector2(288, -152), Vector2(288, -136), Vector2(300, -152), Vector2(294, -144)]:
		var late := start == Vector2(294, -144)
		await _reset_player(150)
		player.invulnerable = true
		var e := await _drone(start)
		var b = e.behavior
		b.force_card(DIVE)
		check(b.lock_point() == Vector2(294, -144), "dive lock point %s should be (294, -144)" % b.lock_point())
		if late:
			var startup: float = b.scaled_startup(e.current_attack)
			while e.ai == Enemy.AI.WINDUP and e.ai_time + FRAME * 1.5 < startup:
				await physics_frames(1)
			# The lock steps 1 px back toward the lock point this frame.
			e.global_position.y -= 7.0
		var landing := INF
		var recover_frame := -1
		var settled_frame := -1
		for i in 200:
			await physics_frames(1)
			if (e.ai == Enemy.AI.ACTIVE or e.ai == Enemy.AI.RECOVER) and landing == INF and e.is_on_floor():
				landing = e.global_position.x
			if e.ai == Enemy.AI.RECOVER and recover_frame < 0:
				recover_frame = i
				if late:
					check(not e.is_on_floor(), "late case: still above the floor as RECOVER starts")
					e.velocity = Vector2.ZERO
			if recover_frame >= 0 and settled_frame < 0 and e.global_position.y >= -1.0:
				settled_frame = i
			if recover_frame >= 0 and i > recover_frame + 4:
				break
		if late:
			check(e.ai != Enemy.AI.RECOVER or e.global_position.y >= -1.0, "a late touchdown should settle in RECOVER (y %.2f)" % e.global_position.y)
		check(recover_frame >= 0, "dive never recovered from %s" % start)
		check(settled_frame >= 0 and settled_frame - recover_frame <= 2, "dive from %s not on the floor within 2 frames of RECOVER (%d)" % [start, settled_frame - recover_frame])
		# A late touchdown carries the 45 degree run a few px on; it still lands
		# inside the 12 px floor X.
		check_near(landing, b.dive_landing_x(), 6.0 if late else 1.0, "dive from %s lands on the locked X" % start)
		e.queue_free()
		await physics_frames(1)


# --- 5. Dive dodge windows -------------------------------------------------------------

func _dive_trial(dodge_at: float, dir: int) -> Outcome:
	await _reset_player(150)
	var e := await _drone(Vector2(294, -144))
	e.behavior.force_card(DIVE)
	await _wait_ai(e, Enemy.AI.ACTIVE, 120)
	var out: Outcome
	if dodge_at >= 0.0:
		var wait := roundi(dodge_at * 60.0)
		var early := Outcome.new()
		if wait > 0:
			early = await _watch_attack(e, -1, wait)
		input.move_x = dir
		input.press_dodge()
		await physics_frames(1)
		input.move_x = 0
		out = await _watch_attack(e, Enemy.AI.RECOVER, 90)
		out.contact = out.contact or early.contact
		out.damaged = out.damaged or early.damaged
	else:
		out = await _watch_attack(e, Enemy.AI.RECOVER, 90)
	e.queue_free()
	await physics_frames(1)
	return out


func test_collector_dive_dodge_windows() -> void:
	var stand := await _dive_trial(-1.0, 0)
	check(stand.damaged, "standing on the X should be hit")
	for t: float in [0.0, 0.2, 0.33, 0.40]:
		var o := await _dive_trial(t, 1)
		check(not o.damaged, "dodge toward at %.2f s into ACTIVE should take no damage" % t)
		if is_equal_approx(t, 0.33):
			check(o.perfect, "dodge toward at 0.33 s should be a PERFECT_EVADE")
	var late := await _dive_trial(0.46, 1)
	check(late.damaged, "dodge toward at 0.46 s is too late and should be hit")
	for t: float in [0.0, 0.35]:
		var o := await _dive_trial(t, -1)
		check(not o.damaged, "dodge away at %.2f s should take no damage" % t)


# --- 6. Sweep answers ------------------------------------------------------------------

## Hook front edge minus Rook's near edge (the hook travels left).
func _sweep_gap(e: Enemy) -> float:
	return (e.global_position.x - 24.0) - (player.global_position.x + 6.0)


func _sweep_trial(player_at: Vector2, answer: String, gap_trigger: float) -> Outcome:
	await _reset_player(player_at.x)
	if player_at.y < -2.0:
		player.teleport(player_at)
		await physics_frames(3)
	var e := await _drone(Vector2(424, -60))
	e.behavior.force_card(SWEEP)
	await _wait_ai(e, Enemy.AI.ACTIVE, 120)
	var hp := player.combat.health
	var out := Outcome.new()
	var perfects: Array = []
	var cb := func(_a: Node2D) -> void: perfects.append(1)
	EventBus.perfect_dodge.connect(cb)
	var box := player.get_node("Hurtbox").get_instance_id()
	var done := answer == "stand"
	var hold := 0
	for i in 150:
		if not done and _sweep_gap(e) <= gap_trigger:
			done = true
			match answer:
				"jump":
					input.press_jump()
					hold = 18
				"jump_toward":
					input.press_jump()
					input.move_x = 1
					hold = 18
				"dodge":
					input.move_x = 1
					input.press_dodge()
					hold = 1
		await physics_frames(1)
		if hold > 0:
			hold -= 1
			if hold == 0:
				input.release_jump()
				input.move_x = 0
		if e._attack_hit_ids.has(box):
			out.contact = true
		if e.ai == Enemy.AI.RECOVER:
			break
	EventBus.perfect_dodge.disconnect(cb)
	out.damaged = player.combat.health < hp
	out.perfect = not perfects.is_empty()
	e.queue_free()
	await physics_frames(1)
	return out


func test_collector_sweep_answers() -> void:
	var grounded := await _sweep_trial(Vector2(200, -2), "stand", 0.0)
	check(grounded.damaged, "a grounded Rook should be hooked")
	var jump := await _sweep_trial(Vector2(200, -2), "jump", 40.0)
	check(not jump.damaged, "a jump in place at 40 px should clear the hook")
	var toward := await _sweep_trial(Vector2(200, -2), "jump_toward", 100.0)
	check(not toward.damaged, "a jump toward the hook at 100 px should clear it")
	var dodge := await _sweep_trial(Vector2(200, -2), "dodge", 40.0)
	check(dodge.contact and not dodge.damaged, "a dodge covering first contact should evade the whole pass")
	var early := await _sweep_trial(Vector2(200, -2), "dodge", 40.0 + 0.3 * 220.0 + 0.3 * 270.0)
	check(early.damaged, "a dodge 0.3 s early should be hit")
	var catwalk := await _sweep_trial(Vector2(128, -42), "stand", 0.0)
	check(not catwalk.contact and not catwalk.damaged, "the side catwalk is above the hook")


# --- 7. Press and the phase-2 wave --------------------------------------------------------

func test_collector_press_sidestep_and_p2_wave() -> void:
	# Sidestep 36 px during the tell: clear.
	await _reset_player(200)
	var e := await _drone(Vector2(200, -144))
	check(not e.behavior.rotors_cut(), "rotors run while stalking")
	e.behavior.force_card(PRESS)
	input.move_x = 1
	var hp := player.combat.health
	var cut_in_windup := true
	for i in 120:
		await physics_frames(1)
		if e.ai == Enemy.AI.WINDUP:
			cut_in_windup = cut_in_windup and e.behavior.rotors_cut()
		if player.global_position.x >= 236.0:
			input.move_x = 0
		if e.ai == Enemy.AI.RECOVER:
			break
	check(player.combat.health == hp, "a 36 px sidestep should clear the press")
	check(cut_in_windup, "the rotors cut for the whole Press WINDUP (the tell)")
	check(not e.behavior.rotors_cut(), "the rotors restart in RECOVER")
	e.queue_free()
	# Standing still: hit.
	await _reset_player(200)
	e = await _drone(Vector2(200, -144))
	e.behavior.force_card(PRESS)
	var stand := await _watch_attack(e, Enemy.AI.RECOVER, 150)
	check(stand.damaged, "standing under the press should be hit")
	e.queue_free()
	# Phase 2 from cruise_y - 6: the wave leaves at floor height; a jump clears it.
	var jump := await _wave_trial(300.0, true)
	check(jump[0], "phase 2 press should spawn waves")
	check(jump[1], "the wave should spawn at y -6 +- 1 (got %s)" % [jump[3]])
	check(not jump[2], "a jump should clear the wave")
	var stand_aside := await _wave_trial(240.0, false)
	check(stand_aside[2], "standing 40 px aside should be hit by the wave")


## Returns [spawned, at_floor, damaged, spawn_ys].
func _wave_trial(px: float, jump: bool) -> Array:
	await _reset_player(px)
	_clear_projectiles()
	var e := await _drone(Vector2(200, -150))
	e.health = e.data.max_health * 0.45
	await physics_frames(2)
	check(e.behavior.phase == 2, "phase 2 should trigger at 45% health")
	e.behavior.force_card(PRESS_P2)
	var hp := player.combat.health
	var ys: Array = []
	var jumped := false
	var hold := 0
	for i in 240:
		await physics_frames(1)
		for n in world.get_children():
			var p := n as Projectile
			if p and p.attack.id == WAVE and not ys.has(p.get_instance_id()):
				ys.append(p.get_instance_id())
				ys.append(p.global_position.y)
			if jump and p and p.attack.id == WAVE and not jumped and p.velocity.x > 0.0 and p.global_position.x >= px - 6.0 - 26.0:
				input.press_jump()
				jumped = true
				hold = 18
		if hold > 0:
			hold -= 1
			if hold == 0:
				input.release_jump()
		if e.ai == Enemy.AI.RECOVER and e.ai_time > 0.8:
			break
	var at_floor := ys.size() >= 4
	var spawn_ys: Array = []
	for i in range(1, ys.size(), 2):
		spawn_ys.append(ys[i])
		at_floor = at_floor and absf(float(ys[i]) + 6.0) <= 1.0
	e.queue_free()
	await physics_frames(1)
	return [ys.size() >= 2, at_floor, player.combat.health < hp, spawn_ys]


# --- 8. Poise -------------------------------------------------------------------------------

func _hit(e: Enemy, attack: AttackData, ranged := false) -> int:
	var tags: Array[StringName] = []
	if ranged:
		tags.append(&"ranged")
	return e.receive_hit(HitInfo.create(player, attack, Vector2.ZERO, Vector2.RIGHT, tags))


func test_collector_poise_break_grounds_once() -> void:
	var breaker := AttackData.new()
	breaker.id = &"test_poise_break"
	breaker.damage = 1.0
	breaker.poise_damage = 90.0
	var e := await _drone(Vector2(252, -144))
	_hit(e, breaker)
	check(e.ai == Enemy.AI.LAUNCHED, "90 poise should knock the flyer out of the air")
	var landed := -1
	var stagger := 0
	for i in 240:
		await physics_frames(1)
		if landed < 0 and e.is_on_floor():
			landed = i
		if e.ai == Enemy.AI.STAGGER:
			stagger += 1
		elif stagger > 0:
			break
	check(landed >= 0 and landed <= 48, "should hit the floor within 0.8 s (frame %d)" % landed)
	check(stagger * FRAME >= 1.7, "grounded stagger %.2f s should be >= 1.7" % (stagger * FRAME))
	e.queue_free()
	# Five seconds of blade combos plus pistol fire: exactly one knockdown.
	var blade: WeaponData = load("res://data/weapons/pulse_blade.tres")
	var pistol: WeaponData = load("res://data/weapons/service_pistol.tres")
	e = await _drone(Vector2(252, -144))
	e.health = 1000000.0
	var knockdowns := 0
	var prev := e.ai
	for i in 300:
		if i % 12 == 0:
			_hit(e, blade.light_chain[(i / 12) % blade.light_chain.size()])
		if i % 8 == 0:
			_hit(e, pistol.shot, true)
		await physics_frames(1)
		if e.ai == Enemy.AI.LAUNCHED and prev != Enemy.AI.LAUNCHED:
			knockdowns += 1
		prev = e.ai
	check(knockdowns == 1, "5 s of continuous blade + pistol should knock it down exactly once (%d)" % knockdowns)
	e.queue_free()
	# Pistol poise is scaled by 0.3: 30 hits = 27 poise.
	e = await _drone(Vector2(252, -144))
	for i in 30:
		_hit(e, pistol.shot, true)
	check_near(e.data.max_poise - e.poise, 27.0, 0.01, "30 pistol hits should deal 27 poise")
	check(e.ai != Enemy.AI.LAUNCHED and e.ai != Enemy.AI.STAGGER, "pistol chip alone should not stagger")


# --- 9. Blade punishes ---------------------------------------------------------------------

func _blade_lands(e: Enemy, at: Vector2, face: int, jump: bool) -> bool:
	player.teleport(at)
	player.facing = face
	await physics_frames(2)
	var hp := e.health
	if jump:
		input.press_jump()
		await physics_frames(12)
	input.press_light()
	await physics_frames(14)
	input.release_jump()
	await physics_frames(20)
	return e.health < hp


func test_collector_punishable_by_blade() -> void:
	player.invulnerable = true
	# Dive recovery (grounded).
	var e := await _drone(Vector2(294, -144))
	e.behavior.force_card(DIVE)
	await _wait_ai(e, Enemy.AI.RECOVER, 150)
	await physics_frames(18)
	check(await _blade_lands(e, Vector2(e.global_position.x + 22.0, -2), -1, false), "floor light should land in dive recovery")
	e.queue_free()
	# Press recovery.
	await _reset_player(120)
	player.invulnerable = true
	e = await _drone(Vector2(200, -144))
	e.behavior.force_card(PRESS)
	await _wait_ai(e, Enemy.AI.RECOVER, 150)
	check(await _blade_lands(e, Vector2(e.global_position.x - 22.0, -2), 1, false), "floor light should land in press recovery")
	e.queue_free()
	# Volley vent sag: a floor jump + air light.
	await _reset_player(120)
	player.invulnerable = true
	e = await _drone(Vector2(300, -144))
	e.behavior.force_card(VOLLEY)
	await _wait_ai(e, Enemy.AI.RECOVER, 150)
	await physics_frames(16)
	check(e.behavior.room_pos().y >= -76.0 - 0.001, "volley recovery should sag to -76 (at %.1f)" % e.behavior.room_pos().y)
	check(await _blade_lands(e, Vector2(e.global_position.x - 8.0, -2), 1, true), "floor jump air-light should land on the vent sag")
	e.queue_free()
	_clear_projectiles()
	# Sweep low hang at the far edge.
	await _reset_player(300)
	player.invulnerable = true
	e = await _drone(Vector2(424, -60))
	e.behavior.force_card(SWEEP)
	await _wait_ai(e, Enemy.AI.RECOVER, 200)
	await physics_frames(6)
	check(await _blade_lands(e, Vector2(e.global_position.x + 8.0, -2), -1, true), "floor jump air-light should land on the sweep's low hang")
	e.queue_free()
	# Cruise lane from the centre catwalk.
	await _reset_player(244)
	player.invulnerable = true
	e = await _drone(Vector2(252, -144))
	player.teleport(Vector2(240, -82))
	await physics_frames(4)
	var hp := e.health
	input.press_jump()
	await physics_frames(14)
	input.press_light()
	await physics_frames(16)
	input.release_jump()
	await physics_frames(30)
	check(e.health < hp, "a jump-attack from the centre catwalk should reach the cruise lane")
	e.queue_free()
	# Optional pistol: straight up during the Press setup / tell.
	await _reset_player(150)
	player.invulnerable = true
	e = await _drone(Vector2(252, -144), true)
	hp = e.health
	var fired := false
	for i in 300:
		await physics_frames(1)
		var b = e.behavior
		var pressing: bool = b.card == PRESS or (e.current_attack != null and e.current_attack.id == PRESS and e.ai == Enemy.AI.WINDUP)
		var dx := e.global_position.x - player.global_position.x
		if pressing and absf(dx) <= 24.0:
			# Face the drone (the muzzle sits 9 px forward), then fire straight up.
			player.facing = int(signf(dx)) if absf(dx) > 1.0 else player.facing
			input.up_held = true
			input.press_ranged()
			fired = true
		if fired and e.health < hp:
			break
	input.up_held = false
	check(fired and e.health < hp, "a straight-up pistol shot should hit the drone during the press setup")


# --- 10. Volley aim -------------------------------------------------------------------------

func test_collector_volley_fires_along_telegraph() -> void:
	player.invulnerable = true
	_clear_projectiles()
	var e := await _drone(Vector2(340, -144))
	var b = e.behavior
	b.force_card(VOLLEY)
	var early_aim := e.attack_aim
	var freeze: float = b.scaled_startup(e.current_attack) - b.aim_freeze
	# Before the freeze the line tracks Rook.
	input.move_x = -1
	await physics_frames(12)
	input.move_x = 0
	check(e.attack_aim.angle_to(early_aim) != 0.0, "the telegraph line should track Rook before the freeze")
	# Rook is already at full run when the line freezes.
	while e.ai == Enemy.AI.WINDUP and e.ai_time < freeze - 0.25:
		await physics_frames(1)
	input.move_x = 1
	while e.ai == Enemy.AI.WINDUP and e.ai_time < freeze + FRAME:
		await physics_frames(1)
	var frozen := e.attack_aim
	var start_x := player.global_position.x
	while e.ai == Enemy.AI.WINDUP:
		await physics_frames(1)
		if player.global_position.x - start_x >= 40.0:
			input.move_x = 0
	input.move_x = 0
	check(player.global_position.x - start_x >= 36.0, "Rook should have moved ~40 px after the freeze (%.0f)" % (player.global_position.x - start_x))
	await physics_frames(1)
	var angles: Array[float] = []
	for n in world.get_children():
		var p := n as Projectile
		if p and p.attack.id == VOLLEY:
			angles.append(p.velocity.angle())
	angles.sort()
	check(angles.size() == 3, "volley should fire 3 pellets (%d)" % angles.size())
	if angles.size() == 3:
		check(absf(rad_to_deg(angle_difference(angles[1], frozen.angle()))) <= 1.0, "central pellet should fly along the frozen line")
		var live := (player.global_position + Vector2(0, -16) - (e.global_position + Vector2(0, -12))).normalized()
		check(absf(rad_to_deg(angle_difference(angles[1], live.angle()))) > 1.0, "the shot must not re-aim at Rook's new position")


# --- 11. Phase two --------------------------------------------------------------------------------

func test_collector_phase_two() -> void:
	player.invulnerable = true
	var e := await _drone(Vector2(252, -144), true)
	var b = e.behavior
	var phases: Array = []
	var cb := func(_boss: Node2D, p: int) -> void: phases.append(p)
	EventBus.boss_phase_changed.connect(cb)
	# Trigger while stalking so the whole pause runs in ENGAGE.
	for i in 300:
		await physics_frames(1)
		if e.ai == Enemy.AI.ENGAGE and b.played.size() >= 1 and e.attack_cooldown > 0.0:
			break
	e.telegraph_scale = 0.9
	var played_before: int = b.played.size()
	e.health = e.data.max_health * 0.49
	await physics_frames(1)
	check(b.phase == 2, "phase 2 at 49% health")
	check_near(e.telegraph_scale, 0.9 * 0.85, 0.0001, "telegraph_scale is multiplied by 0.85")
	check(phases == [2], "boss_phase_changed(2) emitted once (%s)" % [phases])
	check(world.find_children("*", "ScrapPickup", true, false).is_empty(), "no scrap burst at the phase change")
	var engage_paused := 0
	var attacked_in_pause := false
	for i in 600:
		if not b.paused():
			break
		await physics_frames(1)
		if e.ai == Enemy.AI.ENGAGE:
			engage_paused += 1
		if e.ai == Enemy.AI.WINDUP:
			attacked_in_pause = true
	check(not attacked_in_pause, "no attack during the roar")
	check(engage_paused >= 89, "the roar lasts 1.5 s of ENGAGE (%d frames)" % engage_paused)
	for i in 60 * 30:
		await physics_frames(1)
		if b.played.size() >= played_before + 4:
			break
	var after: Array = []
	for i in range(played_before, b.played.size()):
		after.append(String(b.played[i]))
	check(after.has("collector_drop_press_p2") and after.has("collector_tag_volley_p2"), "the phase-2 deck draws press_p2 and volley_p2 (%s)" % [after])
	check(not after.has("collector_drop_press") and not after.has("collector_tag_volley"), "no phase-1 variants after the switch (%s)" % [after])
	check(world.find_children("*", "ScrapPickup", true, false).is_empty(), "no scrap until the drone dies")
	EventBus.boss_phase_changed.disconnect(cb)


# --- 12. BossBot ------------------------------------------------------------------------------------

func _bot_fight(profile: String) -> Dictionary:
	await _reset_player(120)
	for n in world.get_children():
		if n is Enemy or n is Projectile or n is ScrapPickup:
			n.queue_free()
	await physics_frames(1)
	var e := await _drone(Vector2(252, -144), true)
	var bot := BossBot.new(get_tree(), player, e, profile)
	var r: Dictionary = await bot.run(200.0)
	print("  BossBot %s: won %s in %.1f s, health %d" % [profile, r["won"], r["seconds"], r["health"]])
	if OS.get_environment("BOSSBOT_LOG") != "":
		print("\n".join(bot.log))
	return r


func test_scripted_fight_can_win() -> void:
	var blade := await _bot_fight("blade")
	check(blade["won"] and int(blade["health"]) > 0, "blade bot should win (%s)" % [blade])
	check(float(blade["seconds"]) >= 25.0 and float(blade["seconds"]) <= 150.0, "blade fight length %.1f s outside 25-150" % blade["seconds"])
	var pistol := await _bot_fight("pistol")
	check(pistol["won"], "pistol-only bot should win (%s)" % [pistol])
	check(float(pistol["seconds"]) >= 40.0, "pistol-only must not win in under 40 s (%.1f)" % pistol["seconds"])


# --- 13. Arena ------------------------------------------------------------------------------------------

func _enter_arena() -> Room:
	if not is_instance_valid(root):
		root = Node2D.new()
		add_child(root)
		SceneRouter.register_world_root(root)
	SceneRouter.goto_room(ARENA_ROOM, &"start")
	await physics_frames(10)
	return SceneRouter.current_room as Room


## Walks in from the spawn and returns seconds until the boss activates.
func _walk_in(room: Room, arena: BossArena) -> float:
	var p := room.player
	p.invulnerable = true
	var walk := ScriptedInputSource.new()
	p.input_source = walk
	walk.move_x = 1
	var frames := 0
	var started := -1
	for i in 60 * 5:
		await physics_frames(1)
		p.invulnerable = true
		if p.global_position.x >= 90.0:
			walk.move_x = 0
		if arena.started and started < 0:
			started = i
		if started >= 0 and arena.boss.ai_enabled:
			frames = i - started
			break
	return frames * FRAME


func test_arena_rewards_and_remembers() -> void:
	world.queue_free()
	await physics_frames(1)
	var room := await _enter_arena()
	check(room != null, "fixture arena should load")
	var arena := room.find_children("*", "BossArena", true, false)[0] as BossArena
	var gate := room.find_child("ArenaGateLeft", true, false) as Gate
	check(not gate.closed, "gate open before the fight")
	var intro := await _walk_in(room, arena)
	check(gate.closed, "gate should close on entry")
	check(intro >= 2.5 and intro <= 2.7, "first intro should last 2.6 s (%.2f)" % intro)
	# Retry: the intro is short once seen.
	room = await _enter_arena()
	arena = room.find_children("*", "BossArena", true, false)[0] as BossArena
	gate = room.find_child("ArenaGateLeft", true, false) as Gate
	intro = await _walk_in(room, arena)
	check(intro >= 0.5 and intro <= 0.7, "retry intro should last 0.6 s (%.2f)" % intro)
	var boss := arena.boss
	var kill := HitInfo.create(room.player, boss.data.attacks[0].duplicate(), Vector2.ZERO, Vector2.RIGHT)
	kill.attack.damage = 99999.0
	boss.receive_hit(kill)
	check(Game.has_flag("collector_drone_defeated"), "defeat flag not set")
	await physics_frames(int(boss.data.death_time * 60.0) + 4)
	check(gate.closed, "gate stays closed until death_time + 0.2")
	await physics_frames(16)
	check(not gate.closed, "gate should open after death_time + 0.2")
	var rewards := _rewards(room)
	check(rewards.size() == 1, "one reward should spawn (%d)" % rewards.size())
	if rewards.size() == 1:
		check(rewards[0].position == Vector2(252, 0), "reward on the floor at (252, 0), got %s" % rewards[0].position)
		# Leave before pickup: the reward waits on the next visit.
		rewards[0].free()
	arena._ready()
	await physics_frames(2)
	check(arena.boss == null or not is_instance_valid(arena.boss), "defeated boss should be gone")
	check(not gate.closed, "gates open once defeated")
	rewards = _rewards(room)
	check(rewards.size() == 1 and rewards[0].position == Vector2(252, 0), "a missed reward should spawn again (%d)" % rewards.size())
	# Collected: never again.
	Game.mark_collected(REWARD_ID)
	for r in rewards:
		r.free()
	arena._ready()
	await physics_frames(3)
	check(_rewards(room).is_empty(), "a collected reward must not come back")


func _rewards(room: Node) -> Array:
	var out: Array = []
	for n in room.find_children("*", "Collectible", true, false):
		if (n as Collectible).persist_id == REWARD_ID and not n.is_queued_for_deletion():
			out.append(n)
	return out


func test_boss_arena_reward_position_fallback() -> void:
	var e := await _drone(Vector2(360, -120))
	var arena := BossArena.new()
	arena.boss_id = "collector_drone"
	arena.size = Vector2(200, 100)
	arena.position = Vector2(60, -100)
	arena.reward_scene = load("res://tests/fixtures/boss_reward_collectible.tscn")
	world.add_child(arena)
	arena.boss_path = arena.get_path_to(e)
	arena._ready()
	var died_at := e.global_position
	var kill := HitInfo.create(player, e.data.attacks[0].duplicate(), Vector2.ZERO, Vector2.RIGHT)
	kill.attack.damage = 99999.0
	e.receive_hit(kill)
	await physics_frames(int((e.data.death_time + 0.4) * 60.0))
	var rewards := _rewards(world)
	check(rewards.size() == 1, "reward should spawn (%d)" % rewards.size())
	if rewards.size() == 1:
		var at: Vector2 = (rewards[0] as Node2D).global_position
		check(at.distance_to(died_at) <= 1.0, "INF reward_position uses the cached death position %s, got %s" % [died_at, at])
		check(at.distance_to(arena.global_position + arena.size * 0.5) > 10.0, "not the arena centre")


## The arena fixture is generated: tools/roomgen/fixtures_boss.py --check.
func test_boss_fixture_matches_roomgen() -> void:
	var probe: Array = []
	if OS.execute("sh", ["-c", "command -v python3"], probe) != 0:
		push_warning("python3 not found: fixtures_boss.py not run here (it is part of the gate)")
		return
	var out: Array = []
	var code := OS.execute("sh", ["-c", "cd '%s' && python3 -B tools/roomgen/fixtures_boss.py --check" % ProjectSettings.globalize_path("res://")], out, true)
	check(code == 0, "fixtures_boss.py --check reports drift: %s" % [out])
	var inst := (load(ARENA_ROOM) as PackedScene).instantiate()
	check(inst is Room and (inst as Room).bounds == Rect2(0, -240, 480, 270), "fixture should be the one-screen CollectorBay arena")
	var arenas := inst.find_children("*", "BossArena", true, false)
	check(arenas.size() == 1, "one BossArena")
	if arenas.size() == 1:
		var a := arenas[0] as BossArena
		check(a.position == Vector2(72, -224) and a.size == Vector2(376, 224) and a.intro_time == 2.6, "arena rect and intro match CollectorBay")
		check(a.reward_position == Vector2(252, 0) and a.boss_id == "collector_drone", "reward on the floor under the hatch")
	inst.free()
