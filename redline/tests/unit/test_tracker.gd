extends RedlineTestCase
## M7/M3 CeilingTracker (the Collector eye, D-069) on tests/fixtures/
## tracker_rail.tscn (tools/roomgen/fixtures_tracker.py): rail 720..1620 at
## y -350, wake 740, lost 1780, a sealed block 1640..1760 (y -380..-24).
## Timing reference: running from 100, the eye tracks from t 5.07 s; a Rook
## stopped at 1200 sees it reach the cone edge ~1.8 s later, the lock ~1.0 s
## after that and the bolt 0.6 s later. Tests wait for the eye, never count
## from EMERGE.

const FIXTURE := "res://tests/fixtures/tracker_rail.tscn"
const EYE_SCENE := preload("res://world/props/CollectorEye.tscn")
const CONFIG_PATH := "res://data/props/collector_eye.tres"
## The sealed block leaves a 24 px slot at the floor, so crossing it is a
## slide; everything else is a plain run.
const EAST_ROUTE := [["run", 1560], ["slide", 1790], ["run", 1900]]
const WEST_ROUTE := [["run", 1840], ["slide", 1610], ["run", 100]]

var root: Node2D
var locked: Array = []
var perfect: Array = []
var enemy_hits: Array = []


func before_each() -> void:
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	Game.new_game()
	locked.clear()
	perfect.clear()
	enemy_hits.clear()
	EventBus.tracker_locked.connect(_on_locked)
	EventBus.perfect_dodge.connect(_on_perfect)
	EventBus.enemy_damaged.connect(_on_enemy_damaged)


func after_each() -> void:
	EventBus.tracker_locked.disconnect(_on_locked)
	EventBus.perfect_dodge.disconnect(_on_perfect)
	EventBus.enemy_damaged.disconnect(_on_enemy_damaged)
	SceneRouter.current_room = null
	SceneRouter.world_root = null
	root.queue_free()
	Game.new_game()
	await physics_frames(2)


func _on_locked(id: String) -> void:
	locked.append(id)


func _on_perfect(attacker: Node2D) -> void:
	perfect.append(attacker)


func _on_enemy_damaged(_enemy: Node2D, _hit: HitInfo, _result: int) -> void:
	enemy_hits.append(1)


func _enter(entry: StringName) -> Room:
	SceneRouter.goto_room(FIXTURE, entry)
	await physics_frames(10)
	return SceneRouter.current_room as Room


func _eye(room: Room) -> CeilingTracker:
	return room.find_child("CollectorEye", true, false) as CeilingTracker


## Samples the eye every physics frame into `seen` (max x, states seen): a
## Dictionary the caller owns, because lambdas capture locals by value.
func _watch(eye: CeilingTracker, seen: Dictionary) -> Callable:
	seen["max_x"] = -INF
	seen["states"] = []
	var cb := func() -> void:
		if not is_instance_valid(eye):
			return
		seen["max_x"] = maxf(float(seen["max_x"]), eye.position.x)
		var sname := eye.state_name()
		if not (seen["states"] as Array).has(sname):
			(seen["states"] as Array).append(sname)
	get_tree().physics_frame.connect(cb)
	return cb


## Records every eye bolt spawned into the room; `attackers` gets each bolt's
## attacker at spawn time (the bolt itself may be freed by the time we look).
func _count_bolts(room: Room, bolts: Array, attackers: Array = []) -> Callable:
	var cb := func(n: Node) -> void:
		if n is Projectile and (n as Projectile).attack != null and (n as Projectile).attack.id == &"collector_eye_bolt":
			bolts.append(n)
			attackers.append((n as Projectile).attacker)
	room.child_entered_tree.connect(cb)
	return cb


## Waits until `cond` holds, at most `max_frames`. Returns the frames waited,
## or -1 on timeout.
func _wait_until(cond: Callable, max_frames: int) -> int:
	for f in max_frames:
		if cond.call():
			return f
		await physics_frames(1)
	return -1 if not cond.call() else max_frames


