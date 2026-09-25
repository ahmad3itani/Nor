extends RedlineTestCase
## M7/M5 the Grid (D-071): Breaker + PowerShutter on tests/fixtures/
## grid_shutter.tscn (tools/roomgen/fixtures_grid.py): floor x -48..800 at
## y 0; floor breaker t_fb box (60,-40) on t1; high breaker t_hb box
## (400,-96) on t2; shutter S (176,-200,16,200) on t1, shutter_run, latch
## t_latched; a secret wall at 720; a Needle at 600; spawn start (218, 0)
## facing west. The validator cases use grid_validator.tscn.

const FIXTURE := "res://tests/fixtures/grid_shutter.tscn"
const VALIDATOR_FIXTURE := "res://tests/fixtures/grid_validator.tscn"
const TIMINGS := ["res://data/level/shutter_intro.tres", "res://data/level/shutter_run.tres", "res://data/level/shutter_l3.tres"]

var root: Node2D
var trips: Array = []
var passes: Array = []
var enemy_hits: Array = []
var _added_circuit: Resource


func before_each() -> void:
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	Game.new_game()
	trips.clear()
	passes.clear()
	enemy_hits.clear()
	EventBus.breaker_hit.connect(_on_breaker_hit)
	EventBus.shutter_passed.connect(_on_passed)
	EventBus.enemy_damaged.connect(_on_enemy_damaged)


func after_each() -> void:
	EventBus.breaker_hit.disconnect(_on_breaker_hit)
	EventBus.shutter_passed.disconnect(_on_passed)
	EventBus.enemy_damaged.disconnect(_on_enemy_damaged)
	if _added_circuit:
		Game.catalog.circuits.erase(_added_circuit)
		_added_circuit = null
	SceneRouter.current_room = null
	SceneRouter.world_root = null
	root.queue_free()
	Game.new_game()
	await physics_frames(2)


func _on_breaker_hit(circuit: StringName) -> void:
	trips.append(circuit)


func _on_passed(id: String, margin: float) -> void:
	passes.append([id, margin])


func _on_enemy_damaged(_enemy: Node2D, _hit: HitInfo, _result: int) -> void:
	enemy_hits.append(1)


func _enter() -> Room:
	SceneRouter.goto_room(FIXTURE, &"start")
	await physics_frames(10)
	return SceneRouter.current_room as Room


func _shutter(room: Room) -> PowerShutter:
	return room.find_child("Shutter_S", true, false) as PowerShutter


func _breaker(room: Room, id: String) -> Breaker:
	return room.find_child("Breaker_" + id, true, false) as Breaker


## Hands Rook a known kit (independent of the campaign's starting loadout).
func _arm(p: Player, ranged_id: String = "service_pistol") -> void:
	p.combat.set_loadout(Game.catalog.weapon("pulse_blade"), Game.catalog.weapon(ranged_id))


func _scripted(p: Player) -> ScriptedInputSource:
	var input := ScriptedInputSource.new()
	p.input_source = input
	return input


func _frames(seconds: float) -> int:
	return int(ceil(seconds * 60.0))


# --- Data ---------------------------------------------------------------------------

