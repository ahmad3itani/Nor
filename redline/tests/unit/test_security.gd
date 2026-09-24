extends RedlineTestCase
## M7/M6 ScannerBeam (D-072) on tests/fixtures/security_lane.tscn
## (tools/roomgen/fixtures_security.py): floor y 0 from x -48 to 1400;
## calibration LOW 100, HIGH 210 (top -120), FULL 320 (top -200); live LOW
## 520, live FULL pulse 1.4/1.0 at 760, searchlight 620..1020 on circuit t_s.
## Window tests place Rook mid-run (teleport + run speed) so each takeoff or
## dodge starts at an exact x, then read scanner_tripped for one beam id.

const FIXTURE := "res://tests/fixtures/security_lane.tscn"
const NEEDLE := "res://enemies/variants/Needle.tscn"

var root: Node2D
## [beam_id, mode] per scanner_tripped (append-only: lambdas copy locals).
var tripped: Array = []


func before_each() -> void:
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	Game.new_game()
	tripped.clear()
	EventBus.scanner_tripped.connect(_on_tripped)


func after_each() -> void:
	EventBus.scanner_tripped.disconnect(_on_tripped)
	Game.set_ability(&"dash", false)
	SceneRouter.current_room = null
	SceneRouter.world_root = null
	root.queue_free()
	Game.new_game()
	await physics_frames(2)


func _on_tripped(id: String, mode: int) -> void:
	tripped.append([id, mode])


func _trips(id: String) -> int:
	return tripped.filter(func(t: Array) -> bool: return t[0] == id).size()


func _enter() -> Room:
	SceneRouter.goto_room(FIXTURE, &"start")
	await physics_frames(10)
	return SceneRouter.current_room as Room


func _beam(room: Room, id: String) -> ScannerBeam:
	return room.get_node_or_null(NodePath("Hazards/Scanner_" + id)) as ScannerBeam


func _make_input(p: Player) -> ScriptedInputSource:
	var input := ScriptedInputSource.new()
	p.input_source = input
	return input


## Puts Rook back on the floor, healthy and at rest at x, with every beam's
## blink cleared, ready for the next attempt.
func _reset(room: Room, input: ScriptedInputSource, x: float) -> void:
	input.move_x = 0
	input.down_held = false
	input.release_jump()
	var p := room.player
	for f in 90:
		if p.is_on_floor() and p.current_state_id() != &"hurt" and p.current_state_id() != &"dodge" and p.current_state_id() != &"dash":
			break
		await physics_frames(1)
	p.combat.health = p.combat.config.max_health
	p.combat.hurt_invuln_timer = 0.0
	p.global_position = Vector2(x, 0)
	p.velocity = Vector2.ZERO
	for n in room.find_children("Scanner_*", "", true, false):
		(n as ScannerBeam).grace_left = 0.0
	await physics_frames(4)


## Runs right from `x - lead` at run speed and returns on the frame boundary
## where Rook's centre is exactly at x (nudged by < one frame of travel).
func _run_to_exact(room: Room, input: ScriptedInputSource, x: float, lead: float = 24.0) -> void:
	var p := room.player
	var speed := p.config.max_run_speed
	p.global_position = Vector2(x - lead, 0)
	p.velocity = Vector2(speed, 0)
	input.move_x = 1
	for f in 60:
		await physics_frames(1)
		if p.global_position.x + speed / 60.0 >= x:
			break
	p.global_position.x = x
	p.velocity.x = speed


func _low_takeoff(room: Room, input: ScriptedInputSource, beam: ScannerBeam, d: float) -> bool:
	await _reset(room, input, beam.position.x + d - 60.0)
	var before := _trips(beam.beam_id)
	await _run_to_exact(room, input, beam.position.x + d)
	input.press_jump()
	for f in 70:
		await physics_frames(1)
		if f > 4 and room.player.is_on_floor():
			break
	input.release_jump()
	return _trips(beam.beam_id) == before


## Front edge `d` px before the beam's near face, then dodge right.
func _dodge_from(room: Room, input: ScriptedInputSource, beam: ScannerBeam, d: float, running: bool) -> bool:
	var half := room.player.config.standing_size.x * 0.5
	var x := beam.beam_rect().position.x - d - half
	var before := _trips(beam.beam_id)
	if running:
		await _reset(room, input, x - 60.0)
		await _run_to_exact(room, input, x)
	else:
		await _reset(room, input, x)
		input.move_x = 1
	input.press_dodge()
	for f in 30:
		await physics_frames(1)
	input.move_x = 0
	return _trips(beam.beam_id) == before