func test_running_never_locks() -> void:
	var room := await _enter(&"start")
	var eye := _eye(room)
	check(eye != null, "fixture has no CollectorEye")
	if eye == null:
		return
	var seen := {}
	var cb := _watch(eye, seen)
	var bolts: Array = []
	var bcb := _count_bolts(room, bolts)
	var bot := RouteBot.new(get_tree(), room.player)
	var ok: bool = await bot.run(EAST_ROUTE)
	await physics_frames(30)
	get_tree().physics_frame.disconnect(cb)
	room.child_entered_tree.disconnect(bcb)
	check(ok, "run to 1900 failed: %s" % bot.failure)
	check((seen["states"] as Array).has("TRACK"), "the eye should have woken and tracked: %s" % str(seen["states"]))
	check(not (seen["states"] as Array).has("LOCK") and eye.lock_count == 0, "a running Rook must never be locked: %s" % str(seen["states"]))
	check(bolts.is_empty() and locked.is_empty(), "no bolt may fire at a running Rook")
	check(float(seen["max_x"]) <= 1620.0, "the eye left its rail: max x %.1f" % float(seen["max_x"]))


func test_standing_locks_once() -> void:
	var room := await _enter(&"start")
	var eye := _eye(room)
	var bolts: Array = []
	var attackers: Array = []
	var bcb := _count_bolts(room, bolts, attackers)
	var bot := RouteBot.new(get_tree(), room.player)
	var ok: bool = await bot.run([["run", 1200]])
	check(ok, "run to 1200 failed: %s" % bot.failure)
	var p := room.player
	var half := eye.config.cone_half_width
	# Wait for the eye itself (~1.8 s after the stop), not a count from EMERGE.
	var waited := await _wait_until(func() -> bool: return absf(eye.position.x - p.global_position.x) <= half, 150)
	check(waited >= 0, "the eye never reached the cone edge within 2.5 s (at %.1f, Rook %.1f)" % [eye.position.x, p.global_position.x])
	check(waited >= 60, "the eye reached Rook too early (%d frames after the stop): running must outpace it" % waited)
	await physics_frames(int(round((eye.config.lock_time + eye.config.windup + 0.1) * 60.0)))
	check(eye.lock_count == 1, "standing in the cone should lock exactly once (got %d)" % eye.lock_count)
	check(bolts.size() == 1 and eye.bolts_fired == 1, "exactly one bolt should fire (got %d)" % bolts.size())
	check(locked == ["collector_eye"], "tracker_locked should fire once with the tracker id: %s" % str(locked))
	# The bolt from the real LOCK path is the dodgeable one the dodge tests
	# fire by hand: same attacker, same attack.
	check(attackers.size() == 1 and attackers[0] == eye, "the LOCK bolt's attacker should be the eye: %s" % str(attackers))
	# Keep standing through the cooldown (minus a frame's margin): no second lock.
	await physics_frames(int(round((eye.config.cooldown - 0.1) * 60.0)))
	room.child_entered_tree.disconnect(bcb)
	check(eye.lock_count == 1 and bolts.size() == 1, "cooldown should block a second lock (locks %d, bolts %d)" % [eye.lock_count, bolts.size()])


