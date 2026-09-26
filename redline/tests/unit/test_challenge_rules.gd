extends RedlineTestCase
## Run rules (M9 D2 §3.3-§3.4, D-148, D-149, R04.15/R04.18/R04.28): no hit
## fails on any damage (0 included; falls and Core burnout too) with a neutral
## cause line; movement only fails on a swing or a shot, never a reload; the
## death override ends a run in place or restarts the stage with the run clock
## running; the finish line replaces the exit; BOSS_STARTED times from the
## fight; a forced Core overrides the player's mode and drops the reactor
## assist tag; tags are neutral, separate and unioned over the run.

const H := preload("res://tests/fixtures/challenges/ChallengeHarness.gd")

var h: H
var _finished: Array = []


func before_each() -> void:
	h = H.new(self, "challenge_rules")
	h.setup()
	_finished = []
	h.listen(EventBus.challenge_finished, func(id: String, o: int, v: int, m: int, nb: bool) -> void: _finished.append([id, o, v, m, nb]))


func after_each() -> void:
	await h.teardown()


func _run(ch: ChallengeData) -> bool:
	await h.goto(H.WORLD_A, &"start")
	return await h.start(ch, {"room": H.WORLD_A, "entry": &"start"})


func _retry() -> void:
	Challenges.restart(&"menu")
	var a := Challenges.attempt()
	await h.until(func() -> bool: return Challenges.attempt() == a and Challenges.phase() == Challenges.Phase.RUNNING and h.room() != null)
	await physics_frames(2)


func test_nohit_fails_on_damage_and_pit() -> void:
	var ch := H.fx(H.TRIAL)
	ch.fail_on_damage = true
	check(await _run(ch), "run started")
	h.drive().move_x = 1
	await physics_frames(3)
	h.player().combat.take_damage(0, Vector2.ZERO, 0.0, false, "test")
	check(_finished.size() == 1 and _finished[0][1] == ChallengeData.Outcome.FAILED_HIT and _finished[0][2] == -1, "a 0-pip hit is a hit (%s)" % [_finished])
	check(Challenges.last_result.get("cause") == "Run over: hit taken", "neutral line (%s)" % Challenges.last_result.get("cause"))
	await _retry()
	var p := h.player()
	p.teleport(Vector2(p.global_position.x, h.room().bounds.end.y + h.room().kill_margin + 20.0))
	await physics_frames(2)
	check(_finished.size() == 2 and _finished[1][1] == ChallengeData.Outcome.FAILED_HIT, "a fall is a hit (%s)" % [_finished])
	check(Challenges.last_result.get("cause") == "Run over: fell", "cause: fell (%s)" % Challenges.last_result.get("cause"))


func test_nohit_cause_lines() -> void:
	check(RuleWatch.cause_line("pit") == "Run over: fell" and RuleWatch.cause_line("burnout") == "Run over: Core ran dry", "pit and burnout lines")
	check(RuleWatch.cause_line("needle/lunge") == "Run over: hit taken" and RuleWatch.cause_line("") == "Run over: hit taken", "anything else")
	var ch := H.fx(H.TRIAL)
	ch.fail_on_damage = true
	check(await _run(ch), "run started")
	h.player().combat.take_damage(1, Vector2.ZERO, 0.0, false, "burnout")
	check(Challenges.last_result.get("cause") == "Run over: Core ran dry", "burnout counts as a hit (%s)" % Challenges.last_result.get("cause"))
	var rows: Array = [Challenges.last_result.get("cause"), "Run over: fell", "Run over: hit taken", "Run over: attack used"]
	check(not rows.any(func(t: String) -> bool: return t.to_upper().contains("FAIL")), "never 'FAILED' (§24)")