## [first, last] passing offsets of `pass_at` over range(lo, hi + 1), plus
## whether the passes are one contiguous run.
func _window(passes: Dictionary) -> Array:
	var keys: Array = passes.keys()
	keys.sort()
	var first := INF
	var last := -INF
	for k: float in keys:
		if passes[k]:
			first = minf(first, k)
			last = maxf(last, k)
	var contiguous := true
	for k: float in keys:
		if k >= first and k <= last and not passes[k]:
			contiguous = false
	return [first, last, contiguous]


func _sweep(room: Room, input: ScriptedInputSource, beam: ScannerBeam, lo: int, hi: int, kind: String) -> Dictionary:
	var res := {}
	for i in range(lo, hi + 1):
		match kind:
			"low":
				res[float(i)] = await _low_takeoff(room, input, beam, float(i))
			"dodge_run":
				res[float(i)] = await _dodge_from(room, input, beam, float(i), true)
			"dodge_stand":
				res[float(i)] = await _dodge_from(room, input, beam, float(i), false)
	return res


## Walking into each calibration beam: a trip, no pip, and a shove that
## leaves Rook at least 24 px back on the approach side.
func test_calibration_shove_no_pip_moves_back_24px() -> void:
	var room := await _enter()
	var p := room.player
	var input := _make_input(p)
	var max_hp := p.combat.health
	for id: String in ["cal_low", "cal_high", "cal_full"]:
		var beam := _beam(room, id)
		check(beam != null and beam.data.damage == 0, "%s should be a calibration beam" % id)
		if beam == null:
			continue
		await _reset(room, input, beam.position.x - 60.0)
		input.move_x = 1
		var before := _trips(id)
		var trip_x := INF
		for f in 90:
			await physics_frames(1)
			if _trips(id) > before:
				trip_x = p.global_position.x
				input.move_x = 0
				break
		check(_trips(id) == before + 1, "%s: walking in should trip once" % id)
		await physics_frames(45)
		check(p.combat.health == max_hp, "%s: calibration must not cost a pip (%d/%d)" % [id, p.combat.health, max_hp])
		check(p.global_position.x <= trip_x - 24.0, "%s: shove should move Rook >= 24 px back (trip %.1f, now %.1f)" % [id, trip_x, p.global_position.x])
		check(int(tripped.back()[1]) == int(beam.data.mode), "%s: scanner_tripped carries the mode" % id)
	check(p.combat.hurt_invuln_timer <= 0.0, "a shove grants no invulnerability")


## Run-jump takeoffs from beam - 90 to beam - 10 in 1 px steps over the live
## LOW beam. The documented window (-80..-21) must pass throughout, and the
## exact pass window (collider overlap with the 20 px bar) is one run from
## -87 to -19, +-2 px.
func test_low_takeoff_sweep() -> void:
	var room := await _enter()
	var input := _make_input(room.player)
	var res := await _sweep(room, input, _beam(room, "low"), -90, -10, "low")
	var w := _window(res)
	check(w[2], "LOW pass window should be contiguous: %s" % str(res))
	check_near(w[0], -87.0, 2.0, "LOW earliest passing takeoff")
	check_near(w[1], -19.0, 2.0, "LOW latest passing takeoff")
	for d in range(-80, -20):
		check(res[float(d)], "documented LOW window: takeoff at beam %d should pass" % d)
	check(not res[-90.0] and not res[-10.0], "takeoffs outside the window must trip")


