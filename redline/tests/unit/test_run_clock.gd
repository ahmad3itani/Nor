extends RedlineTestCase
## RunClock and fast reset (M9 D2 §3.5-§3.6, R04.5, R04.7): only running,
## unpaused, non-transition frames count; FIRST_INPUT starts on the first
## real input; m:ss.cc; reset is back in control within 3 frames; past the
## tap window (and until the player has used reset once) it needs a hold,
## unless the hold setting is off; reduced hitstop is tagged.

const H := preload("res://tests/fixtures/challenges/ChallengeHarness.gd")

var h: H


func before_each() -> void:
	h = H.new(self, "run_clock")
	h.setup()


func after_each() -> void:
	H.reset_key(false)
	await h.teardown()


func _start_trial() -> bool:
	await h.goto(H.WORLD_A, &"start")
	return await h.start(H.fx(H.TRIAL), {"room": H.WORLD_A, "entry": &"start"})


func test_counts_only_running_unpaused_non_transition_frames() -> void:
	var c := RunClock.new()
	c.tick()
	check(c.frames == 0, "a stopped clock never counts")
	c.start()
	for i in 5:
		c.tick()
	check(c.frames == 5 and c.split() == 5 and c.splits == PackedInt32Array([5]), "running ticks and splits")
	c.reset()
	check(c.frames == 0 and not c.running and c.splits.is_empty(), "reset")
	check(await _start_trial(), "run started")
	var src := h.drive()
	src.move_x = 1
	await physics_frames(10)
	var f := Challenges.clock.frames
	check(f >= 8 and f <= 10, "counts while running (%d)" % f)
	get_tree().paused = true
	await physics_frames(6)
	check(Challenges.clock.frames == f, "a paused tree counts nothing (%d vs %d)" % [Challenges.clock.frames, f])
	get_tree().paused = false
	await physics_frames(1)
	var g := Challenges.clock.frames
	SceneRouter.transitioning = true
	await physics_frames(5)
	check(Challenges.clock.frames == g, "transition frames never count (%d vs %d)" % [Challenges.clock.frames, g])
	SceneRouter.transitioning = false
	await physics_frames(3)
	check(Challenges.clock.frames == g + 3, "counting resumes (%d)" % Challenges.clock.frames)


func test_first_input_start() -> void:
	check(await _start_trial(), "run started")
	var src := h.drive()
	await physics_frames(8)
	check(not Challenges.clock.running and Challenges.clock.frames == 0, "no input, no clock (%d)" % Challenges.clock.frames)
	src.press_jump()
	await physics_frames(1)
	check(Challenges.clock.running and Challenges.clock.frames == 1, "the first input frame counts (%d)" % Challenges.clock.frames)


func test_format_centiseconds() -> void:
	var rows := [[0, "0:00.00"], [1, "0:00.01"], [60, "0:01.00"], [90, "0:01.50"], [3661, "1:01.01"], [36000, "10:00.00"]]
	for r: Array in rows:
		check(RunClock.format(r[0]) == r[1], "format(%d) = %s (want %s)" % [r[0], RunClock.format(r[0]), r[1]])
	check(RunClock.format_delta(-25) == "-0.41" and RunClock.format_delta(66) == "+1.10", "deltas %s %s" % [RunClock.format_delta(-25), RunClock.format_delta(66)])
	check(RunTimerHud.delta_text(66).begins_with("▲") and RunTimerHud.delta_text(-25).begins_with("▼"), "sign AND arrow")


func test_fast_reset_under_three_frames() -> void:
	Challenges.records.mark_reset_used()
	check(await _start_trial(), "run started")
	var src := h.drive()
	src.move_x = 1
	await physics_frames(5)
	var old := h.room()
	H.reset_key(true)
	var frames := 0
	while h.room() == old and frames < 10:
		await get_tree().physics_frame
		frames += 1
	H.reset_key(false)
	check(h.room() != old, "the room reloaded")
	var p := h.player()
	var x0 := p.global_position.x
	h.drive().move_x = 1
	await get_tree().physics_frame
	frames += 1
	check(p.global_position.x > x0, "the new player moves")
	check(frames <= 3, "reset to control in %d physics frames (<= 3)" % frames)
	check(Challenges.clock.frames <= 1 and Challenges.attempt() == 2, "a fresh attempt (f=%d, attempt %d)" % [Challenges.clock.frames, Challenges.attempt()])


func _hold_test(tap_should_reset: bool) -> void:
	var resets: Array = []
	h.listen(EventBus.challenge_reset, func(_id: String, r: StringName) -> void: resets.append(r))
	var old := h.room()
	H.reset_key(true)
	await physics_frames(2)
	H.reset_key(false)
	await physics_frames(2)
	check((resets.size() == 1) == tap_should_reset, "a tap %s (%s)" % ["resets" if tap_should_reset else "does not reset", resets])
	if tap_should_reset:
		return
	check(h.room() == old, "same room after a tap")
	check(Challenges.reset_needs_hold(), "needs a hold")
	H.reset_key(true)
	await physics_frames(10)
	check(Challenges.reset_hold_fraction() > 0.3 and resets.is_empty(), "the HUD arc fills (%.2f)" % Challenges.reset_hold_fraction())
	await physics_frames(14)
	H.reset_key(false)
	await physics_frames(2)
	check(resets == [&"reset"], "the hold resets once (%s)" % [resets])


