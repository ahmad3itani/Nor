extends RedlineTestCase
## M7 chase set piece (ChaseDirector + Pursuer, D-073) on tests/fixtures/
## chase_flat.tscn (tools/roomgen/fixtures_chase.py): a flat line with a pit
## at x 900..990, path (0,0)->(1700,0), start_area 360..440 holding the
## `start` spawn (400), CP1 380, CP2 1040, end_area 1560..1600, `east` spawn
## at 1680 and `west` at 100. Data: data/world/chase/test_chase.tres
## (base 105 px/s, start_lead 220, warn 0.5 s, respawn_lead 220, regroup 1 s,
## catch 36x64 with its bottom at y 8).

const FIXTURE := "res://tests/fixtures/chase_flat.tscn"
const RAINLINE := "res://data/world/chase/rainline.tres"
const TEST_DATA := "res://data/world/chase/test_chase.tres"
## The fixture route from CP1 (or the start spawn) to the end area.
const RUN_TO_END := [["run", 880], ["runjump", 900, 1010], ["run", 1580]]

var root: Node2D
var started: Array = []
var caught: Array = []
var completed: Array = []
var hints: Array = []
var order: Array = []


func before_each() -> void:
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	Game.new_game()
	started.clear()
	caught.clear()
	completed.clear()
	hints.clear()
	order.clear()
	EventBus.chase_started.connect(_on_started)
	EventBus.chase_caught.connect(_on_caught)
	EventBus.chase_completed.connect(_on_completed)
	EventBus.hint_requested.connect(_on_hint)


func after_each() -> void:
	EventBus.chase_started.disconnect(_on_started)
	EventBus.chase_caught.disconnect(_on_caught)
	EventBus.chase_completed.disconnect(_on_completed)
	EventBus.hint_requested.disconnect(_on_hint)
	SceneRouter.current_room = null
	SceneRouter.world_root = null
	root.queue_free()
	Game.new_game()
	await physics_frames(2)


func _on_started(id: String) -> void:
	var d := _director()
	started.append({"id": id, "frame": Engine.get_physics_frames(), "pp": d.pursuer_progress if d else -1.0})
	order.append("started")


func _on_caught(id: String, cp: int) -> void:
	var d := _director()
	var room := SceneRouter.current_room as Room
	caught.append({"id": id, "cp": cp, "frame": Engine.get_physics_frames(), "pp": d.pursuer_progress if d else -1.0,
		"x": room.player.global_position.x if room else -1.0, "hp": room.player.combat.health if room else -1,
		"source": room.player.combat.last_damage_source if room else ""})
	order.append("caught")


func _on_completed(id: String, seconds: float, catches: int, min_lead: float) -> void:
	var d := _director()
	completed.append({"id": id, "seconds": seconds, "catches": catches, "min_lead": min_lead,
		"flag_set": Game.has_flag(d.done_flag()) if d else false})
	order.append("completed")


func _on_hint(text: String, _seconds: float) -> void:
	hints.append(text)


## Loads the fixture without waiting: the chase may arm on the next frame.
func _load(entry: StringName) -> Room:
	var room := SceneRouter.goto_room(FIXTURE, entry) as Room
	room.player.input_source = ScriptedInputSource.new()
	return room


func _director() -> ChaseDirector:
	var room := SceneRouter.current_room
	if room == null or not is_instance_valid(room):
		return null
	return room.find_child("Chase_test", true, false) as ChaseDirector


func _wait_until(cond: Callable, max_frames: int) -> int:
	for f in max_frames:
		if cond.call():
			return f
		await physics_frames(1)
	return max_frames if cond.call() else -1


func _pursuers(room: Node) -> Array:
	var out: Array = []
	for n in room.find_children("*", "", true, false):
		if n is Pursuer:
			out.append(n)
	return out


# --- Data ------------------------------------------------------------------------

