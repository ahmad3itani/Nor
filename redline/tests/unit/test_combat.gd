extends RedlineTestCase
## M2 combat behaviour driven through the real Player/Enemy scenes.

const PLAYER_SCENE := preload("res://player/Player.tscn")
const NEEDLE := preload("res://enemies/variants/Needle.tscn")
const SHIELD := preload("res://enemies/variants/Shield.tscn")
const DRONE := preload("res://enemies/variants/ScoutDrone.tscn")

var world: Node2D
var player: Player
var input: ScriptedInputSource
var events: Array = []


func before_each() -> void:
	world = Node2D.new()
	add_child(world)
	events.clear()
	var floor_block := GrayboxBlock.new()
	floor_block.size = Vector2(2000, 64)
	floor_block.position = Vector2(-1000, 0)
	world.add_child(floor_block)
	player = PLAYER_SCENE.instantiate()
	player.abilities = PlayerAbilities.new()
	input = ScriptedInputSource.new()
	player.input_source = input
	world.add_child(player)
	player.add_to_group(&"player")
	player.respawn(Vector2(0, -2))
	EventBus.enemy_killed.connect(_on_killed)
	EventBus.perfect_dodge.connect(_on_perfect)
	EventBus.player_died.connect(_on_died)
	await physics_frames(3)


func after_each() -> void:
	EventBus.enemy_killed.disconnect(_on_killed)
	EventBus.perfect_dodge.disconnect(_on_perfect)
	EventBus.player_died.disconnect(_on_died)
	world.queue_free()
	await physics_frames(2)


func _on_killed(enemy: Node2D, hit: HitInfo) -> void:
	events.append({"type": "killed", "enemy": enemy, "hit": hit})


func _on_perfect(_attacker: Node2D) -> void:
	events.append({"type": "perfect"})


func _on_died() -> void:
	events.append({"type": "died"})


func _enemy(scene: PackedScene, pos: Vector2, ai := false) -> Enemy:
	var e: Enemy = scene.instantiate()
	e.ai_enabled = ai
	e.position = pos
	world.add_child(e)
	return e


func _count(type: String) -> int:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == type).size()


func test_light_chain_advances_and_finisher_knocks_back() -> void:
	var e := _enemy(NEEDLE, Vector2(20, -2))
	await physics_frames(3)
	input.press_light()
	await physics_frames(1)
	check(player.current_state_id() == &"melee", "light did not start an attack")
	check(player.combat.current_attack.id == &"blade_light_1", "first attack should be light_1")
	await physics_frames(12)
	check_near(e.health, 20.0, 0.01, "light_1 damage")
	input.press_light()
	await physics_frames(2)
	check(player.combat.current_attack != null and player.combat.current_attack.id == &"blade_light_2", "chain did not advance")


func test_combo_resets_after_pause() -> void:
	var cfg := player.combat.config
	input.press_light()
	await physics_frames(30)
	await physics_frames(int(cfg.combo_reset_time * 60.0) + 4)
	input.press_light()
	await physics_frames(1)
	check(player.combat.current_attack.id == &"blade_light_1", "chain should reset after a pause")


func test_hitstop_freezes_attacker_and_victim() -> void:
	var e := _enemy(NEEDLE, Vector2(20, -2))
	await physics_frames(3)
	input.press_light()
	var froze := false
	for i in 12:
		await physics_frames(1)
		if player.hitstop_timer > 0.0 and e.hitstop_timer > 0.0:
			froze = true
			var x := player.global_position.x
			await physics_frames(1)
			check_near(player.global_position.x, x, 0.001, "player moved during hitstop")
			break
	check(froze, "no hitstop on hit")


func test_launcher_launches_enemy() -> void:
	var e := _enemy(NEEDLE, Vector2(18, -2))
	await physics_frames(3)
	input.up_held = true
	input.press_heavy()
	await physics_frames(1)
	check(player.combat.current_attack.id == &"blade_launcher", "up+heavy should launch")
	var peak := 0.0
	for i in 40:
		await physics_frames(1)
		peak = minf(peak, e.global_position.y)
	check(peak < -40.0, "enemy not launched (peak %.1f)" % peak)
	input.up_held = false


func test_shield_blocks_front_but_not_back_or_heavy() -> void:
	var e := _enemy(SHIELD, Vector2(22, -2))
	e.facing = -1  # guard faces the player
	await physics_frames(3)
	input.press_light()
	await physics_frames(14)
	check_near(e.health, e.data.max_health, 0.01, "frontal light should be blocked")
	# From behind.
	player.respawn(Vector2(44, -2), -1)
	await physics_frames(20)
	input.press_light()
	await physics_frames(14)
	check(e.health < e.data.max_health, "hit from behind should land")
	var hp := e.health
	player.respawn(Vector2(0, -2), 1)
	e.facing = -1
	await physics_frames(20)
	input.press_heavy()
	await physics_frames(30)
	check(e.health < hp, "heavy should break the guard")