func test_data_timings_validate() -> void:
	var want := {"shutter_intro": [5.0, 1.5, 0.25, 0.8, 0.15], "shutter_run": [3.2, 1.0, 0.25, 0.6, 0.15],
		"shutter_l3": [3.6, 1.2, 0.25, 0.6, 0.15]}
	for path: String in TIMINGS:
		var t := load(path) as ShutterTiming
		check(t != null, "%s should load as ShutterTiming" % path)
		if t == null:
			continue
		check(t.validate().is_empty(), "%s: %s" % [path, str(t.validate())])
		var w: Array = want[path.get_file().get_basename()]
		check(is_equal_approx(t.open, w[0]) and is_equal_approx(t.warn, w[1]) and is_equal_approx(t.drop, w[2])
			and is_equal_approx(t.slot, w[3]) and is_equal_approx(t.seal, w[4]), "%s numbers drifted" % path)
	var bad := ShutterTiming.new()
	bad.slot = 0.5
	check(not bad.validate().is_empty(), "slot < 0.55 must fail validation")
	bad = ShutterTiming.new()
	bad.warn = bad.open
	check(not bad.validate().is_empty(), "warn >= open must fail validation")
	bad = ShutterTiming.new()
	bad.open = 1.5
	bad.warn = 0.5
	check(not bad.validate().is_empty(), "open < 2.0 must fail validation")
	var clamp := load("res://data/level/clamp_krail.tres") as ClampTiming
	check(clamp != null and clamp.validate().is_empty(), "clamp_krail.tres should validate")
	if clamp:
		check(is_equal_approx(clamp.warn, 1.0) and is_equal_approx(clamp.drop, 0.15) and is_equal_approx(clamp.hold, 1.0)
			and is_equal_approx(clamp.rise, 0.5) and is_equal_approx(clamp.rearm, 8.0), "clamp_krail numbers drifted")
	var attack := load("res://data/combat/grid_clamp_attack.tres") as AttackData
	check(attack != null and attack.validate().is_empty(), "grid_clamp_attack.tres should validate")
	if attack:
		check(attack.id == &"grid_clamp" and is_equal_approx(attack.damage, 30.0) and is_equal_approx(attack.poise_damage, 120.0)
			and attack.style_tag == &"environmental" and attack.projectile == null, "grid_clamp_attack numbers drifted")


# --- Breaker ------------------------------------------------------------------------

func test_floor_breaker_tripped_by_light_attack() -> void:
	var room := await _enter()
	var p := room.player
	_arm(p)
	var input := _scripted(p)
	var fb := _breaker(room, "t_fb")
	check(fb != null, "fixture has no floor breaker t_fb")
	if fb == null:
		return
	# West of the shutter, facing the breaker (box 60..76, -40..-16).
	p.teleport(Vector2(92, 0))
	p.facing = -1
	await physics_frames(3)
	input.press_light()
	await physics_frames(24)
	check(trips == [&"t1"], "a ground light attack should trip t_fb once: %s" % str(trips))
	check(fb.trips == 1, "breaker trip count should be 1, got %d" % fb.trips)
	check(_shutter(room).state == PowerShutter.State.OPEN, "the shutter on t1 should open, is %s" % _shutter(room).state_name())


func test_high_breaker_jump_air_light_and_each_gun() -> void:
	var room := await _enter()
	var p := room.player
	_arm(p)
	var input := _scripted(p)
	var hb := _breaker(room, "t_hb")
	check(hb != null, "fixture has no high breaker t_hb")
	if hb == null:
		return
	# Jump + air light from just left of the box (400..416), facing it.
	p.teleport(Vector2(392, 0))
	p.facing = 1
	await physics_frames(3)
	input.press_jump()
	for f in 40:
		await physics_frames(1)
		if p.global_position.y <= -40.0 and p.velocity.y < 0.0:
			break
	input.press_light()
	await physics_frames(40)
	input.release_jump()
	check(trips.count(&"t2") == 1, "jump + air light should trip t_hb: %s (feet peaked near %.0f)" % [str(trips), p.global_position.y])
	await physics_frames(30)
	# Every gun reaches it straight up from x 400.
	for gun in ["service_pistol", "heavy_revolver", "scattergun"]:
		await _shoot_up(p, input, gun)
		check(hb.trips >= 1 and trips.size() > 0 and trips.back() == &"t2", "%s straight up should trip t_hb" % gun)
	check(trips.count(&"t2") == 4, "air light + three guns = 4 trips, got %s" % str(trips))
	# A short-range circuit (ranged_range x0.7) still reaches it with the scattergun.
	var c := CircuitData.new()
	c.id = "test_short_range"
	c.display_name = "Test short range"
	c.description = "test"
	c.multipliers = {&"ranged_range": 0.7}
	_added_circuit = c
	Game.catalog.circuits.append(c)
	Game.state.owned_circuits.append("test_short_range")
	check(Game.toggle_circuit("test_short_range"), "could not equip the test circuit")
	check_near(Game.circuit_mult(&"ranged_range"), 0.7, 0.001, "test circuit multiplier")
	var before := trips.size()
	await _shoot_up(p, input, "scattergun")
	check(trips.size() == before + 1, "scattergun with ranged_range x0.7 should still trip t_hb")