## Stop 0.8 s *under the eye* (its lock already building), then run on: the
## lock must bleed off and never fire. Standing builds the lock; moving drains
## it (TrackerConfig.still_speed / move_drain), because at 150 vs 110 px/s a
## centred Rook needs ~0.8 s just to run out of the cone.
func test_short_stops_are_free() -> void:
	var room := await _enter(&"start")
	var eye := _eye(room)
	var bot := RouteBot.new(get_tree(), room.player)
	var ok: bool = await bot.run([["run", 1200]])
	check(ok, "run to 1200 failed: %s" % bot.failure)
	var waited := await _wait_until(func() -> bool: return eye.lock_timer > 0.0, 180)
	check(waited >= 0, "the eye never got over Rook (at %.1f, Rook %.1f)" % [eye.position.x, room.player.global_position.x])
	await physics_frames(48)
	var peak := eye.lock_timer
	check(peak >= 0.7 and eye.state == CeilingTracker.State.TRACK, "0.8 s under the eye should build ~0.8 s of lock (%.2f, %s)" % [peak, eye.state_name()])
	var trace := {"peak": peak, "reset": false}
	var cb := func() -> void:
		trace["peak"] = maxf(float(trace["peak"]), eye.lock_timer)
		if eye.lock_timer == 0.0:
			trace["reset"] = true
	get_tree().physics_frame.connect(cb)
	ok = await bot.run(EAST_ROUTE)
	await physics_frames(30)
	get_tree().physics_frame.disconnect(cb)
	check(ok, "route on failed: %s" % bot.failure)
	check(float(trace["peak"]) < eye.config.lock_time, "the lock kept building after he moved on (peak %.2f)" % float(trace["peak"]))
	check(bool(trace["reset"]), "the lock timer should drain back to 0 once he moves on")
	check(eye.lock_count == 0 and locked.is_empty(), "a 0.8 s stop under the eye must not lock (locks %d)" % eye.lock_count)


func test_block_breaks_line_of_sight() -> void:
	var room := await _enter(&"start")
	var eye := _eye(room)
	# Direct probe: a chest in the cone's reach but behind the sealed block.
	check(eye.has_line_of_sight_to(Vector2(1200, -20)), "open floor should be in sight")
	eye.position.x = 1620.0
	check(not eye.has_line_of_sight_to(Vector2(1652, -20)), "the sealed block must break the line")
	eye.position.x = 720.0
	var bot := RouteBot.new(get_tree(), room.player)
	var ok: bool = await bot.run([["run", 1560], ["slide", 1642]])
	check(ok, "route under the block failed: %s" % bot.failure)
	var p := room.player
	var input := ScriptedInputSource.new()
	p.input_source = input
	input.down_held = true
	# Crawl to x 1645..1649: under the block, yet within the cone's width of
	# the eye parked at the rail end (1620).
	for f in 120:
		var x := p.global_position.x
		input.move_x = -1 if x > 1649.0 else (1 if x < 1645.0 else 0)
		if input.move_x == 0:
			break
		await physics_frames(1)
	input.move_x = 0
	await physics_frames(240)
	var dx := absf(eye.position.x - p.global_position.x)
	check(p.global_position.x > 1640.0, "Rook should be under the block (at %.1f)" % p.global_position.x)
	check(dx <= eye.config.cone_half_width, "precondition: Rook within the cone's width (dx %.1f)" % dx)
	check(eye.lock_count == 0 and locked.is_empty(), "no lock through the sealed block (state %s, locks %d)" % [eye.state_name(), eye.lock_count])


func test_retracts_after_lost_x() -> void:
	var room := await _enter(&"start")
	var eye := _eye(room)
	var bot := RouteBot.new(get_tree(), room.player)
	var ok: bool = await bot.run(EAST_ROUTE)
	check(ok, "run to 1900 failed: %s" % bot.failure)
	var waited := await _wait_until(func() -> bool: return eye.state == CeilingTracker.State.GONE, 180)
	check(waited >= 0, "the eye should retract once Rook is past lost_x (state %s)" % eye.state_name())
	var seen := {}
	var cb := _watch(eye, seen)
	ok = await bot.run([["run", 1840], ["slide", 1610], ["run", 1000], ["wait", 180], ["run", 100]])
	get_tree().physics_frame.disconnect(cb)
	check(ok, "walk back failed: %s" % bot.failure)
	check(seen["states"] == ["GONE"], "a retracted eye never re-emerges: %s" % str(seen["states"]))
	check(eye.lock_count == 0 and eye.bolts_fired == 0, "a retracted eye never fires")