func test_data_validate_rules() -> void:
	var d := PursuerData.new()
	d.id = "x"
	check(d.validate().is_empty(), "default PursuerData should validate: %s" % str(d.validate()))
	d.base_speed = 150.0
	var errs := d.validate()
	check(errs.size() == 1 and errs[0].contains("base_speed"), "base_speed 150 must be an error: %s" % str(errs))
	d.base_speed = 125.0
	d.catchup_speed = 181.0
	check(not d.validate().is_empty(), "catchup_speed > 180 must be an error")
	d.catchup_speed = 165.0
	d.warn_time = 0.2
	check(not d.validate().is_empty(), "warn_time < 0.3 must be an error")
	d.warn_time = 1.2
	d.start_lead = d.near_lead + 63.0
	check(not d.validate().is_empty(), "start_lead < near_lead + 64 must be an error")
	d.start_lead = 380.0
	d.respawn_lead = 150.0
	check(not d.validate().is_empty(), "respawn_lead < 160 must be an error")
	d.respawn_lead = 260.0
	d.regroup_time = 0.4
	check(not d.validate().is_empty(), "regroup_time < 0.5 must be an error")
	d.regroup_time = 1.0
	d.catch_size = Vector2(0, 64)
	check(not d.validate().is_empty(), "a zero catch_size must be an error")
	for path in [RAINLINE, TEST_DATA]:
		var res := load(path) as PursuerData
		check(res != null and res.validate().is_empty(), "%s should validate clean: %s" % [path, str(res.validate()) if res else "missing"])
	var rainline := load(RAINLINE) as PursuerData
	check(rainline.derail_x == 3560.0, "rainline derails at its buffer stop x 3560")


func test_catchup_blend() -> void:
	var d := load(TEST_DATA) as PursuerData
	check_near(d.speed_at(0.0), 105.0, 0.001, "base speed at a short lead")
	check_near(d.speed_at(300.0), 105.0, 0.001, "base speed at far_lead")
	check_near(d.speed_at(332.0), 127.5, 0.001, "halfway through the 64 px blend")
	check_near(d.speed_at(364.0), 150.0, 0.001, "catchup at far_lead + 64")
	check_near(d.speed_at(900.0), 150.0, 0.001, "catchup beyond the blend")
	check_near(d.speed_at(100.0, 0.5), 52.5, 0.001, "segment speed_scale applies to the base speed")
	check_near(d.speed_at(364.0, 0.5), 150.0, 0.001, "catchup is not scaled")


# --- Schedule, catches, grace ------------------------------------------------------

func test_idle_player_is_caught_on_schedule() -> void:
	var room := _load(&"start")
	var f0 := Engine.get_physics_frames()
	var p := room.player
	var waited := await _wait_until(func() -> bool: return not caught.is_empty(), 240)
	check(waited >= 0, "an idle Rook was never caught")
	check(started.size() == 1, "chase_started should fire once, got %d" % started.size())
	if started.is_empty() or caught.is_empty():
		return
	check(int(started[0]["frame"]) - f0 <= 1, "WARN should start on the first frame (started %d frames in)" % (int(started[0]["frame"]) - f0))
	check_near(float(started[0]["pp"]), 180.0, 0.5, "the pursuer starts start_lead (220) behind Rook at 400")
	var t := float(int(caught[0]["frame"]) - int(started[0]["frame"])) / 60.0
	check_near(t, 0.5 + (400.0 - 6.0 - 18.0 - 180.0) / 105.0, 3.0 / 60.0, "first catch time after WARN")
	check(int(caught[0]["hp"]) == 4 and p.combat.health == 4, "a catch costs one pip (5 -> 4), got %d" % p.combat.health)
	check_near(p.global_position.x, 380.0, 0.5, "Rook restarts at CP1")
	check(int(caught[0]["cp"]) == 0, "checkpoint index 0 (CP1)")
	var d := _director()
	check_near(d.pursuer_progress, 160.0, 0.5, "the pursuer restarts respawn_lead (220) behind CP1")
	check(d.catches == 1, "catches == 1, got %d" % d.catches)
	check(String(caught[0]["source"]) == "chase/test", "catch damage source 'chase/test', got %s" % caught[0]["source"])
	check(p.last_safe_position.is_equal_approx(Vector2(380, 0)), "last_safe_position moves to the checkpoint")


