extends RedlineTestCase
## ChallengeData and ChallengeLibrary (M9 D2 §2, R04.6/R04.12/R04.13/R04.14/
## R04.25/R04.27): the fixtures validate; medal thresholds are ordered per
## score kind; medal_for edges; the library lists, sorts and drops what a
## demo cannot reach; unlocks read the profile and are sticky; the rig opens
## only after the Act I close; the group-open notice is silent on loads and
## only shows on a live change once the rig is open; the ladder and the config
## are data.

const H := preload("res://tests/fixtures/challenges/ChallengeHarness.gd")

var h: H
var _hints: Array = []


func before_each() -> void:
	h = H.new(self, "challenge_data")
	h.setup()
	_hints = []
	# Only the rig notice (quests and tips use the same HUD hint channel).
	h.listen(EventBus.hint_requested, func(text: String, _s: float) -> void:
		if text.begins_with(Loc.f("New at the Relay training rig: {group}", {"group": ""})):
			_hints.append(text))


func after_each() -> void:
	await h.teardown()


func test_validate_fixture_ok() -> void:
	for p in [H.TRIAL, H.REMATCH, H.STAGED]:
		var ch := load(p) as ChallengeData
		check(ch != null and ch.validate().is_empty(), "%s validates: %s" % [p.get_file(), ch.validate() if ch else "not loaded"])
	var bad := H.fx(H.TRIAL)
	bad.id = "Bad Id"
	bad.finish_exit_target = ""
	bad.unlock_when = "flagx"
	var errs := bad.validate()
	check(errs.size() >= 3, "bad id, missing finish target and a bad condition are errors: %s" % [errs])
	var staged := H.fx(H.STAGED)
	check(staged.stage_count() == 2 and staged.stage_room(1) == H.STAGE_B and staged.stage_entry(1) == &"from_a", "stage accessors")
	check(H.fx(H.TRIAL).stage_count() == 1 and H.fx(H.TRIAL).stage_room(0) == H.WORLD_A, "implicit single stage")


func test_medals_ordered_per_score_kind() -> void:
	var ch := H.fx(H.TRIAL)
	ch.medal_thresholds = PackedInt32Array([450, 900, 1800, 3600])
	check(not ch.validate().is_empty(), "TIME thresholds must descend (frames)")
	ch.score_kind = ChallengeData.ScoreKind.SCORE
	check(ch.validate().is_empty(), "the same list ascends for SCORE: %s" % [ch.validate()])
	ch.medal_thresholds = PackedInt32Array([400, 300, 200, 100])
	check(not ch.validate().is_empty(), "SCORE thresholds must ascend")
	ch.medal_thresholds = PackedInt32Array([100, 200])
	check(not ch.validate().is_empty(), "exactly 4 thresholds")
	var rank := H.fx(H.STAGED)
	check(rank.medal_thresholds.is_empty() and rank.validate().is_empty(), "RANK uses its rank table")


func test_medal_for_edges() -> void:
	var t := H.fx(H.TRIAL)
	var rows := [[-1, -1], [5000, 0], [3601, 0], [3600, 1], [1801, 1], [1800, 2], [900, 3], [451, 3], [450, 4], [1, 4]]
	for r: Array in rows:
		check(t.medal_for(r[0]) == r[1], "TIME medal_for(%d) = %d (want %d)" % [r[0], t.medal_for(r[0]), r[1]])
	var s := H.fx(H.TRIAL)
	s.score_kind = ChallengeData.ScoreKind.SCORE
	s.medal_thresholds = PackedInt32Array([100, 200, 300, 400])
	for r: Array in [[0, 0], [99, 0], [100, 1], [299, 2], [400, 4], [9999, 4]]:
		check(s.medal_for(r[0]) == r[1], "SCORE medal_for(%d) = %d (want %d)" % [r[0], s.medal_for(r[0]), r[1]])
	var k := H.fx(H.STAGED)
	check(k.medal_for(0) == 0 and k.medal_for(900) == 4 and k.medal_for(-1) == -1, "RANK delegates to the table")
	check(t.is_better(100, 200) and not t.is_better(200, 100) and t.is_better(5, -1) and not t.is_better(-1, 5), "TIME is_better")
	check(s.is_better(200, 100) and not s.is_better(100, 200), "SCORE is_better")