func test_visible_when_defeated_frees() -> void:
	var eye := EYE_SCENE.instantiate() as CeilingTracker
	eye.visible_when = "!flag:collector_drone_defeated"
	root.add_child(eye)
	await physics_frames(1)
	check(is_instance_valid(eye) and not eye.is_queued_for_deletion(), "the eye should exist before the boss dies")
	Game.set_flag("collector_drone_defeated")
	var later := EYE_SCENE.instantiate() as CeilingTracker
	later.visible_when = "!flag:collector_drone_defeated"
	root.add_child(later)
	await physics_frames(1)
	check(not is_instance_valid(later), "the eye should free itself once collector_drone_defeated is set")
	check(eye.content_flags() == {"conditions": ["!flag:collector_drone_defeated"]}, "content_flags should consume visible_when")


## Fires the eye's bolt straight down from rail height at a Rook standing
## against the west wall, then dodges into the wall just before it lands. The
## wall pins him, so the hurtbox stays under the bolt while the i-frames run
## (a free sideways dodge simply leaves the path: also no damage, but no
## perfect credit to test). Same attack, projectile and attacker as in play.
func _dodge_the_bolt(room: Room) -> Array:
	var eye := _eye(room)
	var p := room.player
	eye.set_physics_process(false)
	p.teleport(Vector2(-40, 0))
	var input := ScriptedInputSource.new()
	p.input_source = input
	await physics_frames(10)
	eye.position.x = p.global_position.x
	var bolts: Array = []
	var bcb := _count_bolts(room, bolts)
	eye.fire_bolt()
	room.child_entered_tree.disconnect(bcb)
	var results: Array = []
	check(bolts.size() == 1, "fire_bolt should spawn one projectile")
	if bolts.is_empty():
		return results
	var bolt := bolts[0] as Projectile
	check(bolt.attacker == eye, "the tracker node owns its bolt")
	bolt.impacted.connect(func(r: int) -> void: results.append(r))
	# Dodge ~3 frames before the bolt reaches the top of his hurtbox (34 px):
	# contact lands inside the dodge's perfect window.
	var waited := await _wait_until(func() -> bool:
		return not is_instance_valid(bolt) or bolt.global_position.y >= p.global_position.y - 34.0 - 8.0, 180)
	check(waited >= 0 and is_instance_valid(bolt), "the bolt never got close to Rook")
	input.move_x = -1
	input.press_dodge()
	await physics_frames(30)
	input.move_x = 0
	return results


func test_bolt_is_dodgeable() -> void:
	var room := await _enter(&"start")
	var hp := room.player.combat.health
	var results: Array = await _dodge_the_bolt(room)
	check(results == [CombatResult.PERFECT_EVADE], "the bolt should resolve as a perfect evade: %s" % str(results))
	check(room.player.combat.health == hp, "a perfect dodge through the bolt takes no damage (hp %d -> %d)" % [hp, room.player.combat.health])
	check(perfect.size() == 1, "the dodge should count as perfect (%d)" % perfect.size())


func test_perfect_dodge_on_bolt_credits_core_only() -> void:
	var room := await _enter(&"start")
	var p := room.player
	p.reactor.charge = 0.0
	var eye := _eye(room)
	await _dodge_the_bolt(room)
	check(perfect.size() == 1 and perfect[0] == eye, "perfect_dodge should report the tracker node: %s" % str(perfect))
	check_near(p.reactor.charge, p.reactor.config.perfect_dodge_gain * p.reactor.config.gain_multiplier * (1.0 + Game.circuit_value(&"full_health_reactor_bonus")),
		0.01, "the Core should gain exactly the perfect-dodge amount")
	check(enemy_hits.is_empty(), "the eye is no enemy: no enemy_damaged")


