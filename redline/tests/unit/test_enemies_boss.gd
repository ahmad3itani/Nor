extends RedlineTestCase
## M3.5: Hopper, Watcher, Enforcer and Warden Krail (phases, arena, reward).

const PLAYER_SCENE := preload("res://player/Player.tscn")

var world: Node2D
var player: Player
var input: ScriptedInputSource


func before_each() -> void:
	Game.new_game()
	world = Node2D.new()
	add_child(world)
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
	player.combat.config = player.combat.config.duplicate()
	await physics_frames(3)


func after_each() -> void:
	world.queue_free()
	Game.new_game()
	await physics_frames(2)


func _spawn(path: String, pos: Vector2, ai := true) -> Enemy:
	var e: Enemy = load(path).instantiate()
	e.ai_enabled = ai
	e.position = pos
	world.add_child(e)
	return e


func _wait_for_damage(frames: int) -> bool:
	var hp := player.combat.health
	for i in frames:
		await physics_frames(1)
		if player.combat.health < hp:
			return true
	return false


func test_hopper_leaps_and_hits() -> void:
	var h := _spawn("res://enemies/variants/Hopper.tscn", Vector2(90, -2))
	var peak := 0.0
	var hurt := false
	for i in 240:
		await physics_frames(1)
		peak = minf(peak, h.global_position.y)
		if player.combat.health < player.combat.config.max_health:
			hurt = true
			break
	check(peak < -20.0, "hopper never leapt (peak %.1f)" % peak)
	check(hurt, "hopper never hit the player")


func test_watcher_needs_line_of_sight_and_stays_mounted() -> void:
	var w := _spawn("res://enemies/variants/Watcher.tscn", Vector2(150, -80))
	var wall := GrayboxBlock.new()
	wall.size = Vector2(16, 120)
	wall.position = Vector2(70, -120)
	world.add_child(wall)
	await physics_frames(5)
	check(not w.has_line_of_sight(), "wall should block the watcher's sight")
	var fired := false
	for i in 120:
		await physics_frames(1)
		if w.ai == Enemy.AI.WINDUP:
			fired = true
	check(not fired, "watcher started an attack without line of sight")
	wall.queue_free()
	check(await _wait_for_damage(300), "watcher never hit with a clear line")
	var pos := w.global_position
	var blade: WeaponData = load("res://data/weapons/pulse_blade.tres")
	w.receive_hit(HitInfo.create(player, blade.launcher, Vector2(0, -400), Vector2.UP))
	await physics_frames(20)
	check(w.global_position.distance_to(pos) < 1.0, "anchored watcher moved when hit")


func test_enforcer_combo_follows_up() -> void:
	var e := _spawn("res://enemies/variants/Enforcer.tscn", Vector2(30, -2))
	player.combat.config.hurt_invuln_time = 0.3
	var seen: Array[String] = []
	for i in 300:
		await physics_frames(1)
		if e.current_attack and (seen.is_empty() or seen[seen.size() - 1] != String(e.current_attack.id)):
			seen.append(String(e.current_attack.id))
		if seen.has("enforcer_baton_2"):
			break
	check(seen.has("enforcer_baton_1") and seen.has("enforcer_baton_2"), "combo did not chain: %s" % [seen])
	var i1 := seen.find("enforcer_baton_1")
	check(i1 >= 0 and seen.find("enforcer_baton_2") == i1 + 1, "baton_2 should directly follow baton_1")


func test_krail_phase_two_speeds_up_and_summons() -> void:
	var k := _spawn("res://bosses/WardenKrail.tscn", Vector2(200, -2))
	await physics_frames(3)
	var before := get_tree().get_nodes_in_group(&"enemies").size()
	k.health = k.data.max_health * 0.49
	await physics_frames(5)
	var behavior = k.behavior
	check(behavior.phase == 2, "phase 2 did not trigger at 49% health")
	check(k.telegraph_scale < 1.0, "phase 2 should shorten wind-ups")
	await physics_frames(3)
	check(get_tree().get_nodes_in_group(&"enemies").size() == before + 2, "phase 2 should summon two Needles")


func test_krail_never_repeats_an_attack() -> void:
	var k := _spawn("res://bosses/WardenKrail.tscn", Vector2(200, -2))
	player.combat.config.hurt_invuln_time = 100.0
	await physics_frames(3)
	var seq: Array[String] = []
	var prev_ai := k.ai
	for i in 60 * 25:
		await physics_frames(1)
		# Record each fresh decision (ENGAGE -> WINDUP); follow-ups are part of a combo.
		if k.ai == Enemy.AI.WINDUP and prev_ai == Enemy.AI.ENGAGE and k.current_attack:
			seq.append(String(k.current_attack.id))
		prev_ai = k.ai
		if seq.size() >= 8:
			break
	check(seq.size() >= 4, "boss attacked too rarely: %s" % [seq])
	for i in range(1, seq.size()):
		check(seq[i] != seq[i - 1], "repeated attack %s" % seq[i])


func test_ground_wave_is_jumpable() -> void:
	var k := _spawn("res://bosses/WardenKrail.tscn", Vector2(160, -2), false)
	await physics_frames(2)
	var slam: AttackData = k.behavior.attack(&"krail_ground_slam")
	k.facing = -1
	k.current_attack = slam
	k._begin_active()
	# Grounded: the wave hits.
	check(await _wait_for_damage(60), "ground wave should hit a grounded player")
	player.respawn(Vector2(0, -2))
	await physics_frames(3)
	k.current_attack = slam
	k._begin_active()
	var travel := (160.0 - k.data.body_size.x * 0.5) / slam.projectile.speed
	await physics_frames(int(travel * 60.0) - 12)
	input.press_jump()
	check(not await _wait_for_damage(50), "jumping should clear the ground wave")


func test_boss_arena_locks_rewards_and_remembers() -> void:
	var k := _spawn("res://bosses/WardenKrail.tscn", Vector2(300, -2), false)
	var gate := Gate.new()
	gate.size = Vector2(16, 64)
	gate.position = Vector2(-60, -64)
	world.add_child(gate)
	var arena := BossArena.new()
	arena.size = Vector2(200, 100)
	arena.position = Vector2(100, -100)
	arena.intro_time = 0.1
	arena.reward_scene = load("res://interactables/DashModule.tscn")
	world.add_child(arena)
	arena.boss_path = arena.get_path_to(k)
	arena.gate_paths = [arena.get_path_to(gate)]
	arena._ready()
	player.teleport(Vector2(150, -2))
	await physics_frames(3)
	check(gate.closed, "gate should close when the fight starts")
	await physics_frames(12)
	check(k.ai_enabled, "boss should activate after the intro")
	var kill := HitInfo.create(player, k.data.attacks[0].duplicate(), Vector2.ZERO, Vector2.RIGHT)
	kill.attack.damage = 99999.0
	k.receive_hit(kill)
	check(Game.has_flag("warden_krail_defeated"), "defeat flag not set")
	await physics_frames(int((k.data.death_time + 0.4) * 60.0))
	check(not gate.closed, "gate should open after the boss dies")
	var rewards := world.find_children("*", "AbilityPickup", true, false)
	check(rewards.size() == 1, "reward not spawned")
	if rewards.size() == 1:
		player.teleport((rewards[0] as Node2D).global_position)
		await physics_frames(3)
		check(Game.abilities.dash and Game.has_flag("unlocked_dash"), "dash not granted")