func test_catch_is_never_lethal() -> void:
	var room := _load(&"start")
	await physics_frames(2)
	var p := room.player
	p.combat.health = 1
	var waited := await _wait_until(func() -> bool: return caught.size() >= 6, 1500)
	check(waited >= 0, "six catches expected, got %d" % caught.size())
	check(not p.combat.dead and p.combat.health == 1, "catches at 1 pip must never kill (health %d, dead %s)" % [p.combat.health, p.combat.dead])
	# A damage-taken x2 circuit still cannot turn a catch into a death.
	Game.grant_circuit("glass_pulse")
	check(Game.toggle_circuit("glass_pulse"), "could not equip glass_pulse (damage_taken x2)")
	p.combat.health = 2
	var before := caught.size()
	waited = await _wait_until(func() -> bool: return caught.size() > before, 400)
	check(waited >= 0, "no catch with the circuit equipped")
	check(not p.combat.dead and p.combat.health == 1, "x2 damage at 2 pips must end at 1, got %d" % p.combat.health)


func test_regroup_grace() -> void:
	var room := _load(&"start")
	var p := room.player
	await _wait_until(func() -> bool: return not caught.is_empty(), 240)
	var d := _director()
	check(d.state == ChaseDirector.State.REGROUP, "a catch starts the regroup grace, state %s" % d.state_name())
	var hold := d.pursuer_progress
	# Stand right on the pursuer: no catch while the grace runs, and it holds.
	p.teleport(d.to_global(Vector2(170, 0)))
	await physics_frames(int(d.data.regroup_time * 60.0) - 4)
	check(caught.size() == 1, "no catch during the grace, got %d" % caught.size())
	check_near(d.pursuer_progress, hold, 0.01, "the pursuer holds during the grace")
	var waited := await _wait_until(func() -> bool: return caught.size() >= 2, 10)
	check(waited >= 0, "Rook overlapping the pursuer is caught once the grace ends")


func test_pit_during_chase_returns_to_checkpoint() -> void:
	var room := _load(&"start")
	var p := room.player
	var input := p.input_source as ScriptedInputSource
	input.move_x = 1
	var waited := await _wait_until(func() -> bool: return not caught.is_empty(), 600)
	input.move_x = 0
	check(waited >= 0, "running into the pit should be handled as a chase catch")
	if caught.is_empty():
		return
	var c: Dictionary = caught[0]
	check(String(c["source"]) == "pit", "pit catches use source 'pit', got %s" % c["source"])
	check(int(c["hp"]) == 4, "a pit during the chase costs one pip, health %d" % int(c["hp"]))
	check_near(float(c["x"]), 380.0, 0.5, "the pit returns Rook to CP1, not his last safe ground")
	check_near(float(c["pp"]), 160.0, 0.5, "the pursuer restarts behind CP1")
	check(int(c["cp"]) == 0, "CP1 is index 0")
	check(not p.combat.dead, "a chase pit is never lethal")


func test_end_sets_flag_immediately_and_reload_skips_chase() -> void:
	var room := _load(&"start")
	var bot := RouteBot.new(get_tree(), room.player)
	var ok: bool = await bot.run(RUN_TO_END)
	check(ok, "route to the end failed: %s" % bot.failure)
	check(completed.size() == 1, "chase_completed once, got %d" % completed.size())
	if completed.is_empty():
		return
	check(bool(completed[0]["flag_set"]), "the done flag must be set when chase_completed fires")
	check(int(completed[0]["catches"]) == 0, "a clean run has 0 catches")
	check(is_finite(float(completed[0]["min_lead"])) and float(completed[0]["min_lead"]) > 0.0, "min_lead is reported")
	check(Game.has_flag("chase_test_done"), "chase_test_done is set")
	check(not room.pit_override.is_valid(), "the pit override is cleared at the end")
	var d := _director()
	# The pursuer turns harmless, runs out and derails, then frees itself.
	var gone := await _wait_until(func() -> bool: return _pursuers(room).is_empty(), 600)
	check(gone >= 0, "the pursuer should derail and free itself after the end")
	check(caught.is_empty(), "no catch after the end")
	check(d.state == ChaseDirector.State.DONE, "director DONE after the derail, got %s" % d.state_name())
	# Reload: only the flag persists, and it skips the whole set piece.
	room = _load(&"start")
	await physics_frames(90)
	check(_pursuers(room).is_empty(), "no Pursuer after the chase is done")
	check(not room.pit_override.is_valid(), "no pit override after the chase is done")
	check(started.size() == 1, "the chase must not arm again, started %d" % started.size())
	check(_director().state == ChaseDirector.State.DONE, "reloaded director is DONE")