## HIGH leaves a 24 px slot: a slide and a crawl both pass under it.
func test_high_slide_and_crawl_pass() -> void:
	var room := await _enter()
	var p := room.player
	var input := _make_input(p)
	var beam := _beam(room, "cal_high")
	var bx := beam.position.x
	# Slide: full run-up, hold down 26 px before the beam, keep it past.
	await _reset(room, input, bx - 70.0)
	await _run_to_exact(room, input, bx - 26.0)
	input.down_held = true
	var slid := false
	for f in 60:
		await physics_frames(1)
		slid = slid or p.current_state_id() == &"slide"
		if p.global_position.x > bx + 24.0:
			break
	input.down_held = false
	input.move_x = 0
	check(slid, "Rook should have slid")
	check(p.global_position.x > bx + 10.0, "the slide should carry Rook past the beam (at %.1f)" % p.global_position.x)
	check(_trips("cal_high") == 0, "a slide must pass under a HIGH beam")
	# Crawl: crouch at a standstill, then move while holding down.
	await _reset(room, input, bx - 26.0)
	input.down_held = true
	await physics_frames(6)
	input.move_x = 1
	for f in 120:
		await physics_frames(1)
		if p.global_position.x > bx + 16.0:
			break
	check(p.is_low, "Rook should crawl low")
	check(p.global_position.x > bx + 10.0, "the crawl should reach past the beam (at %.1f)" % p.global_position.x)
	check(_trips("cal_high") == 0, "a crawl must pass under a HIGH beam")
	input.down_held = false
	input.move_x = 0
	# Standing in the slot is what trips it.
	await _reset(room, input, bx - 26.0)
	input.move_x = 1
	await physics_frames(20)
	check(_trips("cal_high") == 1, "walking in standing should trip the HIGH beam")


## A static FULL beam is passed by dodging through it (i-frames). The exact
## window, front edge distance to the beam's near face, is measured the same
## running and from a standstill.
func test_full_static_dodge_window() -> void:
	var room := await _enter()
	var input := _make_input(room.player)
	var beam := _beam(room, "cal_full")
	var run := await _sweep(room, input, beam, 0, 44, "dodge_run")
	var wr := _window(run)
	check(wr[2], "running dodge window should be contiguous: %s" % str(run))
	check_near(wr[0], 10.0, 2.0, "running dodge: nearest passing front edge")
	check_near(wr[1], 38.0, 2.0, "running dodge: farthest passing front edge")
	check(wr[1] - wr[0] + 1.0 >= 27.0, "the dodge window should be >= 27 px (0.18 s at run speed)")
	check(not run[0.0] and not run[44.0], "dodges started outside the window must trip")
	var stand := await _sweep(room, input, beam, 0, 44, "dodge_stand")
	var ws := _window(stand)
	check(ws[2] and absf(ws[0] - wr[0]) <= 2.0 and absf(ws[1] - wr[1]) <= 2.0,
		"a standstill dodge passes over the same span (%s vs %s)" % [str(ws), str(wr)])


## Falling is vertical speed only: it never reads as a blur.
func test_fall_through_full_trips() -> void:
	var room := await _enter()
	var p := room.player
	var input := _make_input(p)
	var beam := _beam(room, "cal_full")
	await _reset(room, input, 200.0)
	p.global_position = Vector2(beam.position.x, -150.0)
	p.velocity = Vector2(0, 450)
	for f in 30:
		await physics_frames(1)
		if _trips("cal_full") > 0:
			break
	check(_trips("cal_full") == 1, "a fall through a FULL beam must trip it")


## Dash (400 px/s) is a blur: it passes a FULL beam even after its short
## i-frames end.
func test_dash_through_full_does_not_trip() -> void:
	Game.set_ability(&"dash", true)
	var room := await _enter()
	var p := room.player
	var input := _make_input(p)
	var beam := _beam(room, "cal_full")
	var dashed := false
	var blurred := false
	for d: float in [4.0, 12.0, 24.0]:
		await _reset(room, input, beam.beam_rect().position.x - d - 6.0 - 40.0)
		await _run_to_exact(room, input, beam.beam_rect().position.x - d - 6.0)
		input.press_dodge()
		for f in 30:
			await physics_frames(1)
			if p.current_state_id() == &"dash":
				dashed = true
				if beam.player_rect(p).intersects(beam.beam_rect()) and not p.invulnerable:
					blurred = true
		input.move_x = 0
	check(dashed, "Rook should dash with Dash unlocked")
	check(blurred, "the dash should overlap the beam outside i-frames at least once (blur, not i-frames)")
	check(_trips("cal_full") == 0, "Dash through a FULL beam must not trip it")