func test_movement_only_fails_on_swing_and_shot_not_reload() -> void:
	var ch := H.fx(H.TRIAL)
	ch.fail_on_attack = true
	check(await _run(ch), "run started")
	var src := h.drive()
	src.move_x = 1
	await physics_frames(3)
	var w := h.player().combat.ranged_weapon()
	EventBus.ranged_fired.emit(w, w.ammo_max if w else 6)
	await physics_frames(2)
	check(_finished.is_empty(), "a reload never fails the run")
	src.press_light()
	await physics_frames(3)
	check(_finished.size() == 1 and _finished[0][1] == ChallengeData.Outcome.FAILED_ATTACK, "a swing does (%s)" % [_finished])
	check(Challenges.last_result.get("cause") == "Run over: attack used", "neutral line")
	await _retry()
	src = h.drive()
	src.press_ranged()
	await physics_frames(3)
	check(_finished.size() == 2 and _finished[1][1] == ChallengeData.Outcome.FAILED_ATTACK, "a shot does (%s)" % [_finished])


func test_death_override_end_run_no_transition() -> void:
	check(await _run(H.fx(H.TRIAL)), "run started")
	h.drive().move_x = 1
	await physics_frames(3)
	var deaths := Game.state.deaths
	var p := h.player()
	p.combat.take_damage(99, Vector2.ZERO, 0.0, false, "test")
	check(_finished.size() == 1 and _finished[0][1] == ChallengeData.Outcome.DIED, "death ends the run (%s)" % [_finished])
	await physics_frames(int(p.combat.config.respawn_delay * 60.0) + 20)
	check(SceneRouter.current_room_path == H.WORLD_A and h.player() == p and not SceneRouter.transitioning, "no respawn transition")
	check(Game.state.deaths == deaths and Game.state.dropped_scrap.is_empty(), "no Game.on_player_death, no scrap cache")
	check(Challenges.records.attempts("fx_trial", 1) == 1 and Challenges.records.board("fx_trial").is_empty(), "an attempt, no record")


func test_restart_stage_on_death_keeps_run_frames() -> void:
	Game.set_ability(&"dash", true)
	check(await h.start(H.fx(H.STAGED), {}), "staged run started")
	await physics_frames(30)
	var f1 := Challenges.clock.frames
	check(f1 > 20, "ROOM_READY: counting (%d)" % f1)
	var resets: Array = []
	h.listen(EventBus.challenge_reset, func(_id: String, r: StringName) -> void: resets.append(r))
	var p := h.player()
	var p_id := p.get_instance_id()
	var delay := p.combat.config.respawn_delay
	p.combat.take_damage(99, Vector2.ZERO, 0.0, false, "test")
	check(await h.until(func() -> bool: return h.player() != null and h.player().get_instance_id() != p_id, int(delay * 60.0) + 30), "the stage restarted")
	check(resets == [&"death"], "reason death (%s)" % [resets])
	check(Challenges.clock.running and Challenges.clock.frames >= f1 + int(delay * 60.0) - 2, "the run clock kept running (%d vs %d)" % [Challenges.clock.frames, f1])
	check(Challenges.attempt() == 1 and Challenges.session.stage_deaths == 1 and Challenges.session.stage_frames < 5, "same attempt, one death, stage time reset")
	check(_finished.is_empty(), "no finish")


func test_finish_line_replaces_exit_room_never_changes() -> void:
	check(await _run(H.fx(H.TRIAL)), "run started")
	var r := h.room()
	var exit := r.find_child("Exit", true, false) as RoomExit
	var line := r.find_child("FinishLine", true, false) as FinishLine
	check(exit and not exit.monitoring, "the exit is off")
	check(line and line.position == exit.position and line.size == exit.size, "a finish line with the exit's rect")
	var p := h.player()
	p.teleport(Vector2(680, 0))
	h.drive().move_x = 1
	check(await h.until(func() -> bool: return not _finished.is_empty(), 120), "finished at the line")
	check(_finished[0][1] == ChallengeData.Outcome.FINISHED and _finished[0][2] == Challenges.last_result["value"], "a TIME value (%s)" % [_finished])
	await physics_frames(20)
	check(SceneRouter.current_room_path == H.WORLD_A and h.room() == r, "the next room never loads")
	check(h.player().cinematic_lock, "the player is frozen")