func test_catch_happens_on_screen() -> void:
	var room := _load(&"start")
	var views: Array = []
	var on_damage := func(_amount: int, _hp: int) -> void:
		var d := _director()
		views.append(d.view_rect().intersects(d.pursuer_rect()) and d.view_rect().has_point(d.point_at(d.pursuer_progress)))
	EventBus.player_damaged.connect(on_damage)
	await _wait_until(func() -> bool: return caught.size() >= 2, 600)
	EventBus.player_damaged.disconnect(on_damage)
	check(views.size() >= 2, "expected two catches, got %d" % views.size())
	check(not views.has(false), "the pursuer must be in view at every catch: %s" % str(views))
	check(room.player.combat.health == 3, "two catches cost two pips")


func test_signals_order() -> void:
	var room := _load(&"start")
	await _wait_until(func() -> bool: return not caught.is_empty(), 240)
	var bot := RouteBot.new(get_tree(), room.player)
	var ok: bool = await bot.run(RUN_TO_END)
	check(ok, "route to the end after a catch failed: %s" % bot.failure)
	check(order == ["started", "caught", "completed"], "signal order: %s" % str(order))
	if completed.size() == 1:
		check(int(completed[0]["catches"]) == 1, "completed reports one catch")
		check(float(completed[0]["seconds"]) > 2.0, "completed reports the chase time")
	for list in [started, caught, completed]:
		for e in list:
			check(String(e["id"]) == "test", "signals carry the chase id")


# --- Arming rule ------------------------------------------------------------------

func test_arming_rule() -> void:
	# (a) Spawned inside start_area: WARN on the first frame.
	var room := _load(&"start")
	await physics_frames(2)
	check(started.size() == 1 and _director().state == ChaseDirector.State.WARN, "spawning inside start_area arms at once")
	# (b) Die, respawn west of start_area (the last Anchor points there), walk in east.
	Game.state.last_anchor_room = FIXTURE
	Game.state.last_anchor_id = "west"
	room.player.combat.take_damage(99, Vector2.ZERO, 0.0, false, "test")
	# Compare instance ids: the old room is freed while we wait.
	var old_id := room.get_instance_id()
	var waited := await _wait_until(func() -> bool:
		var cur := SceneRouter.current_room
		return is_instance_valid(cur) and cur.get_instance_id() != old_id and not SceneRouter.transitioning, 300)
	check(waited >= 0, "death should reload the fixture at 'west'")
	room = SceneRouter.current_room as Room
	await physics_frames(10)
	check_near(room.player.global_position.x, 100.0, 1.0, "respawned at west")
	check(started.size() == 1 and _director().state == ChaseDirector.State.IDLE, "respawning west of start_area stays IDLE")
	var bot := RouteBot.new(get_tree(), room.player)
	check(await bot.run([["run", 420]]), "walk east failed: %s" % bot.failure)
	check(started.size() == 2 and _director().is_active(), "walking east into start_area arms the chase")
	# (c) From the far end: walking west through start_area never arms it.
	started.clear()
	room = _load(&"east")
	var d := _director()
	var moved: Array = [false]
	var watch := func() -> void:
		if is_instance_valid(d) and d.pursuer_progress != 0.0:
			moved[0] = true
	get_tree().physics_frame.connect(watch)
	bot = RouteBot.new(get_tree(), room.player)
	var ok: bool = await bot.run([["run", 1000], ["runjump", 994, 880], ["run", 100]])
	get_tree().physics_frame.disconnect(watch)
	check(ok, "walk west failed: %s" % bot.failure)
	check(started.is_empty() and d.state == ChaseDirector.State.IDLE, "walking west through start_area must stay IDLE (%s)" % d.state_name())
	check(not moved[0], "the parked pursuer must not move while IDLE")
	check(caught.is_empty(), "no catches while IDLE")
	# Then east again into start_area: it arms normally.
	check(await bot.run([["run", 420]]), "walk back east failed: %s" % bot.failure)
	check(started.size() == 1 and d.is_active(), "re-entering start_area moving east arms the chase")