func test_reset_needs_hold_after_60s() -> void:
	Challenges.records.mark_reset_used()
	check(await _start_trial(), "run started")
	h.drive().move_x = 1
	await physics_frames(2)
	check(not Challenges.reset_needs_hold(), "a short run resets with a tap")
	Challenges.clock.frames = 60 * 61
	await _hold_test(false)


func test_hold_setting_off_makes_tap() -> void:
	Settings.fast_reset_hold = false
	check(not Challenges.records.reset_used(), "never used")
	check(await _start_trial(), "run started")
	h.drive().move_x = 1
	await physics_frames(2)
	Challenges.clock.frames = 60 * 90
	check(not Challenges.reset_needs_hold(), "hold off: every reset is a tap")
	await _hold_test(true)


func test_first_run_reset_needs_hold_until_used() -> void:
	check(await _start_trial(), "run started")
	h.drive().move_x = 1
	await physics_frames(2)
	check(Challenges.reset_needs_hold(), "first use needs the hold even under 60 s")
	await _hold_test(false)
	check(Challenges.records.reset_used(), "used once, recorded")
	h.drive().move_x = 1
	await physics_frames(3)
	check(not Challenges.reset_needs_hold(), "then a tap is enough under 60 s")
	await _hold_test(true)


func test_hitstop_reduced_tagged() -> void:
	Challenges.tag_provider = func() -> PackedStringArray: return PackedStringArray()
	Settings.hitstop_scale = 0.5
	check(await _start_trial(), "run started")
	h.drive().move_x = 1
	await physics_frames(3)
	Challenges.finish(ChallengeData.Outcome.FINISHED)
	var tags: Dictionary = Challenges.last_result.get("tags", {})
	check(Array(tags.get("timing", [])) == ["hitstop_reduced"], "timing tag (%s)" % [tags])
	check(Array(tags.get("assists", [])).is_empty(), "never an assist (%s)" % [tags])


func test_hud_lines_and_debug_line() -> void:
	check(await _start_trial(), "run started")
	var ch := Challenges.current()
	ch.fail_on_damage = true
	h.drive().move_x = 1
	await physics_frames(60)
	var lines := Challenges.hud.lines()
	check(lines.size() >= 2 and lines[0].begins_with(RunClock.format(Challenges.clock.frames)) and lines[0].contains("NO HIT"), "time + rule chip (%s)" % [lines])
	check(lines.size() >= 2 and lines[1] == "Attempt 1", "attempt line (%s)" % [lines])
	check(Challenges.hud.showing(), "shown in a run")
	CinematicMode.hud_hidden = true
	check(not Challenges.hud.showing(), "hidden with the HUD")
	CinematicMode.hud_hidden = false
	Challenges.hud.show_split(-25)
	check(Challenges.hud.lines()[-1] == "▼ -0.41", "split delta line (%s)" % [Challenges.hud.lines()])
	check(Challenges.hud.lines().size() * RunTimerHud.LINE + 2.0 <= RunTimerHud.BLOCK.y, "three lines fit the 24 px block (R04.8)")
	Challenges.hud._toast_time = 0.0
	Challenges.hud.show_reset_chip()
	check(Challenges.reset_needs_hold() and Challenges.hud.lines()[-1].begins_with("Hold "), "the chip asks for a hold before reset was used (%s)" % [Challenges.hud.lines()])
	Challenges.records.mark_reset_used()
	check(not Challenges.reset_needs_hold() and not Challenges.hud.lines()[-1].begins_with("Hold "), "a tap once it was used (%s)" % [Challenges.hud.lines()])
	var dbg := Challenges.debug_lines()
	check(dbg.size() == 1 and dbg[0].begins_with("RUN fx_trial stage 1/1 f="), "debug overlay line (%s)" % [dbg])
	check(DebugOverlay.providers.has(Challenges.debug_lines), "registered as a DebugOverlay provider")
	Challenges.quit()
	await h.until(func() -> bool: return not Challenges.active() and not SceneRouter.transitioning)
	check(Challenges.hud.lines().is_empty() and not Challenges.hud.showing(), "nothing outside runs by default")
	Settings.speedrun_timer = 1
	Game.state.igt_frames = 3661
	check(Challenges.hud.lines() == PackedStringArray(["IGT 1:01.01"]), "the campaign IGT (%s)" % [Challenges.hud.lines()])
	Settings.speedrun_timer = 2
	Challenges.hud._on_speedrun_split("room:WorldA", 100, -3)
	check(Challenges.hud.lines().size() == 2, "a campaign split line (%s)" % [Challenges.hud.lines()])
	EventBus.game_state_reset.emit()
	check(Challenges.hud.lines() == PackedStringArray(["IGT 1:01.01"]), "a load or New Game clears it (%s)" % [Challenges.hud.lines()])
	var world := SceneRouter.current_room_path
	SceneRouter.current_room_path = "res://world/rooms/challenge/X.tscn"
	check(Challenges.hud.lines().is_empty() and not Challenges.hud.showing(), "no campaign IGT off the map (labs are not world rooms either)")
	SceneRouter.current_room_path = world