func _shoot_up(p: Player, input: ScriptedInputSource, gun: String) -> void:
	_arm(p, gun)
	p.teleport(Vector2(400, 0))
	p.facing = 1
	await physics_frames(36)  # past the breaker's re-arm time
	input.up_held = true
	input.press_ranged()
	await physics_frames(20)
	input.up_held = false


func test_launched_needle_trips_neither_breaker_nor_secret_wall() -> void:
	var room := await _enter()
	var needle := room.find_child("Needle1", true, false) as Enemy
	var wall := room.find_child("Breakable1", true, false) as BreakableWall
	var fb := _breaker(room, "t_fb")
	check(needle != null and wall != null and fb != null, "fixture needs Needle1, Breakable1 and t_fb")
	if needle == null or wall == null or fb == null:
		return
	needle.ai_enabled = false
	var secrets: Array = []
	var on_secret := func(id: String) -> void: secrets.append(id)
	EventBus.secret_found.connect(on_secret)
	# Thrown through the floor breaker's box...
	needle.global_position = Vector2(120, -12)
	needle.set_ai(Enemy.AI.LAUNCHED)
	needle.velocity = Vector2(-360, -60)
	var crossed := false
	for f in 30:
		await physics_frames(1)
		if is_instance_valid(needle) and needle.body_rect().intersects(fb.hurtbox_rect()):
			crossed = true
	check(crossed, "the launched Needle must actually fly through the breaker's hurtbox")
	check(fb.trips == 0 and trips.is_empty(), "a launched body must not trip a breaker (%s)" % str(trips))
	# ...and into the secret wall.
	check(is_instance_valid(needle) and not needle.is_dead(), "the Needle must survive the first throw for the wall half")
	if not is_instance_valid(needle) or needle.is_dead():
		EventBus.secret_found.disconnect(on_secret)
		return
	needle.global_position = Vector2(680, -12)
	needle.set_ai(Enemy.AI.LAUNCHED)
	needle.velocity = Vector2(360, -60)
	var wall_rect := Rect2(wall.global_position, wall.size).grow(1.0)
	var hit_wall := false
	for f in 30:
		await physics_frames(1)
		if is_instance_valid(needle) and needle.body_rect().intersects(wall_rect):
			hit_wall = true
	check(hit_wall, "the launched Needle must actually reach the secret wall")
	check(is_instance_valid(wall) and is_equal_approx(wall.health, wall.max_health), "a launched body must not damage a secret wall")
	check(secrets.is_empty(), "no secret should be found: %s" % str(secrets))
	EventBus.secret_found.disconnect(on_secret)


func test_breaker_hit_gives_no_core_or_style() -> void:
	var room := await _enter()
	var p := room.player
	_arm(p)
	var input := _scripted(p)
	p.teleport(Vector2(92, 0))
	p.facing = -1
	await physics_frames(3)
	var charge := p.reactor.charge
	var points := p.style.meter.points
	input.press_light()
	await physics_frames(24)
	check(trips == [&"t1"], "the light attack should trip t_fb once: %s" % str(trips))
	check(enemy_hits.is_empty(), "a breaker must never emit enemy_damaged (%d)" % enemy_hits.size())
	check(p.reactor.charge <= charge + 0.001, "a breaker hit must not charge the Core (%.2f -> %.2f)" % [charge, p.reactor.charge])
	check(p.style.meter.points <= points + 0.001, "a breaker hit must not give style (%.2f -> %.2f)" % [points, p.style.meter.points])
	# Within rearm_time a second hit is ignored.
	var fb := _breaker(room, "t_fb")
	check(not fb.trip(), "a trip inside rearm_time must be ignored")
	check(trips.size() == 1, "an ignored trip must not emit breaker_hit")


# --- Shutter ------------------------------------------------------------------------