func test_end_ignored_in_idle() -> void:
	var room := _load(&"east")
	var bot := RouteBot.new(get_tree(), room.player)
	var ok: bool = await bot.run([["run", 1000]])
	check(ok, "walk west failed: %s" % bot.failure)
	check(not Game.has_flag("chase_test_done"), "crossing end_area while IDLE must not set the done flag")
	check(completed.is_empty() and started.is_empty(), "no chase signals while IDLE")
	check(_director().state == ChaseDirector.State.IDLE, "still IDLE")


func test_warn_hint_once_per_load() -> void:
	var room := _load(&"start")
	await _wait_until(func() -> bool: return caught.size() >= 2, 600)
	var d := _director()
	var warn := hints.filter(func(h: String) -> bool: return h == d.data.warn_hint)
	var repeat := hints.filter(func(h: String) -> bool: return h == d.data.repeat_hint)
	check(warn.size() == 1, "warn_hint exactly once across two catches, got %d" % warn.size())
	check(repeat.size() == 1, "repeat_hint once after the 2nd catch, got %d" % repeat.size())
	check(room.player.combat.health == 3, "two catches")


func test_debug_overlay_draws() -> void:
	# The HitboxView hook and the telegraph overlay run without errors while
	# the chase is live (drawing is exercised, not pixel-checked).
	var room := _load(&"start")
	var view := HitboxView.new()
	root.add_child(view)
	await physics_frames(60)
	for i in 3:
		await get_tree().process_frame
	check(_director().is_active(), "chase should be live")
	check(not _pursuers(room).is_empty(), "the pursuer exists while the chase runs")
	view.queue_free()


# --- Content protocol ---------------------------------------------------------------

func test_content_protocol() -> void:
	var v := ContentValidator.new().check_room(FIXTURE, false)
	var mine := Array(v.errors).filter(func(e: String) -> bool: return e.contains("Chase_test"))
	check(mine.is_empty(), "the fixture's director should lint clean: %s" % str(mine))
	check(v.produced.has("chase_test_done"), "content_flags produces the done flag")
	# Break it on purpose: every rule reports.
	var room := (load(FIXTURE) as PackedScene).instantiate() as Room
	var dir := room.find_child("Chase_test", true, false) as ChaseDirector
	dir.position = Vector2(4, 0)
	dir.speed_scale = PackedFloat32Array([1.0, 1.0])
	dir.start_area = Rect2(900, -64, 40, 64)
	dir.end_area = Rect2(1700, -64, 40, 64)
	(dir.get_node("CP2") as Node2D).position = Vector2(1000, 0)
	var errs := dir.content_errors(room)
	var expect := ["(0, 0)", "speed_scale", "start_area", "end_area overlaps exit", "CP2"]
	for key in expect:
		check(Array(errs).any(func(e: String) -> bool: return e.contains(key)), "expected an error about '%s' in %s" % [key, str(errs)])
	(dir.get_node("CP1") as Node2D).position = Vector2(1100, 0)
	(dir.get_node("CP2") as Node2D).position = Vector2(1040, 0)
	errs = dir.content_errors(room)
	check(Array(errs).any(func(e: String) -> bool: return e.contains("not after")), "checkpoints out of order must be reported: %s" % str(errs))
	room.free()
