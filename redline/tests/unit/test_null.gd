extends RedlineTestCase
## The Deep Rig strata (M9 D3 §3, run by T04's Challenges; T10, D-154/D-155;
## 'null' is an internal id, the player reads "Deep Rig"): the data and the
## NullRules lint, the rooms off the map, the story contract (the depth flag
## is produced, eight future flags, the redline ending still out of reach,
## the knowledge lint), the unlock and the Dash requirement, the run rules
## (a death or a reset restarts the stratum, the profile keeps nothing but
## the depth flag), ranks that never read Settings, and the descent's splits.

const H := preload("res://tests/fixtures/challenges/ChallengeHarness.gd")
const IDS := ["null_descent", "null_static_lane", "null_breaker_run", "null_floor"]
const PIT_IDS := ["pit_style", "pit_endurance"]
const STATIC_LANE := "res://world/rooms/challenge/NullStaticLane.tscn"
const BREAKER_RUN := "res://world/rooms/challenge/NullBreakerRun.tscn"
const FLOOR := "res://world/rooms/challenge/NullFloor.tscn"
const DEPTH := "null_depth_reached"

var h: H
var _cleared: Array = []
var _finished: Array = []


func before_each() -> void:
	h = H.new(self, "null")
	h.setup()
	ChallengeLibrary.data_dir = ChallengeLibrary.DEFAULT_DIR
	ChallengeLibrary.clear_cache()
	_cleared = []
	_finished = []
	h.listen(EventBus.challenge_stage_cleared, func(id: String, st: String, f: int, hits: int, deaths: int, m: int) -> void:
		_cleared.append([id, st, f, hits, deaths, m]))
	h.listen(EventBus.challenge_finished, func(id: String, o: int, v: int, m: int, nb: bool) -> void: _finished.append([id, o, v, m, nb]))


func after_each() -> void:
	await h.teardown()


func _ch(id: String) -> ChallengeData:
	return ChallengeLibrary.by_id(id)


## Starts a Deep Rig challenge with Dash on the profile; enemies pacified.
func _start(id: String) -> bool:
	Game.set_ability(&"dash", true)
	var ok: bool = await h.start(_ch(id), {})
	check(ok, "%s started" % id)
	if ok:
		_pacify()
	return ok


func _pacify() -> void:
	for e in h.room().find_children("*", "Enemy", true, false):
		(e as Enemy).ai_enabled = false
		(e as Enemy).set_ai(Enemy.AI.IDLE)


## Fires the live room's goal for the current stage (as Rook reaching it).
func _reach_goal() -> void:
	for g in h.room().find_children("*", "ChallengeGoal", true, false):
		(g as ChallengeGoal)._reach()
		return


func _wait_room(path: String) -> bool:
	return await h.until(func() -> bool: return SceneRouter.current_room_path == path and not SceneRouter.transitioning \
		and h.player() != null and Challenges.phase() == Challenges.Phase.RUNNING, 120)


func test_null_challenges_validate_and_rules_clean() -> void:
	for id in IDS:
		var ch := _ch(id)
		check(ch != null, "%s shipped" % id)
		if ch == null:
			continue
		check(ch.validate().is_empty(), "%s validates: %s" % [id, ch.validate()])
		check(ch.group == ChallengeData.Group.NULL and ch.score_kind == ChallengeData.ScoreKind.RANK \
			and ch.end_on == ChallengeData.EndOn.GOAL and ch.on_death == ChallengeData.OnDeath.RESTART_STAGE, "%s: a Deep Rig RANK run" % id)
		check(ch.kit.use_profile_loadout and ch.kit.reactor_mode == -1, "%s: the player's own loadout and Core mode" % id)
		check(ch.rank_table.resource_path == "res://data/challenges/null_ranks.tres", "%s ranks on null_ranks.tres" % id)
		var v := ContentValidator.new()
		v.check_resource(ch, "res://data/challenges/%s.tres" % id)
		check(v.errors.is_empty(), "%s lints clean: %s" % [id, v.errors])
	check(_ch("null_descent").stages.map(func(s: ChallengeStage) -> String: return s.id) == ["static_lane", "breaker_run", "floor"],
		"the descent runs the three strata in order")
	# A stratum's own stage and the descent's copy of it agree (pars, rooms).
	for single in ["null_static_lane", "null_breaker_run", "null_floor"]:
		var a := _ch(single).stages[0]
		var b: ChallengeStage = _ch("null_descent").stages.filter(func(s: ChallengeStage) -> bool: return s.id == a.id)[0]
		check(a.room == b.room and a.entry == b.entry and a.par_s == b.par_s and a.redline_s == b.redline_s and a.boss_id == b.boss_id,
			"%s matches its descent stage" % single)
	var ranks := load("res://data/challenges/null_ranks.tres") as RankTable
	check(ranks.validate().is_empty() and Array(ranks.thresholds) == [0, 450, 650, 820, 900], "null_ranks: D3 §3.3 values")
	check(not "rank_names" in ranks, "no rank names of its own: RankLadder tiers (R10.2)")
	var v2 := ContentValidator.new()
	NullRules.run(v2)
	check(v2.errors.is_empty(), "NullRules clean: %s" % [v2.errors])