## Only Rook trips beams: a launched Needle flies through a live FULL beam
## and nothing happens.
func test_only_player_trips() -> void:
	var room := await _enter()
	var beam := _beam(room, "cal_full")
	var needle := (load(NEEDLE) as PackedScene).instantiate() as Enemy
	needle.position = Vector2(beam.position.x - 60.0, -2.0)
	room.get_node("Enemies").add_child(needle)
	await physics_frames(2)
	needle.set_ai(Enemy.AI.LAUNCHED)
	needle.velocity = Vector2(320, -240)
	var crossed := false
	for f in 60:
		await physics_frames(1)
		if not is_instance_valid(needle):
			break
		if needle.global_position.x > beam.position.x + 20.0:
			crossed = true
			break
	check(crossed, "the launched Needle should cross the beam")
	check(beam.is_live(), "the beam stays live")
	check(tripped.is_empty(), "only the player trips scanners: %s" % str(tripped))


func test_pulse_and_sweep_phase_from_data() -> void:
	var room := await _enter()
	var pulse := _beam(room, "pulse")
	var d := pulse.data
	check(d.pulse_on == 1.4 and d.pulse_off == 1.0 and d.pre_flicker >= 0.35, "pulse_14 data")
	# The cycle starts OFF, flickers for pre_flicker, then is ON for pulse_on.
	check(pulse.pulse_state_at(0.0) == ScannerBeam.State.OFF, "t 0: off")
	check(pulse.pulse_state_at(d.pulse_off - d.pre_flicker - 0.02) == ScannerBeam.State.OFF, "just before the flicker: off")
	check(pulse.pulse_state_at(d.pulse_off - d.pre_flicker + 0.02) == ScannerBeam.State.FLICKER, "flicker telegraph")
	check(pulse.pulse_state_at(d.pulse_off + 0.02) == ScannerBeam.State.ON, "on after pulse_off")
	check(pulse.pulse_state_at(d.pulse_off + d.pulse_on - 0.02) == ScannerBeam.State.ON, "still on at the end of pulse_on")
	check(pulse.pulse_state_at(d.pulse_off + d.pulse_on + 0.02) == ScannerBeam.State.OFF, "next cycle: off")
	pulse.phase = 0.5
	check(pulse.pulse_state_at(d.pulse_off + 0.5 - 0.1) == ScannerBeam.State.FLICKER, "phase delays the cycle (flicker)")
	check(pulse.pulse_state_at(d.pulse_off + 0.52) == ScannerBeam.State.ON, "phase delays the cycle (on)")
	pulse.phase = 0.0
	check(pulse.state() == pulse.pulse_state_at(pulse.clock), "live state follows the clock")
	# Sweep: paused at sweep_from, travels at sweep_speed, pauses, returns.
	var sl := _beam(room, "searchlight")
	var sd := sl.data
	var leg := (sd.sweep_to - sd.sweep_from) / sd.sweep_speed
	var mid := (sd.sweep_from + sd.sweep_to) * 0.5
	check_near(sl.sweep_x_at(sd.end_pause * 0.5), sd.sweep_from, 0.01, "sweep starts paused at sweep_from")
	check_near(sl.sweep_x_at(sd.end_pause + leg * 0.5), mid, 0.5, "sweep moves at sweep_speed")
	check_near(sl.sweep_x_at(sd.end_pause + leg + sd.end_pause * 0.5), sd.sweep_to, 0.01, "sweep pauses at sweep_to")
	check_near(sl.sweep_x_at(2.0 * sd.end_pause + leg * 1.5), mid, 0.5, "sweep returns")
	sl.phase = 1.0
	check_near(sl.sweep_x_at(sd.end_pause + 1.0 + leg * 0.5), mid, 0.5, "phase delays the sweep")
	sl.phase = 0.0
	var at := sl.clock
	await physics_frames(60)
	check_near(sl.clock - at, 1.0, 0.02, "the beam clock runs in physics time")
	check_near(sl.beam_x(), sl.sweep_x_at(sl.clock), 0.01, "live beam x follows the clock")
	check_near(sl.beam_rect().get_center().x, sl.beam_x(), 0.01, "the lethal rect sits on the beam x")