func test_library_lists_and_filters_demo() -> void:
	var ids: Array = ChallengeLibrary.all().map(func(c: ChallengeData) -> String: return c.id)
	check(ids == ["fx_staged", "fx_rematch", "fx_trial"], "fixtures sorted by group (Deep Rig first): %s" % [ids])
	check(ChallengeLibrary.by_id("fx_trial") != null and ChallengeLibrary.by_id("nope") == null, "by_id")
	BuildInfo.force_allowed[H.STAGE_B] = true
	BuildInfo.force_allowed[H.STAGE_B] = false
	ids = ChallengeLibrary.all().map(func(c: ChallengeData) -> String: return c.id)
	check(not ids.has("fx_staged") and ids.has("fx_trial"), "a stage room outside the demo drops the run: %s" % [ids])
	check(ChallengeLibrary.by_id("fx_staged") != null, "by_id still finds it (start refuses it)")
	check(not Challenges.start(ChallengeLibrary.by_id("fx_staged"), {}), "start refuses a demo-blocked run")
	BuildInfo.force_allowed.clear()
	check(ChallengeLibrary.all().size() == 3, "all back")


func test_library_drops_demo_blocked_finish() -> void:
	BuildInfo.force_allowed[H.WORLD_B] = false
	var ids: Array = ChallengeLibrary.all().map(func(c: ChallengeData) -> String: return c.id)
	check(not ids.has("fx_trial"), "a finish past the demo border drops the trial: %s" % [ids])
	check(ids.has("fx_rematch"), "others stay")


func test_unlocks_on_profile_state() -> void:
	for ch in ChallengeLibrary.all():
		check(not ChallengeLibrary.unlocked(ch), "fresh profile: %s locked" % ch.id)
	Game.state.flags["collector_drone_defeated"] = true
	check(ChallengeLibrary.unlocked(ChallengeLibrary.by_id("fx_trial")) and ChallengeLibrary.unlocked(ChallengeLibrary.by_id("fx_rematch")), "the Collector unlocks its fixtures")
	check(not ChallengeLibrary.unlocked(ChallengeLibrary.by_id("fx_staged")), "the Deep Rig fixture stays locked")
	Game.state.flags["null_open"] = true
	check(ChallengeLibrary.unlocked(ChallengeLibrary.by_id("fx_staged")), "null_open unlocks it")
	Game.state.flags["null_open"] = false
	# Mid-run the sandbox holds kit flags: unlocks still read the profile.
	var sb := ProfileSandbox.begin(ProfileSandbox.kit_state(H.fx(H.STAGED).kit, null, Game.state), PlayerAbilities.new(), false)
	Game.state.flags["null_open"] = true
	check(not ChallengeLibrary.unlocked(ChallengeLibrary.by_id("fx_staged")), "a sandbox flag never unlocks")
	sb.restore(false)


func test_content_flags_consumes_unlock_and_produces_on_finish() -> void:
	var ch := H.fx(H.STAGED)
	var cf := ch.content_flags()
	check(Array(cf["produces"]) == ["fx_depth_reached"], "produces on_finish_flags (%s)" % [cf])
	check(Array(cf["conditions"]) == ["flag:null_open", "ability:dash"], "consumes unlock + requires (%s)" % [cf])
	var v := ContentValidator.new()
	v.check_resource(ch, "res://data/challenges/fx_staged.tres")
	check(v.produced.has("fx_depth_reached") and v.consumed.has("null_open"), "the validator sees both sides")
	check(v.errors.is_empty(), "no errors: %s" % [v.errors])


func test_rank_ladder_from_data() -> void:
	RankLadder.clear_cache()
	var names: Array = []
	for i in RankLadder.count():
		names.append(RankLadder.name(i))
	check(names == ["Clear", "Bronze", "Silver", "Gold", "Redline"], "names from rank_ladder.tres (%s)" % [names])
	check(RankLadder.name(-1) == "" and RankLadder.name(9) == "", "out of range")
	check(RankLadder.shared().resource_path == RankLadder.PATH and RankLadder.shared().validate().is_empty(), "the data file validates")
	var bad := RankLadder.new()
	bad.names = PackedStringArray(["C", "B", "A", "S", "Redline"])
	check(bad.validate().size() >= 4, "style letters are refused as medal names: %s" % [bad.validate()])