func test_boss_started_start_on() -> void:
	var ch := H.fx(H.REMATCH)
	check(await h.start(ch, {}), "rematch started")
	check(Game.has_flag("collector_drone_intro_seen") and not Game.has_flag("collector_drone_defeated"), "the arena is armed with the short intro")
	h.drive().move_x = 1
	await physics_frames(5)
	check(not Challenges.clock.running, "not before the fight")
	var arena: BossArena = h.room().find_children("*", "BossArena", true, false)[0]
	var other := Node2D.new()
	add_child(other)
	EventBus.boss_started.emit(other, "SOMEONE")
	await physics_frames(1)
	check(not Challenges.clock.running, "another boss never starts the clock")
	other.queue_free()
	EventBus.boss_started.emit(arena.boss, "COLLECTOR")
	await physics_frames(30)
	check(Challenges.clock.running and Challenges.clock.frames >= 29, "boss_started starts it (%d)" % Challenges.clock.frames)
	EventBus.boss_defeated.emit("collector_drone")
	check(_finished.size() == 1 and _finished[0][1] == ChallengeData.Outcome.FINISHED and _finished[0][2] == Challenges.clock.frames, "boss_defeated ends it (%s)" % [_finished])


func test_reactor_override_forces_mode_and_drops_reactor_assist_tag() -> void:
	Settings.reactor_mode = 1
	Challenges.tag_provider = func() -> PackedStringArray: return PackedStringArray(["reactor_assist", "no_burnout", "aim_assist"])
	var ch := H.fx(H.TRIAL)
	ch.kit.reactor_mode = 2
	check(await _run(ch), "run started")
	var p := h.player()
	check(Challenges.forced_reactor_mode() == 2 and p.reactor.config == p.reactor.configs[2], "the kit's Core, not the player's (%s)" % p.reactor.config.resource_path)
	h.drive().move_x = 1
	await physics_frames(3)
	Challenges.finish(ChallengeData.Outcome.FINISHED)
	check(Array(Challenges.last_result["tags"]["assists"]) == ["aim_assist"], "reactor tags dropped (%s)" % [Challenges.last_result["tags"]])
	Challenges.quit()
	await h.until(func() -> bool: return not Challenges.active() and not SceneRouter.transitioning)
	check(Challenges.forced_reactor_mode() == -1, "no forced mode outside runs")


func test_assist_tags_recorded() -> void:
	Challenges.tag_provider = func() -> PackedStringArray: return PackedStringArray(["damage_assist"])
	check(await _run(H.fx(H.TRIAL)), "run started")
	h.drive().move_x = 1
	await physics_frames(3)
	Challenges.finish(ChallengeData.Outcome.FINISHED)
	var e: Dictionary = Challenges.records.board("fx_trial")[0]
	check(e["assists"] == ["damage_assist"] and e["timing"] == [], "the board entry carries the neutral tag (%s)" % [e])
	check(int(e["medal"]) == H.fx(H.TRIAL).medal_for(int(e["value"])), "the same medal as unassisted")


func test_tag_policy_matches_d149() -> void:
	var all := PackedStringArray(["reactor_assist", "damage_assist", "aim_assist", "no_burnout"])
	Challenges.tag_provider = func() -> PackedStringArray: return all
	Settings.jump_hold_mode = 1
	Settings.generous_checkpoints = true
	Settings.hitstop_scale = 0.5
	check(await _run(H.fx(H.TRIAL)), "run started")
	h.drive().move_x = 1
	await physics_frames(3)
	Challenges.finish(ChallengeData.Outcome.FINISHED)
	var tags: Dictionary = Challenges.last_result["tags"]
	check(Array(tags["assists"]) == Array(all), "exactly the assists (%s)" % [tags])
	check(Array(tags["timing"]) == ["hitstop_reduced"], "one timing tag, never 'checkpoints' in a run, never the jump latch (%s)" % [tags])
	check(not Array(tags["assists"]).has("hitstop_reduced") and not Array(tags["assists"]).has("jump_hold_mode"), "timing and comfort never read as assists")
	var camp := Challenges.campaign.current_tags()
	check(camp.has("checkpoints") and camp.has("hitstop_reduced") and not camp.has("jump_hold_mode"), "the campaign adds room checkpoints (%s)" % [camp])
	# The default provider (Settings.active_assists): whatever it lists is what
	# a run records, and comfort options are never in it.
	Challenges.tag_provider = Challenges._default_tags
	Settings.aim_assist = 1
	Settings.damage_assist = 1
	var expected := Settings.active_assists()
	for t in expected:
		check(["reactor_assist", "damage_assist", "aim_assist", "no_burnout"].has(t), "D-149 assist ids only (%s)" % t)
	await _retry()
	h.drive().move_x = 1
	await physics_frames(3)
	Challenges.finish(ChallengeData.Outcome.FINISHED)
	check(Array(Challenges.last_result["tags"]["assists"]) == Array(expected), "the default provider is recorded as is (%s vs %s)" % [Challenges.last_result["tags"], expected])