func test_breaker_takes_beam_offline_for_offline_open() -> void:
	var room := await _enter()
	var sl := _beam(room, "searchlight")
	var pulse := _beam(room, "pulse")
	check(sl.circuit == &"t_s" and sl.offline_open == 5.5 and sl.offline_warn == 1.5, "searchlight uses the default offline floats")
	check(sl.content_flags().get("consumes", []) == ["circuit:t_s"], "the beam consumes circuit:t_s")
	EventBus.breaker_hit.emit(&"other")
	await physics_frames(1)
	check(sl.state() != ScannerBeam.State.OFFLINE, "another circuit changes nothing")
	EventBus.breaker_hit.emit(&"t_s")
	check(pulse.state() != ScannerBeam.State.OFFLINE, "a beam off the circuit is unaffected")
	var frames := 0
	var warn_frame := -1
	while sl.state() == ScannerBeam.State.OFFLINE and frames < 600:
		await physics_frames(1)
		frames += 1
		if warn_frame < 0 and sl.is_warning():
			warn_frame = frames
	check_near(frames, 330.0, 1.0, "OFFLINE for offline_open (frames)")
	check_near(warn_frame, 240.0, 1.0, "countdown in the last offline_warn (frames)")
	# A re-hit at 3 s refreshes the window.
	EventBus.breaker_hit.emit(&"t_s")
	await physics_frames(180)
	check(sl.state() == ScannerBeam.State.OFFLINE and not sl.is_warning(), "3 s in: still offline, no countdown")
	EventBus.breaker_hit.emit(&"t_s")
	frames = 0
	while sl.state() == ScannerBeam.State.OFFLINE and frames < 600:
		await physics_frames(1)
		frames += 1
	check_near(frames, 330.0, 1.0, "a re-hit refreshes the full offline_open")
	# Offline really means harmless: stand in the beam's path while it is off.
	EventBus.breaker_hit.emit(&"t_s")
	var p := room.player
	p.global_position = Vector2(sl.beam_x(), 0)
	await physics_frames(20)
	check(_trips("searchlight") == 0, "an offline beam never trips")


## After a live hit the beam blinks dark for rehit_grace: one mistake costs
## one pip, and the knockback sends Rook back the way he came.
func test_rehit_grace() -> void:
	var room := await _enter()
	var p := room.player
	var input := _make_input(p)
	var beam := _beam(room, "low")
	var max_hp := p.combat.health
	await _reset(room, input, beam.position.x - 40.0)
	input.move_x = 1
	for f in 60:
		await physics_frames(1)
		if _trips("low") > 0:
			break
	input.move_x = 0
	check(_trips("low") == 1, "walking into a live LOW beam trips it")
	check(p.combat.health == max_hp - 1, "a live beam costs one pip")
	check(p.velocity.x < 0.0, "knockback goes back toward the approach side")
	check(beam.state() == ScannerBeam.State.DARK, "the beam blinks dark after a hit")
	check_near(beam.grace_left, beam.data.rehit_grace, 0.02, "for rehit_grace")
	# Inside the grace (hurt invulnerability cleared on purpose): no re-hit.
	await physics_frames(20)
	p.combat.hurt_invuln_timer = 0.0
	p.global_position = Vector2(beam.position.x, 0)
	p.velocity = Vector2.ZERO
	await physics_frames(10)
	check(_trips("low") == 1 and p.combat.health == max_hp - 1, "no re-hit during rehit_grace")
	# After the grace the beam sees him again.
	await physics_frames(int(ceil(beam.grace_left * 60.0)) + 2)
	p.combat.hurt_invuln_timer = 0.0
	p.global_position = Vector2(beam.position.x, 0)
	await physics_frames(3)
	check(_trips("low") == 2 and p.combat.health == max_hp - 2, "the beam re-arms after rehit_grace")


func test_data_presets_validate() -> void:
	for n: String in ["cal_low", "cal_high", "cal_full", "low", "high", "full_pulse_14", "full_pulse_12", "full_pulse_10", "searchlight"]:
		var d := load("res://data/level/scanner_%s.tres" % n) as ScannerData
		check(d != null, "scanner_%s loads" % n)
		if d:
			check(d.validate().is_empty(), "scanner_%s validates: %s" % [n, str(d.validate())])
			check((d.damage == 0) == n.begins_with("cal_"), "scanner_%s: calibration iff damage 0" % n)
	var bad := ScannerData.new()
	bad.pulse_on = 1.0
	bad.pulse_off = 1.0
	bad.pre_flicker = 0.2
	bad.sweep_from = 0.0
	bad.sweep_to = 100.0
	bad.sweep_speed = 50.0
	bad.end_pause = 0.5
	bad.thickness = 0.0
	check(bad.validate().size() == 3, "validate flags flicker, end_pause and thickness: %s" % str(bad.validate()))
	var room := await _enter()
	for n in room.find_children("Scanner_*", "", true, false):
		check((n as ScannerBeam).content_errors(room).is_empty(), "%s lints clean" % n.name)