func test_pistol_hits_at_range_and_uses_ammo() -> void:
	var e := _enemy(NEEDLE, Vector2(140, -2))
	await physics_frames(3)
	var w := player.combat.ranged_weapon()
	check(w.id == &"service_pistol", "default ranged should be the pistol")
	input.press_ranged()
	await physics_frames(20)
	check_near(e.health, e.data.max_health - w.shot.damage, 0.01, "pistol damage at range")
	check(int(player.combat.ammo[w.id]) == w.ammo_max - 1, "ammo not consumed")
	await physics_frames(int(w.reload_time * 60.0) + 5)
	check(int(player.combat.ammo[w.id]) == w.ammo_max, "did not reload when idle")


func test_scattergun_fans_pellets_and_is_short_range() -> void:
	player.combat.cycle_ranged()
	var w := player.combat.ranged_weapon()
	check(w.id == &"scattergun", "cycle should select the scattergun")
	input.press_ranged()
	await physics_frames(1)
	var pellets := world.get_children().filter(func(n: Node) -> bool: return n is Projectile).size()
	check(pellets == w.shot.projectile.pellets, "expected %d pellets, got %d" % [w.shot.projectile.pellets, pellets])
	var far := _enemy(NEEDLE, Vector2(200, -2))
	await physics_frames(30)
	check_near(far.health, far.data.max_health, 0.01, "scattergun should not reach 200px")


func test_scattergun_down_shot_in_air_pops_player_up() -> void:
	player.combat.cycle_ranged()
	input.press_jump()
	await physics_frames(24)  # falling after apex
	check(player.velocity.y > 0.0, "setup: should be falling")
	input.down_held = true
	input.press_ranged()
	await physics_frames(1)
	input.down_held = false
	check(player.velocity.y < -100.0, "downward shot should recoil upward (vy %.1f)" % player.velocity.y)


func test_enemy_telegraphs_before_hitting_player() -> void:
	var e := _enemy(NEEDLE, Vector2(30, -2), true)
	var windup_seen_at := -1
	var hurt_at := -1
	for i in 120:
		await physics_frames(1)
		if windup_seen_at < 0 and e.ai == Enemy.AI.WINDUP:
			windup_seen_at = i
		if player.combat.health < player.combat.config.max_health:
			hurt_at = i
			break
	check(windup_seen_at >= 0, "no wind-up observed")
	check(hurt_at > 0, "needle never hit the player")
	if windup_seen_at >= 0 and hurt_at > 0:
		check((hurt_at - windup_seen_at) / 60.0 >= e.data.attacks[0].startup - 0.02,
			"hit landed before the telegraph finished")
	check(player.current_state_id() == &"hurt", "player should be in hurt state")


func test_perfect_dodge_negates_damage() -> void:
	var e := _enemy(NEEDLE, Vector2(30, -2), true)
	for i in 180:
		await physics_frames(1)
		if e.ai == Enemy.AI.WINDUP and e.ai_time >= e.current_attack.startup - 2.0 / 60.0:
			break
	input.press_dodge()
	await physics_frames(20)
	check(_count("perfect") >= 1, "perfect dodge not detected")
	check(player.combat.health == player.combat.config.max_health, "took damage despite perfect dodge")


func test_encounter_director_limits_attackers() -> void:
	var director := EncounterDirector.new()
	director.max_attackers = 2
	world.add_child(director)
	for x in [-30, 30, 40, -40]:
		_enemy(NEEDLE, Vector2(x, -2), true)
	player.combat.config = player.combat.config.duplicate()
	player.combat.config.hurt_invuln_time = 100.0  # keep the player alive and still
	var worst := 0
	for i in 240:
		await physics_frames(1)
		var attacking := 0
		for n in get_tree().get_nodes_in_group(&"enemies"):
			var en := n as Enemy
			if en.ai == Enemy.AI.WINDUP or en.ai == Enemy.AI.ACTIVE or en.ai == Enemy.AI.RECOVER:
				attacking += 1
		worst = maxi(worst, attacking)
	check(worst <= 2, "more than 2 simultaneous attackers (%d)" % worst)
	check(worst >= 1, "nobody attacked")


func test_launched_enemy_damages_the_one_it_hits() -> void:
	var a := _enemy(NEEDLE, Vector2(20, -2))
	var b := _enemy(NEEDLE, Vector2(70, -2))
	await physics_frames(3)
	# Finisher sends `a` flying into `b`.
	for i in 3:
		input.press_light()
		await physics_frames(10)
	await physics_frames(40)
	check(b.health < b.data.max_health, "second enemy not hurt by the launched body")