func test_unlocks_sticky_after_flag_reset() -> void:
	await h.goto(H.WORLD_A, &"start")
	Game.set_flag("collector_drone_defeated")
	check(Challenges.records.ever_unlocked("fx_trial"), "recorded on the live flag")
	Game.set_flag("collector_drone_defeated", false)
	check(ChallengeLibrary.unlocked(ChallengeLibrary.by_id("fx_trial")), "still unlocked once the flag resets (NG+)")
	check(not ChallengeLibrary.unlocked(ChallengeLibrary.by_id("fx_staged")), "never unlocked stays locked")


func test_unlock_records_are_global() -> void:
	Game.state.flags["collector_drone_defeated"] = true
	ChallengeLibrary.record_unlocks()
	Challenges.records.reload()
	check(Challenges.records.ever_unlocked("fx_rematch"), "records.json keeps it")
	var s := FileAccess.get_file_as_string(Challenges.records.path())
	check(s.contains("ever_unlocked") and s.contains("fx_rematch"), "in the global store, not the profile")


func test_reveal_when_defaults_to_unlock_when() -> void:
	var ch := H.fx(H.TRIAL)
	check(ch.reveal_condition() == ch.unlock_when, "empty reveal_when = unlock_when")
	ch.reveal_when = "flag:met_orr"
	check(ch.reveal_condition() == "flag:met_orr", "set reveal_when wins")
	check(not ChallengeLibrary.revealed(ch), "not yet revealed")
	Game.state.flags["met_orr"] = true
	check(ChallengeLibrary.revealed(ch) and not ChallengeLibrary.unlocked(ch), "revealed before unlocked")
	check(Array(ch.content_flags()["conditions"]).has("flag:met_orr"), "content_flags consumes reveal_when")
	ch.reveal_when = "bogus"
	check(not ch.validate().is_empty(), "validate checks the grammar")


func test_challenge_config_validates() -> void:
	ChallengeConfig.clear_cache()
	var c := ChallengeConfig.shared()
	check(c.resource_path == ChallengeConfig.PATH and c.validate().is_empty(), "the data file validates: %s" % [c.validate()])
	check(is_equal_approx(c.fast_reset_tap_window_s, 60.0) and is_equal_approx(c.fast_reset_hold_s, 0.35) and c.pb_board_size == 10, "D2 values")
	check(c.bot_margin >= 1.0 and is_equal_approx(c.silver_floor_mult, 1.5) and is_equal_approx(c.silver_floor_add_s, 3.0), "medal tunables")
	check(c.group_titles.size() == ChallengeData.Group.size() and not c.group_titles.has("The Null"), "one title per group, no knowledge-lint term")
	var bad := ChallengeConfig.new()
	bad.bot_margin = 0.9
	check(not bad.validate().is_empty(), "bot_margin < 1 is an error")


func _write_save(extra_flags: Dictionary) -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(H.SAVE_V3))
	var flags: Dictionary = d.get("flags", {})
	flags.merge(extra_flags, true)
	d["flags"] = flags
	SaveManager.save_profile(1, d)


func test_group_notice_silent_on_load() -> void:
	await h.goto(H.WORLD_A, &"start")
	_write_save({"collector_drone_defeated": true, "act1_complete": true})
	check(Game.load_game(1), "loaded")
	await physics_frames(2)
	check(Challenges.records.ever_unlocked("fx_trial") and Challenges.records.ever_unlocked("fx_staged"), "recorded on load")
	check(_hints.is_empty(), "no hint on a catch-up load (%s)" % [_hints])
	Game.set_flag("fx_unrelated_flag")
	await physics_frames(2)
	check(_hints.is_empty(), "and none later for groups already open (%s)" % [_hints])


func test_group_notice_only_live_after_rig_open() -> void:
	await h.goto(H.WORLD_A, &"start")
	Game.set_flag("collector_drone_defeated")
	await physics_frames(2)
	check(Challenges.records.ever_unlocked("fx_trial"), "recorded while the rig is closed")
	check(_hints.is_empty(), "no notice before the rig opens (%s)" % [_hints])
	Game.set_flag("act1_complete")
	await physics_frames(2)
	check(_hints.size() == 1, "one notice when the rig opens (%s)" % [_hints])
	if _hints.size() == 1:
		var text: String = _hints[0]
		check(text.contains("Boss Rematch") and text.contains("Time Trial") and text.contains("Deep Rig"), "names the groups: %s" % text)
	Game.set_flag("fx_unrelated_flag")
	await physics_frames(2)
	check(_hints.size() == 1, "never twice (%s)" % [_hints])