func test_null_rooms_off_map_totals_unchanged_22_5_5() -> void:
	for path in DataDir.list_scenes(NullRules.ROOM_DIR):
		check(Game.world_map.room(path.get_file().get_basename()) == null, "%s is off the world map" % path.get_file())
		check(not SliceStats.room_paths().has(path), "%s is not a district room" % path.get_file())
		var v := ContentValidator.new().check_room(path, false)
		check(v.errors.is_empty(), "%s validates: %s" % [path.get_file(), v.errors])
	check(not ContentValidator.WORLD_ROOM_DIRS.has(NullRules.ROOM_DIR) and ContentValidator.OFF_MAP_DIRS.has(NullRules.ROOM_DIR), "NU-2 folders")
	SliceStats.clear_cache()
	var t := SliceStats.totals()
	check((t["secret_ids"] as Array).size() == 22 and int(t["fragments"]) == 5 and int(t["core_shards"]) == 5,
		"slice totals unchanged 22/5/5 (%d/%d/%d)" % [(t["secret_ids"] as Array).size(), t["fragments"], t["core_shards"]])


func test_fixture_room_with_anchor_is_error() -> void:
	var room := Room.new()
	var anchor := Anchor.new()
	anchor.name = "Anchor1"
	room.add_child(anchor)
	var wall := BreakableWall.new()
	wall.name = "Breakable1"
	room.add_child(wall)
	var v := ContentValidator.new()
	NullRules.check_room(room, "res://world/rooms/challenge/Fixture.tscn", v)
	room.free()
	check(v.errors.size() == 2 and v.errors[0].begins_with("[NU-1]") and v.errors[0].contains("Anchor1"), "an Anchor and a wall are NU-1 errors: %s" % [v.errors])
	# NU-5 and NU-4 on made-up data.
	var bad := (load("res://data/enemies/needle_null.tres") as EnemyData).duplicate(true) as EnemyData
	check(bad.scrap_drop == 0, "needle_null drops no Scrap")
	var k: Enemy = (load("res://bosses/variants/WardenKrailNull.tscn") as PackedScene).instantiate()
	k.get_node("Behavior").set("phase2_telegraph_scale", 0.5)
	var v2 := ContentValidator.new()
	NullRules.check_variant(k, "res://bosses/variants/WardenKrailNull.tscn", v2)
	k.free()
	check(v2.errors.size() == 1 and v2.errors[0].contains("[NU-4]"), "a telegraph scale under 0.6 is NU-4: %s" % [v2.errors])


func test_knowledge_lint_exempts_challenge_rooms() -> void:
	var lint := load(KnowledgeLint.PATH) as KnowledgeLint
	check(lint.is_exempt("res://world/rooms/challenge/NullFloor.tscn"), "challenge rooms are exempt (room-internal labels)")
	check(not lint.is_exempt("res://data/challenges/null_floor.tres"), "challenge data is not exempt (R10.6)")
	check(not lint.is_exempt("res://data/districts/null.tres"), "the district banner is not exempt (R10.6)")
	check(Array(lint.exempt_dirs) == ["res://data/endings", "res://world/rooms/challenge"], "only the rooms were added (%s)" % [lint.exempt_dirs])


