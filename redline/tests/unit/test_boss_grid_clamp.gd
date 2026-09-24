extends RedlineTestCase
## M7/M5 Grid clamp, Warden Krail's boss test (D-071), on tests/fixtures/
## grid_clamp.tscn (tools/roomgen/fixtures_grid.py): Warden Tower's arena
## (floor x -48..464 at y 0, one-ways at 60 and 300, y -72), high breakers
## at (36,-96) and (396,-96) on wt_clamp, clamp x 176..240 (top -270, raised
## bottom -120, drops to -24), the real Krail at 330 with its BossArena
## (40,-250, 400x250). Timing (clamp_krail): warn 1.0, drop 0.15, hold 1.0,
## rise 0.5, rearm 8.0.

const FIXTURE := "res://tests/fixtures/grid_clamp.tscn"
const HINT_TEXT := "Breakers live: drop the clamp on him"

var root: Node2D
var drops: Array = []
var hints: Array = []


func before_each() -> void:
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	Game.new_game()
	drops.clear()
	hints.clear()
	EventBus.clamp_dropped.connect(_on_dropped)
	EventBus.hint_requested.connect(_on_hint)


func after_each() -> void:
	EventBus.clamp_dropped.disconnect(_on_dropped)
	EventBus.hint_requested.disconnect(_on_hint)
	SceneRouter.current_room = null
	SceneRouter.world_root = null
	root.queue_free()
	Game.new_game()
	await physics_frames(2)


func _on_dropped(id: String, staggered: bool) -> void:
	drops.append([id, staggered])


func _on_hint(text: String, _seconds: float) -> void:
	if text == HINT_TEXT:
		hints.append(Engine.get_physics_frames())


func _enter() -> Room:
	SceneRouter.goto_room(FIXTURE, &"from_bell")
	await physics_frames(10)
	return SceneRouter.current_room as Room


func _clamp(room: Room) -> GridClamp:
	return room.find_child("Clamp_wt_clamp", true, false) as GridClamp


func _krail(room: Room) -> Enemy:
	return room.find_child("WardenKrail1", true, false) as Enemy


func _breaker(room: Room) -> Breaker:
	return room.find_child("Breaker_wt_grid_w", true, false) as Breaker


## Walks Rook into the BossArena trigger (it starts on body entry).
func _start_arena(room: Room, at: Vector2 = Vector2(100, 0)) -> void:
	room.player.teleport(at)
	await physics_frames(3)


## Krail out of the way (this test is about Rook, not the fight).
func _freeze(k: Enemy) -> void:
	k.global_position = Vector2(420, 0)
	k.process_mode = Node.PROCESS_MODE_DISABLED


func _slam_frames(c: GridClamp) -> int:
	return int(ceil((c.timing.warn + c.timing.drop) * 60.0)) + 3


func test_clamp_staggers_krail() -> void:
	var room := await _enter()
	var c := _clamp(room)
	var k := _krail(room)
	check(c != null and k != null, "fixture needs Clamp_wt_clamp and WardenKrail1")
	if c == null or k == null:
		return
	await _start_arena(room)
	check(c.state == GridClamp.State.READY, "the arena start arms the clamp (%s)" % c.state_name())
	k.global_position = Vector2(208, 0)
	await physics_frames(2)
	var hp := k.health
	var charge := room.player.reactor.charge
	check(_breaker(room).trip(), "breaker trip")
	await physics_frames(_slam_frames(c))
	check(k.ai == Enemy.AI.STAGGER, "Krail should be staggered, is %s" % Enemy.AI.keys()[k.ai])
	check_near(hp - k.health, 30.0, 0.01, "Krail takes the clamp's 30")
	check(drops == [["wt_clamp", true]], "clamp_dropped(wt_clamp, staggered): %s" % str(drops))
	check(room.player.reactor.charge > charge, "Rook is credited: the Core charges (%.1f -> %.1f)" % [charge, room.player.reactor.charge])
	# Demolitionist doubles the environmental damage.
	Game.new_game()
	Game.grant_circuit("demolitionist")
	check(Game.toggle_circuit("demolitionist"), "could not equip demolitionist")
	room = await _enter()
	c = _clamp(room)
	k = _krail(room)
	await _start_arena(room)
	k.global_position = Vector2(208, 0)
	await physics_frames(2)
	hp = k.health
	_breaker(room).trip()
	await physics_frames(_slam_frames(c))
	check_near(hp - k.health, 60.0, 0.01, "Demolitionist doubles the clamp")