func test_slot_low_pass_vs_standing_block() -> void:
	var room := await _enter()
	var s := _shutter(room)
	var t := s.timing
	check(t == load("res://data/level/shutter_run.tres"), "fixture shutter should use shutter_run")
	_breaker(room, "t_fb").trip()
	await physics_frames(_frames(t.open + t.drop + t.slot * 0.5))
	check(s.state == PowerShutter.State.SLOT, "mid-slot state expected, got %s" % s.state_name())
	var bot := RouteBot.new(get_tree(), room.player)
	var ok: bool = await bot.run([["slide", 150]])
	check(ok and room.player.global_position.x < 170.0, "a slide should pass the 24 px slot (at %.0f, %s)" % [room.player.global_position.x, bot.failure])
	check(Game.has_flag("t_latched"), "a low pass should latch the shutter")
	# Low pass: margin = open + drop + slot - t, less than the slot itself
	# (slightly negative when he finishes clearing under the held seal).
	check(passes.size() == 1 and float(passes[0][1]) > -t.seal - 0.2 and float(passes[0][1]) < t.slot * 0.5,
		"low-pass margin should come from the slot clock: %s" % str(passes))
	# Fresh run: after the full cycle a standing run is blocked.
	Game.new_game()
	room = await _enter()
	s = _shutter(room)
	check(s.state == PowerShutter.State.CLOSED, "a fresh fixture starts closed (%s)" % s.state_name())
	_breaker(room, "t_fb").trip()
	await physics_frames(_frames(t.open + t.drop + t.slot + t.seal + 0.1))
	check(s.state == PowerShutter.State.CLOSED, "after the cycle the shutter is closed again (%s)" % s.state_name())
	bot = RouteBot.new(get_tree(), room.player)
	await bot.run([["run", 150]])
	check(room.player.global_position.x > 192.0, "a closed shutter must block the run (x %.1f)" % room.player.global_position.x)
	# Re-trip re-opens it.
	_breaker(room, "t_fb").trip()
	await physics_frames(2)
	check(s.state == PowerShutter.State.OPEN and is_equal_approx(s.gap, s.size.y), "a re-trip should reopen (%s, gap %.0f)" % [s.state_name(), s.gap])
	ok = await bot.run([["run", 150]])
	check(ok and room.player.global_position.x < 160.0, "after the re-trip a run passes (x %.0f)" % room.player.global_position.x)


func test_latch_persists_after_reload() -> void:
	var room := await _enter()
	_breaker(room, "t_fb").trip()
	var bot := RouteBot.new(get_tree(), room.player)
	var ok: bool = await bot.run([["run", 140]])
	check(ok, "a standing run through the open shutter failed: %s" % bot.failure)
	check(Game.has_flag("t_latched"), "a pass should set the latch flag")
	check(_shutter(room).state == PowerShutter.State.LATCHED, "the shutter should stay open for good")
	room = await _enter()
	var s := _shutter(room)
	check(s.state == PowerShutter.State.LATCHED and is_equal_approx(s.gap, s.size.y), "a latched shutter starts open on load (%s)" % s.state_name())
	bot = RouteBot.new(get_tree(), room.player)
	ok = await bot.run([["run", 140]])
	check(ok and room.player.global_position.x < 150.0, "a latched shutter needs no breaker (x %.0f)" % room.player.global_position.x)
	await physics_frames(_frames(s.timing.cycle() + 0.2))
	check(s.state == PowerShutter.State.LATCHED, "a latched shutter never drops again")


func test_never_crushes() -> void:
	var room := await _enter()
	var p := room.player
	var s := _shutter(room)
	var input := _scripted(p)
	_breaker(room, "t_fb").trip()
	# Crouch in the column (176..192) before the drop.
	p.teleport(Vector2(184, 0))
	input.down_held = true
	await physics_frames(_frames(s.timing.open + s.timing.drop + s.timing.slot + s.timing.seal + 0.5))
	check(p.is_low, "Rook should be crouched in the column")
	check(s.state == PowerShutter.State.SEAL and s.is_holding(), "the seal should hold over Rook (%s)" % s.state_name())
	check(s.gap >= s.slot_gap() - 0.01, "held at slot height (gap %.1f)" % s.gap)
	check(p.combat.health == p.combat.config.max_health, "a held shutter deals no damage")
	# Crawl out east: the column clears and the seal finishes.
	input.move_x = 1
	await physics_frames(40)
	input.move_x = 0
	input.down_held = false
	await physics_frames(20)
	check(s.state == PowerShutter.State.CLOSED, "the shutter should seal once the column is clear (%s)" % s.state_name())
	check(p.global_position.x - 6.0 >= 192.0, "Rook crawled clear of the column (x %.1f)" % p.global_position.x)
	check(not Game.has_flag("t_latched"), "leaving on the side he came from is not a pass")
	check(p.combat.health == p.combat.config.max_health, "no damage from the shutter at any point")
	# A standing body in the column holds the drop at open height.
	Game.new_game()
	room = await _enter()
	p = room.player
	s = _shutter(room)
	_breaker(room, "t_fb").trip()
	p.teleport(Vector2(184, 0))
	await physics_frames(_frames(s.timing.open + s.timing.drop + 0.2))
	check(s.state == PowerShutter.State.DROP and s.is_holding() and is_equal_approx(s.gap, s.size.y),
		"a standing Rook holds the drop at open height (%s, gap %.0f)" % [s.state_name(), s.gap])


