extends RedlineTestCase
## The Pulse Pit (M9 D2 §2.3, §8.2; T10): the WaveDirector arms in its room
## (the room is built after challenge_started, R10.4), spawns the set in a
## fixed round-robin order, scores the style set with the run's style score
## and the endurance set with the ReactorCore multiplier, and never touches
## the world map or the economy. The two challenges are pit_style (90 s,
## style score) and pit_endurance (forced Challenge core, until Rook falls).

const H := preload("res://tests/fixtures/challenges/ChallengeHarness.gd")
const PIT := "res://world/rooms/challenge/PulsePit.tscn"
const STYLE_SET := "res://data/challenges/waves/pit_style.tres"
const ENDURANCE_SET := "res://data/challenges/waves/pit_endurance.tres"

var h: H
var _finished: Array = []


func before_each() -> void:
	h = H.new(self, "pulse_pit")
	h.setup()
	# The shipped challenges, not the fixture folder.
	ChallengeLibrary.data_dir = ChallengeLibrary.DEFAULT_DIR
	ChallengeLibrary.clear_cache()
	_finished = []
	h.listen(EventBus.challenge_finished, func(id: String, o: int, v: int, m: int, nb: bool) -> void: _finished.append([id, o, v, m, nb]))


func after_each() -> void:
	await h.teardown()


func _pit(id: String) -> ChallengeData:
	var ch := ChallengeLibrary.by_id(id)
	check(ch != null, "%s is shipped" % id)
	return ch


func _director() -> WaveDirector:
	var r := h.room()
	return r.get_node_or_null("WaveDirector") as WaveDirector if r else null


## Waits until the live room's director has spawned at least one enemy.
func _spawned() -> bool:
	return await h.until(func() -> bool:
		var d := _director()
		return d != null and d.armed and not d.spawn_log.is_empty(), 120)


func test_waves_start_after_start_and_restart() -> void:
	# A Relay-terminal style start (from a world room).
	await h.goto(H.WORLD_A, &"start")
	check(await h.start(_pit("pit_style"), {"room": H.WORLD_A, "entry": &"start"}), "pit_style started from a world room")
	check(SceneRouter.current_room_path == PIT, "the run loaded the Pulse Pit")
	check(await _spawned(), "waves spawn after a terminal start")
	# An id, not the node: the old room is freed (a lambda must not capture it).
	var first := _director().get_instance_id()
	# A fast reset reloads the room (goto_room deferred): the new director arms.
	Challenges.restart(&"reset")
	check(await h.until(func() -> bool: return _director() != null and _director().get_instance_id() != first and Challenges.phase() == Challenges.Phase.RUNNING, 60),
		"the reset rebuilt the room")
	check(await _spawned(), "waves spawn after a fast reset")
	check(_director().wave >= 1 and _director().spawn_log[0][0] == 1, "the reset starts again at wave 1 (%s)" % [_director().spawn_log])
	Challenges.quit()
	await h.until(func() -> bool: return not Challenges.active() and not SceneRouter.transitioning, 120)
	check(not Challenges.active(), "quit")
	# A title start (the title row loads the save, then starts).
	h.make_host(true)
	check(await h.start(_pit("pit_endurance"), {"title": true}), "pit_endurance started from the title")
	check(await _spawned(), "waves spawn after a title start")