func test_sliding_rook_safe_standing_rook_hit_and_pushed_out() -> void:
	var room := await _enter()
	var p := room.player
	var c := _clamp(room)
	_freeze(_krail(room))
	await _start_arena(room)
	var input := ScriptedInputSource.new()
	p.input_source = input
	# Low (crouched) at the centre of the footprint when it lands: safe.
	p.teleport(Vector2(208, 0))
	input.down_held = true
	_breaker(room).trip()
	await physics_frames(_slam_frames(c))
	check(p.is_low, "Rook should be low under the clamp")
	check(p.combat.health == p.combat.config.max_health, "a low Rook is safe (health %d)" % p.combat.health)
	check(c.state == GridClamp.State.HOLD, "the clamp holds at the slot (%s)" % c.state_name())
	check(drops.size() == 1 and drops[0][1] == false, "clamp_dropped without a boss: %s" % str(drops))
	# Sliding through the 24 px slot while it holds: also safe.
	input.down_held = false
	p.teleport(Vector2(120, 0))
	await physics_frames(2)
	var bot := RouteBot.new(get_tree(), p)
	var ok: bool = await bot.run([["slide", 260]])
	check(ok and p.global_position.x > 246.0, "a slide passes under the held clamp (x %.0f, %s)" % [p.global_position.x, bot.failure])
	check(p.combat.health == p.combat.config.max_health, "sliding under it costs nothing (%d, %s, x %.0f)" % [p.combat.health, p.combat.last_damage_source, p.global_position.x])
	# Standing under it when it lands: 1 pip and shoved out of 176..240.
	Game.new_game()
	room = await _enter()
	p = room.player
	c = _clamp(room)
	_freeze(_krail(room))
	await _start_arena(room)
	p.teleport(Vector2(200, 0))
	await physics_frames(2)
	_breaker(room).trip()
	await physics_frames(_slam_frames(c))
	check(p.combat.health == p.combat.config.max_health - 1, "a standing Rook takes 1 pip (health %d, last %s)" % [p.combat.health, p.combat.last_damage_source])
	check(p.combat.last_damage_source == "clamp", "damage source 'clamp' (%s)" % p.combat.last_damage_source)
	var half := p.config.standing_size.x * 0.5
	check(p.global_position.x + half <= 176.0 or p.global_position.x - half >= 240.0,
		"Rook ends up outside x 176..240 (x %.1f)" % p.global_position.x)
	await physics_frames(20)
	check(p.global_position.x + half <= 176.0 or p.global_position.x - half >= 240.0,
		"and stays out while it holds (x %.1f)" % p.global_position.x)


func test_inert_before_arena_start() -> void:
	var room := await _enter()
	var c := _clamp(room)
	var k := _krail(room)
	check(c.state == GridClamp.State.INERT, "inert before the arena starts (%s)" % c.state_name())
	k.global_position = Vector2(208, 0)
	var hp := k.health
	_breaker(room).trip()
	await physics_frames(_slam_frames(c) + 30)
	check(c.state == GridClamp.State.INERT and drops.is_empty(), "a breaker hit does nothing while inert (%s)" % c.state_name())
	check(is_equal_approx(k.health, hp), "Krail untouched")


func test_rises_for_good_after_defeat() -> void:
	var room := await _enter()
	var c := _clamp(room)
	var k := _krail(room)
	await _start_arena(room)
	check(c.state == GridClamp.State.READY, "armed (%s)" % c.state_name())
	# Finish Krail through the real receive path.
	k.health = 1.0
	var attack := load("res://data/combat/hazard_attack.tres") as AttackData
	k.receive_hit(HitInfo.create(room.player, attack, Vector2.ZERO, Vector2.RIGHT))
	await physics_frames(3)
	check(Game.has_flag("warden_krail_defeated"), "Krail's defeat flag")
	check(c.state == GridClamp.State.DONE, "the clamp retires on boss_defeated (%s)" % c.state_name())
	_breaker(room).trip()
	await physics_frames(_slam_frames(c))
	check(drops.is_empty() and c.state == GridClamp.State.DONE, "a retired clamp never drops")
	check_near(c.bottom, c.raised_bottom - (-270.0), 0.01, "raised for good")
	# On reload the defeat flag keeps it up and dark.
	room = await _enter()
	c = _clamp(room)
	check(c.state == GridClamp.State.DONE, "defeated flag -> DONE on load (%s)" % c.state_name())


func test_arm_hint_once() -> void:
	var room := await _enter()
	var c := _clamp(room)
	check(c.arm_hint_id == "t_clamp", "fixture clamp has arm_hint_id t_clamp")
	await _start_arena(room)
	var armed_at := Engine.get_physics_frames()
	# Krail stays at 330 (outside the footprint): the line waits 4.0 s.
	await physics_frames(int(GridClamp.HINT_DELAY * 60.0) + 5)
	check(hints.size() == 1, "one teaching line within 4.0 s: %s" % str(hints))
	if hints.size() == 1:
		check_near(float(hints[0] - armed_at) / 60.0, GridClamp.HINT_DELAY, 0.15, "the line lands 4.0 s after arming")
	check(Game.has_flag("hint_t_clamp"), "hint flag set")
	check(_breaker(room).is_lit(), "the breaker lamps pulse with the line")
	# Earlier when Krail walks under the clamp.
	Game.new_game()
	hints.clear()
	room = await _enter()
	await _start_arena(room)
	armed_at = Engine.get_physics_frames()
	_krail(room).global_position = Vector2(208, 0)
	await physics_frames(10)
	check(hints.size() == 1 and float(hints[0] - armed_at) / 60.0 < 1.0, "Krail under the clamp brings the line forward: %s" % str(hints))
	# Re-arming later (a retry: same profile, room reloaded) shows nothing.
	hints.clear()
	room = await _enter()
	await _start_arena(room)
	await physics_frames(int(GridClamp.HINT_DELAY * 60.0) + 30)
	check(hints.is_empty(), "the line is shown once per profile: %s" % str(hints))
	# The validator sees the hint flag and the circuit.
	var v := ContentValidator.new().check_room(FIXTURE, false)
	check(v.errors.is_empty(), "grid_clamp validates: %s" % str(v.errors))
	check(v.produced.has("hint_t_clamp") and v.consumed.has("circuit:wt_clamp") and v.produced.has("circuit:wt_clamp"), "clamp/breaker flags in the graph")