## A column that ends above the floor: the panel still reaches the floor, so
## the closed shutter blocks a crawl and the slot sits 24 px above the floor.
func test_floor_gap_column_still_seals() -> void:
	var room := await _enter()
	var p := room.player
	var s := PowerShutter.new()
	s.name = "Shutter_G"
	s.shutter_id = "G"
	s.circuit = &"t1"
	s.timing = load("res://data/level/shutter_run.tres") as ShutterTiming
	s.latch_flag = "t_gap_latched"
	s.size = Vector2(16, 176)
	s.position = Vector2(300, -200)  # column ends at -24: a 24 px floor gap
	room.add_child(s)
	await physics_frames(2)
	check_near(s.full_height(), 200.0, 0.01, "the panel travels down to the real floor")
	check(s.content_errors(room).is_empty(), "a 24 px floor gap validates: %s" % str(s.content_errors(room)))
	# Closed: a crouched crawl west from 340 stops at the panel.
	var input := _scripted(p)
	p.teleport(Vector2(340, 0))
	input.down_held = true
	await physics_frames(4)
	input.move_x = -1
	await physics_frames(90)
	input.move_x = 0
	check(p.is_low, "Rook crawled low")
	check(p.global_position.x - p.config.low_size.x * 0.5 >= 316.0 - 0.5, "a closed shutter blocks the crawl under a floor gap (x %.1f)" % p.global_position.x)
	input.down_held = false
	# In the slot the panel's bottom is slot_height above the floor (y -24).
	p.teleport(Vector2(380, 0))  # run-up room for the slide
	_breaker(room, "t_fb").trip()
	await physics_frames(_frames(s.timing.open + s.timing.drop + 0.05))
	check(s.state == PowerShutter.State.SLOT, "slot state expected, got %s" % s.state_name())
	check_near(s.global_position.y + s.full_height() - s.gap, -s.slot_height, 0.01, "the slot is measured from the floor")
	var bot := RouteBot.new(get_tree(), p)
	var ok: bool = await bot.run([["slide", 250]])
	check(ok and Game.has_flag("t_gap_latched"), "a slide passes the floor-gap slot and latches it (x %.0f, %s)" % [p.global_position.x, bot.failure])


func test_rearm_refreshes_timer() -> void:
	var room := await _enter()
	var s := _shutter(room)
	var fb := _breaker(room, "t_fb")
	fb.trip()
	await physics_frames(120)
	check_near(s.time_left(), s.timing.open - 2.0, 0.05, "two seconds into the countdown")
	check(fb.trip(), "a trip after rearm_time should count")
	await physics_frames(1)
	check_near(s.time_left(), s.timing.open, 0.05, "a second hit refreshes the countdown")
	check(s.state == PowerShutter.State.OPEN, "refresh keeps it OPEN (%s)" % s.state_name())
	check(trips.size() == 2, "each trip emits breaker_hit: %s" % str(trips))
	check(fb.is_lit(), "the breaker lamp is amber while its circuit is live")


func test_pass_margin_signal() -> void:
	var room := await _enter()
	var s := _shutter(room)
	_breaker(room, "t_fb").trip()
	await physics_frames(60)
	var bot := RouteBot.new(get_tree(), room.player)
	await bot.run([["run", 140]])
	check(passes.size() == 1 and passes[0][0] == "S", "one shutter_passed for S: %s" % str(passes))
	if passes.size() == 1:
		var m: float = passes[0][1]
		# About 1 s waited + ~0.3 s run: roughly 1.9 s of the 3.2 s left.
		check(m > 1.5 and m < s.timing.open - 1.0, "standing margin = open - t (got %.2f)" % m)
		check_near(s.pass_margin(), m, 0.0001, "pass_margin() matches the signal")