func test_group_notice_blocked_is_dropped() -> void:
	await h.goto(H.WORLD_A, &"start")
	Challenges.quiet_notices = true
	Game.set_flag("collector_drone_defeated")
	Game.set_flag("act1_complete")
	await physics_frames(2)
	check(_hints.is_empty(), "quiet (tours): no notice")
	Challenges.quiet_notices = false
	Game.set_flag("fx_unrelated_flag")
	await physics_frames(2)
	check(_hints.is_empty(), "a blocked notice is dropped, not queued (%s)" % [_hints])


## The real path: the Act I close sets act1_complete under its locking
## scene. The notice is owed, not dropped, and shows once free play resumes.
func test_group_notice_owed_through_locking_scene() -> void:
	var room := await h.goto(H.WORLD_A, &"start")
	Game.set_flag("collector_drone_defeated")
	await physics_frames(2)
	var wait := SeqWait.new()
	wait.seconds = 0.3
	var flag := SeqFlag.new()
	flag.flags = PackedStringArray(["act1_complete"])
	var tail := SeqWait.new()
	tail.seconds = 0.3
	var seq := SequenceData.new()
	seq.id = "test_rig_close"
	seq.steps = [wait, flag, tail] as Array[SequenceStep]
	seq.lock_input = true
	seq.hide_hud = false
	seq.letterbox = false
	CinematicMode.set_mode(CinematicMode.Mode.AUTO)
	CinematicMode.auto_speed = 1.0
	var done: Array = []
	var play := func() -> void: done.append(await Cinematics.play(seq, SequenceContext.for_room(room)))
	play.call()
	check(await h.until(func() -> bool: return Game.has_flag("act1_complete"), 120), "the flag is set mid-scene")
	check(Cinematics.locks_input(), "while the scene locks input")
	await physics_frames(3)
	check(_hints.is_empty(), "no notice under the scene (%s)" % [_hints])
	check(not Challenges.records.group_announced(ChallengeData.Group.TIME_TRIAL), "the group is not marked announced yet")
	check(await h.until(func() -> bool: return not done.is_empty(), 120), "the scene ends")
	check(await h.until(func() -> bool: return _hints.size() == 1, 30), "the notice shows in free play (%s)" % [_hints])
	if _hints.size() == 1:
		var text: String = _hints[0]
		check(text.contains("Boss Rematch") and text.contains("Time Trial") and text.contains("Deep Rig"), "names every group opened meanwhile: %s" % text)
	await physics_frames(20)
	check(_hints.size() == 1, "once (%s)" % [_hints])
	CinematicMode.reset()


func test_validate_rejects_unreachable_finish_and_death_end() -> void:
	var ch := H.fx(H.TRIAL)
	ch.finish_room = ch.start_room
	check(ch.validate().is_empty(), "finish_room = start_room is fine (%s)" % [ch.validate()])
	ch.finish_room = H.WORLD_B
	check(Array(ch.validate()).any(func(e: String) -> bool: return e.contains("finish_room")), "another finish room is unreachable while exits are off")
	ch.finish_room = ""
	ch.end_on = ChallengeData.EndOn.DEATH
	ch.on_death = ChallengeData.OnDeath.END_RUN
	check(Array(ch.validate()).any(func(e: String) -> bool: return e.contains("DEATH needs")), "DEATH needs on_death FINISH")
	ch.on_death = ChallengeData.OnDeath.FINISH
	check(ch.validate().is_empty(), "a survival run validates (%s)" % [ch.validate()])


func test_rig_closed_before_act1_complete() -> void:
	Game.state.flags["collector_drone_defeated"] = true
	check(not ChallengeLibrary.rig_open() and not ChallengeLibrary.any_unlocked(), "a first playthrough: the rig stays closed")
	var data := Game.state.to_dict()
	check(not ChallengeLibrary.any_unlocked_for(data) and not Challenges.any_unlocked_for(data), "the title row stays hidden")
	Game.state.flags["act1_complete"] = true
	check(ChallengeLibrary.rig_open() and ChallengeLibrary.any_unlocked(), "open after the Act I close")
	check(Challenges.any_unlocked_for(Game.state.to_dict()), "title row from a peeked save")
	Game.state.flags["act1_complete"] = false
	Game.state.flags["ng_cycle"] = 1
	check(ChallengeLibrary.rig_open() and ChallengeLibrary.any_unlocked_for(Game.state.to_dict()), "NG+ keeps it open")
	check(not ChallengeLibrary.any_unlocked_for({}), "no save, no row")