func test_waves_validate() -> void:
	for path in [STYLE_SET, ENDURANCE_SET]:
		var ws := load(path) as WaveSet
		check(ws != null and ws.validate().is_empty(), "%s validates: %s" % [path.get_file(), ws.validate() if ws else "not a WaveSet"])
	var style := load(STYLE_SET) as WaveSet
	var endurance := load(ENDURANCE_SET) as WaveSet
	check(style.wave_count() == 5 and not style.loops() and style.score_mode == WaveSet.ScoreMode.STYLE, "style: five waves, no loop, style score")
	check(endurance.wave_count() == 6 and endurance.loop_from == 3 and endurance.max_alive == 5 \
		and endurance.score_mode == WaveSet.ScoreMode.ENDURANCE, "endurance: six waves, W4-W6 loop, max 5 alive")
	for id in ["pit_style", "pit_endurance"]:
		var ch := _pit(id)
		check(ch.validate().is_empty(), "%s validates: %s" % [id, ch.validate()])
		check(ch.group == ChallengeData.Group.PULSE_PIT and ch.score_kind == ChallengeData.ScoreKind.SCORE, "%s is a Pulse Pit SCORE run" % id)
		check(ch.unlock_when == "flag:act1_complete" and ch.start_room == PIT, "%s opens after Act I, in the pit" % id)
		var v := ContentValidator.new()
		NullRules.check_challenge(ch, v)
		check(v.errors.is_empty(), "%s: NU-6 clean: %s" % [id, v.errors])
	# NU-6 catches a set naming a marker the room lacks.
	var bad := style.duplicate(true) as WaveSet
	bad.entries[0].spawn_points = PackedInt32Array([9])
	var v2 := ContentValidator.new()
	NullRules.check_waves(bad, PIT, "fixture", v2)
	check(v2.errors.size() == 1 and v2.errors[0].contains("WaveSpawn_9"), "a missing WaveSpawn is an error: %s" % [v2.errors])
	var broken := WaveSet.new()
	var e := WaveEntry.new()
	e.wave = 2
	e.enemy_scene = "res://enemies/variants/Nope.tscn"
	broken.entries = [e]
	var errs := broken.validate()
	check(errs.size() >= 2, "a skipped wave and a missing scene are errors: %s" % [errs])


## The director in a free run (no challenge): the same set spawns the same
## enemies at the same markers in the same frames, every time.
func _free_run_log(frames: int) -> Array:
	var r := await h.goto(PIT, &"start")
	r.player.combat.config = r.player.combat.config.duplicate()
	r.player.combat.config.hurt_invuln_time = 999.0
	var d := r.get_node("WaveDirector") as WaveDirector
	check(not d.armed, "outside a run the director stays idle")
	var ws := (load(STYLE_SET) as WaveSet).duplicate(true) as WaveSet
	ws.next_after_s = 0.5
	d.free_run = true
	d.arm(ws)
	var log: Array = []
	var waves: Array = []
	d.wave_started.connect(func(n: int) -> void: waves.append([n, d._frames]))
	for i in frames:
		await physics_frames(1)
	for entry: Array in d.spawn_log:
		log.append(entry.duplicate())
	d.free_run = false
	d.disarm()
	return [log, waves]


func test_wave_director_deterministic_order() -> void:
	var a: Array = await _free_run_log(200)
	var b: Array = await _free_run_log(200)
	check(a == b and not (a[0] as Array).is_empty(), "two runs spawn identically (%s vs %s)" % [a, b])
	var log: Array = a[0]
	# Wave 1: two Needles round-robin over points 1 and 4.
	check(log.size() >= 2 and log[0] == [1, "res://enemies/variants/Needle.tscn", 1] and log[1] == [1, "res://enemies/variants/Needle.tscn", 4],
		"wave 1 round-robin (%s)" % [log.slice(0, 2)])
	var waves_started: Array = a[1]
	check(waves_started.size() >= 3 and waves_started[1][1] == 30, "a stalled wave advances after next_after_s (%s)" % [waves_started])


func test_endurance_score_formula_and_multiplier() -> void:
	var ws := load(ENDURANCE_SET) as WaveSet
	check(ws.endurance_score(10.0, 3, 2, 1.0) == 650, "10 s, 3 kills, 2 waves = 100 + 150 + 400")
	check(ws.endurance_score(10.0, 3, 2, 1.5) == 975, "x1.5 on the Challenge core (reactor_challenge.tres)")
	check(ws.endurance_score(0.0, 0, 0, 1.5) == 0, "nothing scores nothing")
	await h.goto(H.WORLD_A, &"start")
	check(await h.start(_pit("pit_endurance"), {"room": H.WORLD_A, "entry": &"start"}), "pit_endurance started")
	check(await _spawned(), "waves spawned")
	var d := _director()
	check_near(d.multiplier(), 1.5, 0.0001, "the live Core's score_multiplier (Challenge core)")
	await physics_frames(30)
	var want := ws.endurance_score(float(Challenges.clock.frames) / RunClock.FPS, d.kills, d.waves_cleared, 1.5)
	check(Challenges.score_value() == want and want > 0, "the run's score is the director's formula (%d vs %d)" % [Challenges.score_value(), want])
	# A kill scores score_per_kill x 1.5.
	var before := d.kills
	for pair: Array in d._alive:
		var e := pair[0] as Enemy
		if is_instance_valid(e):
			var kill := HitInfo.create(h.player(), e.data.attacks[0].duplicate(), Vector2.ZERO, Vector2.RIGHT)
			kill.attack.damage = 99999.0
			e.receive_hit(kill)
			break
	await physics_frames(2)
	check(d.kills == before + 1, "the director counted the kill (%d)" % d.kills)
	check(Challenges.wave_number() == d.wave and d.wave >= 1, "the HUD reads the wave (%d)" % Challenges.wave_number())