# --- Validator ----------------------------------------------------------------------

func test_validator_breaker_too_high_is_error() -> void:
	var v := ContentValidator.new().check_room(VALIDATOR_FIXTURE, false)
	var joined := "\n".join(v.errors)
	check(joined.contains("Breaker_v_high") and joined.contains("higher than"), "a breaker above floor -96 is an error: %s" % joined)
	check(not joined.contains("Breaker_v_orphan"), "a floor breaker at -40 is fine: %s" % joined)
	check(joined.contains("Shutter_V") and joined.contains("no latch_flag"), "a shutter without latch is an error: %s" % joined)
	check(joined.contains("Shutter_V") and joined.contains("above the floor"), "a shutter ending > 48 px above the floor is an error: %s" % joined)
	var warns := "\n".join(v.warnings)
	check(warns.contains("circuit:v_nobody"), "a circuit nothing consumes warns: %s" % warns)
	check(not joined.contains("circuit:v1"), "circuit v1 has a consumer: %s" % joined)
	# The real fixture: clean, except t2 (the high breaker) feeds nothing.
	var ok := ContentValidator.new().check_room(FIXTURE, false)
	check(ok.errors.is_empty(), "grid_shutter should validate: %s" % str(ok.errors))
	check("\n".join(ok.warnings).contains("circuit:t2"), "t2 has no consumer in the fixture: %s" % str(ok.warnings))
	check(ok.produced.has("t_latched") and ok.consumed.has("circuit:t1"), "shutter flags reach the flag graph")
	# Gate's open_flag does nothing on a shutter, so setting it is an error.
	var stub := Node2D.new()
	var s := PowerShutter.new()
	s.shutter_id = "O"
	s.open_flag = "some_flag"
	stub.add_child(s)
	check("\n".join(s.content_errors(stub)).contains("open_flag"), "open_flag on a PowerShutter is an error")
	stub.free()


## A high breaker beside (not above) a one-way at -72 still warns when Rook,
## standing at the one-way's end, reaches it with a grounded light swing
## (D2b: Warden Tower's first one-ways at 60..124 / 300..364 did).
func test_validator_breaker_beside_oneway_warns() -> void:
	var reach_x := Breaker.grounded_reach_x()
	check(reach_x > 30.0, "grounded reach past a platform end includes hitbox, lunge and half width (%.1f)" % reach_x)
	for case in [[60.0, true], [120.0, false]]:
		var room := Node2D.new()
		var floor_block := GrayboxBlock.new()
		floor_block.size = Vector2(512, 64)
		floor_block.position = Vector2(-48, 0)
		room.add_child(floor_block)
		var ow := GrayboxBlock.new()
		ow.name = "OneWay1"
		ow.one_way = true
		ow.size = Vector2(52, 8)
		ow.position = Vector2(case[0], -72)
		room.add_child(ow)
		var b := Breaker.new()
		b.breaker_id = "v_side"
		b.circuit = &"v_side"
		b.position = Vector2(36, -96)
		room.add_child(b)
		var warned := "\n".join(b.content_errors(room)).contains("grounded-attack reach of one-way OneWay1")
		check(warned == case[1], "breaker at 36..52 vs one-way from x %d: warn %s expected %s" % [case[0], warned, case[1]])
		room.free()


## The grid fixtures still match tools/roomgen/fixtures_grid.py (-B: no
## tracked __pycache__ churn). Skipped with a warning where python3 is
## absent; the gate also runs the script itself.
func test_fixtures_match_roomgen() -> void:
	var probe: Array = []
	if OS.execute("sh", ["-c", "command -v python3"], probe) != 0:
		push_warning("python3 not found: fixtures_grid.py --check not run here")
		return
	var out: Array = []
	var code := OS.execute("sh", ["-c", "cd '%s' && python3 -B tools/roomgen/fixtures_grid.py --check" % ProjectSettings.globalize_path("res://")], out, true)
	check(code == 0, "fixtures_grid.py --check reports drift: %s" % str(out))