func test_null_text_passes_knowledge_lint() -> void:
	var lint := load(KnowledgeLint.PATH) as KnowledgeLint
	var texts: Array = []
	for id in IDS + PIT_IDS:
		var ch := _ch(id)
		texts.append_array([[id, ch.title], [id, ch.description], [id, ch.requires_text], [id, ch.locked_hint]])
		for st in ch.stages:
			texts.append([id, st.title])
	var theme := load("res://data/districts/null.tres") as DistrictTheme
	texts.append(["null.tres", theme.district_name])
	check(theme.district_name == "Deep Rig", "the banner reads Deep Rig")
	for pair: Array in texts:
		check(lint.hits(String(pair[1])).is_empty(), "%s: '%s' has knowledge-lint hits %s" % [pair[0], pair[1], lint.hits(String(pair[1]))])
		check(not String(pair[1]).to_lower().contains("the null"), "%s never says 'The Null'" % pair[0])
	for path in DataDir.list_scenes(NullRules.ROOM_DIR):
		var room := (load(path) as PackedScene).instantiate() as Room
		check(room.district_name in ["Deep Rig", "Training Pit"], "%s district '%s'" % [path.get_file(), room.district_name])
		room.free()


func test_future_flags_8_and_redline_ending_still_unreachable() -> void:
	var future := FutureFlagSet.shared()
	check(future.flags().size() == 8 and not future.has_flag(DEPTH), "eight future flags, the depth flag is not one")
	var redline := EndingResolver.by_id("redline")
	var conds := Array(redline.all_conditions())
	check(conds.any(func(c: String) -> bool: return c.ends_with(DEPTH)), "redline still reads the depth flag")
	check(conds.any(func(c: String) -> bool: return future.is_future_condition(c)), "redline still needs a future flag (Act V): %s" % [conds])
	check(redline.content_check().is_empty(), "redline content_check clean: %s" % [redline.content_check()])


func test_null_depth_reached_has_producer() -> void:
	var v := ContentValidator.new().run(true)
	var paths: Array = v.producers.get(DEPTH, [])
	check(paths.has("res://data/challenges/null_floor.tres") and paths.has("res://data/challenges/null_descent.tres"),
		"the Floor and the descent produce it (%s)" % [paths])
	check(Array(v.errors).filter(func(e: String) -> bool: return e.contains(DEPTH)).is_empty(), "no future-flag error for it")


func test_null_open_and_dash_requirement() -> void:
	var ch := _ch("null_static_lane")
	check(not ChallengeLibrary.unlocked(ch), "locked without null_open")
	Game.set_flag("act1_complete")
	check(Game.has_flag("null_open") and ChallengeLibrary.unlocked(ch), "act1_complete derives null_open: unlocked")
	check(ch.requires_text == "The rig needs the Dash module." and Array(ch.requires) == ["ability:dash"], "the requirement and its line")
	Game.set_ability(&"dash", false)
	check(not ChallengeLibrary.profile_holds(ch.requires[0]), "the profile lacks Dash")
	await h.goto(H.WORLD_A, &"start")
	check(not Challenges.start(ch, {"room": H.WORLD_A, "entry": &"start"}), "start refused without Dash")
	check(not Challenges.active(), "no run")
	Game.set_ability(&"dash", true)
	check(await h.start(ch, {"room": H.WORLD_A, "entry": &"start"}), "with Dash it starts")


func test_death_restarts_stage_full_health_no_profile_deaths() -> void:
	var deaths_before := Game.state.deaths
	if not await _start("null_static_lane"):
		return
	var profile := Game.held_profile
	var p := h.player()
	var p_id := p.get_instance_id()
	p.combat.take_damage(99, Vector2.ZERO, 0.0, false, "test")
	check(await h.until(func() -> bool: return h.player() != null and h.player().get_instance_id() != p_id and not SceneRouter.transitioning, 240),
		"the stratum restarted")
	check(SceneRouter.current_room_path == STATIC_LANE, "the same stratum")
	check(h.player().combat.health == h.player().combat.config.max_health, "full health on the restart (%d)" % h.player().combat.health)
	check(Challenges.session.stage_deaths == 1 and Challenges.attempt() == 1, "one stage death, the same attempt")
	check(profile.deaths == deaths_before and profile.dropped_scrap.is_empty(), "the profile counts no death and drops no Scrap")
	check(_finished.is_empty(), "a death never ends a Deep Rig run")


func test_reset_restarts_stage() -> void:
	if not await _start("null_descent"):
		return
	_reach_goal()
	check(await _wait_room(BREAKER_RUN), "stage two (Breaker Run)")
	var resets: Array = []
	h.listen(EventBus.challenge_reset, func(_id: String, r: StringName) -> void: resets.append(r))
	var p_id := h.player().get_instance_id()
	Challenges.restart(&"reset")
	check(await h.until(func() -> bool: return h.player() != null and h.player().get_instance_id() != p_id and not SceneRouter.transitioning, 60),
		"the room reloaded")
	check(SceneRouter.current_room_path == BREAKER_RUN and Challenges.stage_index() == 1, "the reset restarts the current stratum, not the descent")
	check(resets == [&"reset"] and Challenges.attempt() == 1, "same attempt (%s)" % [resets])
	check(_cleared.size() == 1, "stage one stays cleared")
	Challenges.restart_run()
	check(await _wait_room(STATIC_LANE), "restart descent goes back to Static Lane")
	check(Challenges.stage_index() == 0 and Challenges.attempt() == 2, "a new attempt from stage one")