func test_midrun_assist_toggle_is_tagged() -> void:
	var on: Array = []
	Challenges.tag_provider = func() -> PackedStringArray: return PackedStringArray(on)
	check(await _run(H.fx(H.TRIAL)), "run started")
	h.drive().move_x = 1
	await physics_frames(3)
	on.append("aim_assist")
	EventBus.settings_changed.emit()
	await physics_frames(3)
	on.clear()
	EventBus.settings_changed.emit()
	await physics_frames(3)
	Challenges.finish(ChallengeData.Outcome.FINISHED)
	check(Array(Challenges.last_result["tags"]["assists"]) == ["aim_assist"], "switched on and off mid-run: still tagged (%s)" % [Challenges.last_result["tags"]])
	await _retry()
	h.drive().move_x = 1
	await physics_frames(3)
	Challenges.finish(ChallengeData.Outcome.FINISHED)
	check(Array(Challenges.last_result["tags"]["assists"]).is_empty(), "a new attempt starts clean")


func test_staged_descent_goals_rank_and_stage_cleared() -> void:
	Game.set_ability(&"dash", true)
	var cleared: Array = []
	h.listen(EventBus.challenge_stage_cleared, func(id: String, st: String, f: int, hits: int, deaths: int, m: int) -> void: cleared.append([id, st, f, hits, deaths, m]))
	check(await h.start(H.fx(H.STAGED), {}), "staged run started")
	h.player().combat.take_damage(1, Vector2.ZERO, 0.0, false, "test")
	var hp := h.player().combat.health
	h.drive().move_x = 1
	check(await h.until(func() -> bool: return cleared.size() == 1, 400), "stage A goal")
	check(cleared.size() == 1 and cleared[0][1] == "stage_a" and cleared[0][3] == 1 and cleared[0][4] == 0, "the split carries hits and deaths (%s)" % [cleared])
	check(await h.until(func() -> bool: return SceneRouter.current_room_path == H.STAGE_B and not SceneRouter.transitioning and h.player() != null, 60), "stage B loaded")
	check(h.player().combat.health == hp, "health carries between stages (%d vs %d)" % [h.player().combat.health, hp])
	check(Challenges.current_title().contains("Stage B"), "the title names the stage (%s)" % Challenges.current_title())
	h.drive().move_x = 1
	check(await h.until(func() -> bool: return not _finished.is_empty(), 400), "finished at the last goal")
	var res := Challenges.last_result
	var stages: Array = res.get("stages", [])
	check(stages.size() == 2 and _finished[0][1] == ChallengeData.Outcome.FINISHED, "two stage results (%s)" % [stages])
	if stages.size() == 2:
		var want := RankTable.mean_score([stages[0]["score"], stages[1]["score"]])
		check(int(res["value"]) == want and _finished[0][2] == want, "the value is the mean stage score (%d vs %d)" % [int(res["value"]), want])
		check(int(res["medal"]) == H.fx(H.STAGED).rank_table.run_rank(stages) and int(res["medal"]) < 4, "a hit keeps the run off the top tier (%d)" % int(res["medal"]))
	check(not Challenges.records.best_stage("fx_staged", 1, "stage_a").is_empty(), "stage bests recorded")
	check(Challenges.has_stages(), "a descent has stages")