func test_hazard_kill_credits_player() -> void:
	var spikes := SpikeHazard.new()
	spikes.size = Vector2(64, 8)
	spikes.position = Vector2(60, -8)
	world.add_child(spikes)
	var e := _enemy(NEEDLE, Vector2(24, -2))
	await physics_frames(3)
	input.press_heavy()
	await physics_frames(60)
	var kills := events.filter(func(ev: Dictionary) -> bool: return ev["type"] == "killed")
	check(kills.size() == 1, "enemy not killed by spikes")
	if kills.size() == 1:
		var hit: HitInfo = kills[0]["hit"]
		check(hit.attacker == player, "environmental kill not credited to player")
		check(hit.has_tag(&"environmental"), "kill not tagged environmental")


func test_player_death_and_respawn_restore_health() -> void:
	player.combat.take_damage(player.combat.config.max_health, Vector2.ZERO, 0.0, true)
	await physics_frames(1)
	check(_count("died") == 1, "player_died not emitted")
	check(player.combat.dead, "not dead")
	player.respawn(Vector2(0, -2))
	check(not player.combat.dead and player.combat.health == player.combat.config.max_health, "respawn did not restore health")


func test_dodge_iframes_evade_hits() -> void:
	input.press_dodge()
	await physics_frames(3)
	var needle_attack: AttackData = preload("res://data/enemies/needle.tres").attacks[0]
	var hit := HitInfo.create(null, needle_attack, Vector2(100, 0), Vector2.RIGHT)
	hit.source_position = player.global_position - Vector2(10, 0)
	var result := player.receive_hit(hit)
	check(result == CombatResult.PERFECT_EVADE or result == CombatResult.EVADED, "dodge should evade, got %s" % CombatResult.name_of(result))
	check(player.combat.health == player.combat.config.max_health, "damage leaked through i-frames")


func test_point_blank_shot_hits_overlapping_enemy() -> void:
	# Muzzle starts inside the enemy's hurtbox; the shot must still land.
	var e := _enemy(NEEDLE, Vector2(8, -2))
	await physics_frames(3)
	input.press_ranged()
	await physics_frames(4)
	check(e.health < e.data.max_health, "point-blank pistol shot missed an overlapping enemy")


func test_point_blank_when_shooter_center_inside_enemy() -> void:
	# Player stands fully inside a (rear-facing) shield: the shot must still register.
	var e := _enemy(SHIELD, Vector2(2, -2))
	e.facing = 1  # guard faces away from the shot's origin side
	await physics_frames(3)
	input.press_ranged()
	await physics_frames(4)
	check(e.health < e.data.max_health or e.last_hit != null, "shot from inside the enemy registered nothing")


## Jump peak (px above the floor at y 0) with an air light pressed `light_at`
## frames after the jump press (-1: none; 0: the same frame).
func _jump_peak(light_at: int) -> float:
	player.respawn(Vector2(0, -2))
	await physics_frames(3)
	input.press_jump()
	var peak := 0.0
	for f in 90:
		if f == light_at:
			input.press_light()
		await physics_frames(1)
		peak = minf(peak, player.global_position.y)
		if f > 5 and player.is_on_floor():
			break
	input.release_jump()
	return -peak


## M7 D2b: an air light hangs (and slows the fall) only when it connects. A
## whiffed air light, or a light pressed on the jump frame, leaves the jump
## as it was: chained whiffs used to lift a floor jump ~30 px and carry a
## jump over the Dash gates. A hit still takes one of the airtime's hangs.
func test_air_hang_only_on_hit() -> void:
	var plain := await _jump_peak(-1)
	var whiff := await _jump_peak(14)
	check(absf(whiff - plain) < 1.0, "a whiffed air light should not lift the jump (%.1f vs %.1f)" % [whiff, plain])
	check(player.combat.air_hang_left == player.combat.config.air_hang_uses, "a whiff takes no hang")
	var same_frame := await _jump_peak(0)
	check(same_frame < plain + 1.0, "a light on the jump frame should not super-jump (%.1f vs %.1f)" % [same_frame, plain])
	# A drone just above the rising blade: the hit hangs Rook.
	var e := _enemy(DRONE, Vector2(14, -78))
	await physics_frames(2)
	var hp := e.health
	var hit := await _jump_peak(14)
	check(e.health < hp, "setup: the air light should hit the drone")
	check(hit > plain + 4.0, "a connecting air light should hang Rook (%.1f vs %.1f)" % [hit, plain])