func test_profile_unchanged_after_run_except_depth_flag() -> void:
	Game.set_ability(&"dash", true)
	Game.set_flag("act1_complete")
	var before := Game.state.to_dict()
	if not await _start("null_floor"):
		return
	Game.state.flags["null_krail_defeated"] = true
	Game.state.scrap_unbanked = 99
	Challenges.finish(ChallengeData.Outcome.FINISHED)
	Challenges.quit()
	await h.until(func() -> bool: return not Challenges.active() and not SceneRouter.transitioning, 60)
	var after := Game.state.to_dict()
	check(bool(after["flags"].get(DEPTH, false)), "the depth flag landed on the profile")
	(after["flags"] as Dictionary).erase(DEPTH)
	for k: String in before:
		if k == "play_time_sec":
			continue
		check(str(before[k]) == str(after[k]), "profile key %s unchanged (%s vs %s)" % [k, before[k], after[k]])


func test_depth_flag_set_after_restore_any_rank() -> void:
	if not await _start("null_floor"):
		return
	var profile := Game.held_profile
	# Two hits and a slow clock: a low rank still reaches the depth.
	h.player().combat.take_damage(1, Vector2.ZERO, 0.0, false, "test")
	Challenges.rules.hits = 2
	Challenges.session.stage_frames = 60 * 190
	Challenges.clock.frames = 60 * 190
	_reach_goal()
	check(await h.until(func() -> bool: return not _finished.is_empty(), 30), "finished at the Floor's goal")
	if _finished.is_empty():
		return
	check(_finished[0][3] >= 0 and _finished[0][3] < 3, "a low tier (%d)" % _finished[0][3])
	check(not profile.flags.has(DEPTH), "not during the run")
	Challenges.quit()
	check(bool(Game.state.flags.get(DEPTH, false)) and Game.state == profile, "set on the profile after the restore")
	check(bool(SaveManager.load_profile(1).get("flags", {}).get(DEPTH, false)), "and saved")


func test_rank_never_reads_settings() -> void:
	var table := load("res://data/challenges/null_ranks.tres") as RankTable
	var st := _ch("null_static_lane").stages[0]
	var cases := [[25.0, 0, 0, 4.0], [31.0, 1, 0, 3.0], [60.0, 3, 1, 1.0], [95.0, 0, 2, 0.0]]
	var plain: Array = []
	for c: Array in cases:
		var s := table.score(c[0], c[1], c[2], c[3], st)
		plain.append([s, table.rank_of(s, c[0], c[1], c[2], st)])
	Settings.reactor_mode = 1
	Settings.damage_assist = 2
	Settings.aim_assist = 2
	Settings.hitstop_scale = 0.5
	Settings.generous_checkpoints = true
	var assisted: Array = []
	for c: Array in cases:
		var s := table.score(c[0], c[1], c[2], c[3], st)
		assisted.append([s, table.rank_of(s, c[0], c[1], c[2], st)])
	check(plain == assisted, "every assist on: the same ranks (%s vs %s)" % [plain, assisted])
	check(plain[0][1] == RankTable.TOP_TIER and plain[1][1] < RankTable.TOP_TIER, "Redline needs no hit and the redline time")
	# The live path: a running stratum counts a hit the same way and ranks the
	# same stage result with every assist off and on.
	_assists(false)
	if not await _start("null_static_lane"):
		return
	var live := func(on: bool) -> Array:
		_assists(on)
		var before := Challenges.rules.hits
		h.player().combat.take_damage(1, Vector2.ZERO, 0.0, false, "test", true)
		var counted := Challenges.rules.hits - before
		Challenges.session.stage_frames = 31 * RunClock.FPS
		Challenges.session.stage_deaths = 0
		Challenges.rules.hits = 1
		var r := Challenges.stage_result()
		return [counted, r["score"], r["tier"], Challenges.projected_rank()]
	var off: Array = live.call(false)
	var on: Array = live.call(true)
	check(off == on and off[0] == 1, "a live stage ranks the same with every assist on (%s vs %s)" % [off, on])
	_assists(false)