func test_style_target_time_limit() -> void:
	var ch := _pit("pit_style")
	check(ch.end_on == ChallengeData.EndOn.TIME_LIMIT and is_equal_approx(ch.time_limit_s, 90.0), "90 s limit")
	check(Array(ch.medal_thresholds) == [1200, 2400, 4000, 6000], "provisional medals (%s)" % [ch.medal_thresholds])
	await h.goto(H.WORLD_A, &"start")
	check(await h.start(ch, {"room": H.WORLD_A, "entry": &"start"}), "pit_style started")
	check(await _spawned(), "waves spawned")
	Challenges.session.style_score = 1500.0
	check(Challenges.score_value() == 1500, "the style set scores the run's style score")
	Challenges.clock.frames = roundi(ch.time_limit_s * RunClock.FPS) - 3
	check(await h.until(func() -> bool: return not _finished.is_empty(), 30), "the time limit ends the run")
	if not _finished.is_empty():
		check(_finished[0][1] == ChallengeData.Outcome.FINISHED and _finished[0][2] == 1500, "finished with the style score (%s)" % [_finished[0]])
		check(_finished[0][3] == 1, "1500 is Bronze (medal %d)" % _finished[0][3])


func test_endurance_forces_challenge_core_even_with_assist_setting() -> void:
	Settings.reactor_mode = 1
	var ch := _pit("pit_endurance")
	check(ch.kit.reactor_mode == 2 and ch.end_on == ChallengeData.EndOn.DEATH and ch.on_death == ChallengeData.OnDeath.FINISH,
		"the endurance kit forces the Challenge core; a fall finishes the run")
	await h.goto(H.WORLD_A, &"start")
	check(await h.start(ch, {"room": H.WORLD_A, "entry": &"start"}), "pit_endurance started")
	var p := h.player()
	check(p.reactor.config == p.reactor.configs[2], "the Challenge core, not the player's Assist setting")
	check(Challenges.forced_reactor_mode() == 2, "Challenges reports the forced mode")
	check(Settings.reactor_mode == 1, "the setting itself is untouched")
	p.combat.take_damage(99, Vector2.ZERO, 0.0, false, "test")
	check(await h.until(func() -> bool: return not _finished.is_empty(), 180), "a fall ends the run")
	if not _finished.is_empty():
		check(_finished[0][1] == ChallengeData.Outcome.FINISHED and _finished[0][2] >= 0, "FINISHED with a score (%s)" % [_finished[0]])


func test_pit_off_map_economy_unchanged() -> void:
	check(Game.world_map.room("PulsePit") == null, "the pit is not on the world map")
	for r in Game.world_map.rooms:
		check(not r.room_path.begins_with(NullRules.ROOM_DIR), "world map room %s is not a challenge room" % r.room_path)
	for path in SliceStats.room_paths():
		check(not path.begins_with(NullRules.ROOM_DIR), "SliceStats never counts %s" % path)
	var eco := EconomyAudit.compute()
	check(not (eco["by_district"] as Dictionary).has("Training Pit") and not (eco["by_district"] as Dictionary).has("Deep Rig"),
		"no challenge district in the economy (%s)" % [(eco["by_district"] as Dictionary).keys()])
	var v := ContentValidator.new().check_room(PIT, false)
	check(v.errors.is_empty(), "the pit room validates: %s" % [v.errors])
	var room := v.instantiate_room(PIT)
	var nu := ContentValidator.new()
	NullRules.check_room(room, PIT, nu)
	room.free()
	check(nu.errors.is_empty(), "NU-1 clean: %s" % [nu.errors])