func test_spawn_past_lost_x_is_gone() -> void:
	# Load by hand so the history starts before the eye's first physics frame.
	var room := SceneRouter.goto_room(FIXTURE, &"east") as Room
	var eye := _eye(room)
	check(eye != null, "fixture has no CollectorEye")
	if eye == null:
		return
	var history := {"states": [], "visible": false}
	var hcb := func() -> void:
		if not is_instance_valid(eye):
			return
		(history["states"] as Array).append(eye.state_name())
		if eye.visible:
			history["visible"] = true
	get_tree().physics_frame.connect(hcb)
	await physics_frames(3)
	# GONE from the eye's first physics frame (the first sample; allow one
	# pre-tick DORMANT sample in case the signal ever lands before the tick).
	var first: Array = (history["states"] as Array).slice(0, 2)
	check(first == ["GONE", "GONE"] or first == ["DORMANT", "GONE"], "a Rook spawned past lost_x sends the eye to GONE on frame 1: %s" % str(history["states"]))
	var bot := RouteBot.new(get_tree(), room.player)
	var ok: bool = await bot.run(WEST_ROUTE)
	await physics_frames(60)
	get_tree().physics_frame.disconnect(hcb)
	check(ok, "walk west failed: %s" % bot.failure)
	var states := history["states"] as Array
	check(not states.has("EMERGE") and not states.has("TRACK"), "the eye must never emerge (so no gate sfx): %s" % str(states.slice(0, 6)))
	check(not bool(history["visible"]), "the eye must never be visible")
	check(eye.bolts_fired == 0 and locked.is_empty(), "the eye must never fire")


func test_config_validate_rules() -> void:
	var cfg := load(CONFIG_PATH) as TrackerConfig
	check(cfg != null and cfg.validate().is_empty(), "collector_eye.tres should validate: %s" % (str(cfg.validate()) if cfg else "missing"))
	check(cfg.attack != null and cfg.attack.id == &"collector_eye_bolt" and cfg.attack.validate().is_empty(), "the bolt AttackData should validate")
	check(cfg.attack.projectile.speed == 150.0 and cfg.attack.projectile.lifetime == 2.4 and cfg.attack.damage == 1.0, "bolt numbers")
	var bad := {"lock_time": 0.5, "windup": 0.2, "speed": 150.0, "cooldown": 0.9, "attack": null,
		"still_speed": 0.0, "move_drain": 0.5}
	for key: String in bad:
		var c := cfg.duplicate() as TrackerConfig
		c.set(key, bad[key])
		check(not c.validate().is_empty(), "%s = %s should fail validate()" % [key, str(bad[key])])
	# Content protocol on the node.
	var eye := EYE_SCENE.instantiate() as CeilingTracker
	eye.rail_min = 720
	eye.rail_max = 1620
	eye.wake_x = 740
	eye.lost_x = 1780
	check(eye.content_errors(null).is_empty(), "a sound rail should lint clean: %s" % str(eye.content_errors(null)))
	eye.wake_x = 900
	check(eye.content_errors(null).size() == 1, "wake_x past rail_min + 64 should be an error")
	eye.wake_x = 740
	eye.lost_x = 1600
	check(eye.content_errors(null).size() == 1, "lost_x inside the rail should be an error")
	eye.lost_x = 1780
	eye.rail_max = 700
	check(eye.content_errors(null).size() >= 1, "rail_min >= rail_max should be an error")
	eye.config = null
	eye.rail_max = 1620
	check(eye.content_errors(null).size() == 1, "a missing config should be an error")
	eye.free()
	var v := ContentValidator.new().check_room(FIXTURE, false)
	for e in v.errors:
		check(not e.contains("CollectorEye"), "fixture eye should validate clean: %s" % e)


func test_roomgen_fixture_matches() -> void:
	var probe: Array = []
	if OS.execute("sh", ["-c", "command -v python3"], probe) != 0:
		push_warning("python3 not found: fixtures_tracker.py --check not run here (it is part of the gate)")
		return
	var out: Array = []
	var code := OS.execute("sh", ["-c", "cd '%s' && python3 -B tools/roomgen/fixtures_tracker.py --check" % ProjectSettings.globalize_path("res://")], out, true)
	check(code == 0, "fixtures_tracker.py --check reports drift: %s" % str(out))