func _assists(on: bool) -> void:
	Settings.reactor_mode = 1 if on else 0
	Settings.damage_assist = 2 if on else 0
	Settings.aim_assist = 2 if on else 0
	Settings.hitstop_scale = 0.5 if on else 1.0
	Settings.generous_checkpoints = on


func test_descent_splits_emit_stage_cleared() -> void:
	if not await _start("null_descent"):
		return
	var rooms := [STATIC_LANE, BREAKER_RUN, FLOOR]
	for i in 3:
		check(await _wait_room(rooms[i]), "stage %d room" % (i + 1))
		_pacify()
		await physics_frames(10)
		_reach_goal()
	check(await h.until(func() -> bool: return not _finished.is_empty(), 30), "the descent finished at the Floor")
	check(_cleared.map(func(c: Array) -> String: return c[1]) == ["static_lane", "breaker_run", "floor"], "three stage splits in order (%s)" % [_cleared])
	check(Challenges.clock.splits.size() == 3, "three clock splits (%s)" % [Challenges.clock.splits])
	if not _finished.is_empty():
		var stages: Array = Challenges.last_result.get("stages", [])
		check(stages.size() == 3 and _finished[0][1] == ChallengeData.Outcome.FINISHED, "three stage results")


func test_act1_max_state_leaves_null_depth_unset() -> void:
	var restore := FlagSandbox.begin()
	FlagSandbox.apply_act1_max_state()
	check(Game.has_flag("null_open"), "null_open derived from act1_complete (D-154)")
	check(not Game.state.flags.has(DEPTH), "the depth flag stays unset (R10.8)")
	check(not Game.state.flags.has("null_krail_defeated") and not Game.state.flags.has("null_ns1_latched"), "no rig bookkeeping flag")
	restore.call()


func test_dev_null_page_builds_and_actions_taint() -> void:
	var c: DevConsole = load("res://ui/menus/DevConsole.gd").new()
	add_child(c)
	c.open_menu()
	c.go(&"null")
	var labels: Array = []
	for n in c._body.get_children():
		if n is Button and not n.is_queued_for_deletion():
			labels.append((n as Button).text)
	for id in IDS:
		check(labels.has("Start: %s" % _ch(id).title), "a start row for %s (%s)" % [id, labels])
	check(labels.has("Clear Deep Rig records") and labels.size() <= DevConsole.PAGE_ROWS + 2, "rows fit (%s)" % [labels])
	var height := await menu_height(c)
	check(height <= 270.0, "the page fits (%.0f px)" % height)
	c.close_menu()
	c.queue_free()
	check(not Game.state.dev_tainted, "a clean profile")
	NullDevActions.grant_open()
	check(Game.has_flag("null_open") and Game.state.dev_tainted, "grant_open sets null_open and taints")
	NullDevActions.set_depth(true)
	check(Game.has_flag(DEPTH), "the depth flag set")
	NullDevActions.set_depth(false)
	check(not Game.has_flag(DEPTH), "and cleared")
	# A dev start ignores the Dash requirement; the records keep the real id.
	Game.set_ability(&"dash", false)
	await h.goto(H.WORLD_A, &"start")
	check(NullDevActions.start("null_static_lane"), "a dev start without Dash")
	check(await _wait_room(STATIC_LANE) and Challenges.current_id() == "null_static_lane", "running Static Lane")
	check(NullDevActions.summary().contains("null_open yes"), "summary: %s" % NullDevActions.summary())
	# Mid-run Game.state is the sandbox: the flag rows refuse (and show it).
	check(not NullDevActions.flags_editable() and not NullDevActions.set_depth(true) and not NullDevActions.grant_open(),
		"no flag edits mid-run")
	check(not ChallengeLibrary.profile_holds("flag:" + DEPTH), "the profile's depth flag untouched")
	var c2: DevConsole = load("res://ui/menus/DevConsole.gd").new()
	add_child(c2)
	c2.open_menu()
	c2.go(&"null")
	var flag_rows := c2._body.get_children().filter(func(n: Node) -> bool:
		return n is Button and not n.is_queued_for_deletion() and ((n as Button).text.contains("Grant null_open") or (n as Button).text.contains("Depth flag:")))
	check(flag_rows.size() == 2 and flag_rows.all(func(b: Button) -> bool: return b.disabled and b.text.contains("not mid-run")),
		"the flag rows are disabled mid-run")
	c2.close_menu()
	c2.queue_free()
