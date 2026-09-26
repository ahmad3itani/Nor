extends RedlineTestCase
## M4 analysis: known sessions in, known numbers out; plus one real recorded
## RouteBot run through the pipeline (record -> file -> report -> heatmap).

const TEST_DIR := "user://test_playtest_report"


func after_each() -> void:
	Playtest.end_session("test_done")
	Playtest.allow_headless = false
	Playtest.dir = Playtest.DIR
	# The whole folder goes (test_zz_user_dir_clean, T14).
	AtomicJson.remove_tree(TEST_DIR)
	await physics_frames(1)


## A fake tester: deaths, a moment, idle time, a survey where every answer
## is `good` (true = passes every §44 question).
func _fake(good: bool, variant: String, deaths_in: Array[String]) -> PlaytestSession:
	var s := PlaytestSession.new({"variant": variant, "gpu": "TestGPU", "os": "Test", "refresh_hz": 60})
	s.add_event(0.0, "session_start", "", Vector2.ZERO)
	s.add_event(1.0, "room_enter", "NeonRoofs", Vector2(20, -100))
	for i in deaths_in.size():
		s.add_event(10.0 + i, "death", deaths_in[i], Vector2(800, -60), {"cause": "needle/needle_stab"})
	s.add_event(30.0, "damage", "NeonRoofs", Vector2(820, 40), {"cause": "pit", "amount": 1})
	s.add_event(40.0, "moment", "NeonRoofs", Vector2(760, -100), {"tag": "Confusing / lost", "note": "gap?"})
	s.add_event(61.0, "room_exit", "NeonRoofs", Vector2(2400, -90), {"seconds": 60.0})
	s.add_event(62.0, "room_enter", "NeonRoofs", Vector2(2400, -90))
	s.add_event(900.0, "slice_complete", "WardenTower", Vector2.ZERO, {"play_time": 900.0, "secrets": 4, "dead_air": good})
	# 30 s standing still at x=500, then moving.
	for i in 60:
		s.add_sample(100.0 + i * 0.5, "NeonRoofs", Vector2(500, -100))
	for i in 10:
		s.add_sample(131.0 + i * 0.5, "NeonRoofs", Vector2(520 + i * 30, -100))
	for i in 100:
		s.add_frame(i * 0.016, "NeonRoofs", 12.0 if i != 50 else 60.0, 33.4, 10)
	s.count("hits:blade_light_1", 5)
	s.count("input_pad_s", 30)
	s.count("input_keyboard_s", 90)
	var survey := {}
	for q in Playtest.config.survey:
		match q.kind:
			SurveyQuestion.Kind.SCALE:
				survey[q.id] = 5 if good else 2
			SurveyQuestion.Kind.YES_NO:
				survey[q.id] = good
			_:
				survey[q.id] = 0 if good else q.choices.size() - 1
	s.data["survey"] = survey
	s.data["duration"] = 950.0
	return s


func _analyzer(list: Array[PlaytestSession]) -> PlaytestAnalyzer:
	var a := PlaytestAnalyzer.new(Playtest.config)
	a.sessions = list
	return a


func test_counts_deaths_pits_rooms_and_moments() -> void:
	var a := _analyzer([_fake(true, "baseline", ["NeonRoofs", "WardenTower"]), _fake(false, "strong_slide_jump", ["WardenTower"])])
	var r := a.analyze()
	check(int(r["deaths_total"]) == 3, "deaths_total %s" % r["deaths_total"])
	check(int(r["deaths_by_room"]["WardenTower"]) == 2, "deaths by room wrong")
	check(int(r["deaths_by_cause"]["needle: needle_stab"]) == 3, "death cause not grouped")
	check(int(r["pits_by_room"]["NeonRoofs"]) == 2, "pit falls not counted")
	check(int(r["room_reentries"]["NeonRoofs"]) == 2, "re-entries not counted")
	check(int(r["moment_tags"]["Confusing / lost"]) == 2, "moment tags not counted")
	check(int(r["completed"]) == 2 and int(r["dead_air_done"]) == 1, "completion counts wrong")
	check(float(r["weapon_hits"].get("pulse_blade", 0.0)) >= 10.0 or r["weapon_hits"].has("other"), "hits not grouped by weapon")
	check((r["variants"] as Dictionary).size() == 2, "variants not split")


func test_idle_spans_find_standing_still() -> void:
	var a := _analyzer([_fake(true, "baseline", [])])
	var spans: Array = a.analyze()["idle_spans"].get("NeonRoofs", [])
	check(spans.size() == 1 and float(spans[0]) >= 29.0, "expected one ~30 s idle span, got %s" % [spans])


func test_scorecard_needs_most_criteria() -> void:
	var good := _analyzer([_fake(true, "baseline", []), _fake(true, "baseline", []), _fake(false, "baseline", [])]).scorecard()
	check(good["pass"] and int(good["met"]) == 10, "2 of 3 happy testers (67%%) should meet all ten criteria: %d" % good["met"])
	var bad := _analyzer([_fake(true, "baseline", []), _fake(false, "baseline", []), _fake(false, "baseline", [])]).scorecard()
	check(not bad["pass"] and int(bad["met"]) == 0, "1 of 3 should meet none")


func test_markdown_and_heatmap_render() -> void:
	var a := _analyzer([_fake(true, "baseline", ["NeonRoofs"])])
	var md := a.render_markdown(a.analyze())
	for section in ["§44 scorecard", "Completion time and deaths", "Confusion signals", "Favourite mechanics", "Controls", "Performance", "Variants", "gap?"]:
		check(md.contains(section), "report missing '%s'" % section)
	var img := a.render_heatmap("res://world/rooms/lowlight/NeonRoofs.tscn")
	check(img != null and img.get_width() > 500, "heatmap not rendered")
	if img:
		var death_px := Vector2i(roundi((800 + 64) * 0.5), roundi((-60 - 12 + 500) * 0.5))
		check(img.get_pixelv(death_px).r > 0.9 and img.get_pixelv(death_px).g < 0.4, "death cross missing on heatmap")


func test_recorded_bot_run_goes_through_the_pipeline() -> void:
	Playtest.dir = TEST_DIR
	Playtest.allow_headless = true
	var root := Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	Game.new_game()
	Playtest.begin_session("new")
	SceneRouter.goto_room("res://world/rooms/lowlight/Relay.tscn", &"start")
	await physics_frames(5)
	var bot := RouteBot.new(get_tree(), (SceneRouter.current_room as Room).player)
	var ok: bool = await bot.run([["run", 980], ["exit", 1], ["run", 300]])
	check(ok, "bot route failed: %s" % bot.failure)
	Playtest.end_session("test")
	var summary: String = load("res://devtools/PlaytestReport.gd").build(TEST_DIR, TEST_DIR, "bot")
	check(summary.begins_with("1 sessions"), "report build failed: %s" % summary)
	var md := FileAccess.get_file_as_string(TEST_DIR + "/REPORT.md")
	check(md.contains("| Relay |"), "Relay dwell time missing from report")
	check(FileAccess.file_exists(TEST_DIR + "/heatmaps/FloodedAlley.png"), "heatmap file missing")
	SceneRouter.current_room = null
	SceneRouter.world_root = null
	root.queue_free()
	Game.new_game()


func test_map_opens_and_travel_are_reported() -> void:
	var s := PlaytestSession.new({"variant": "baseline"})
	s.add_event(5.0, "map_open", "MarketRun", Vector2.ZERO)
	s.add_event(6.0, "map_open", "MarketRun", Vector2.ZERO)
	s.add_event(9.0, "fast_travel", "Relay", Vector2.ZERO, {"from": "Relay.tscn|relay", "to": "BellTower.tscn|bell_top"})
	var a := PlaytestAnalyzer.new(Playtest.config)
	a.sessions = [s]
	var r := a.analyze()
	check(int(r["map_opens_by_room"]["MarketRun"]) == 2 and int(r["fast_travels"]) == 1, "map/travel not counted")
	check(a.render_markdown(r).contains("Map opened, by room"), "map section missing from report")


# --- M9 endgame lines (T14) -----------------------------------------------------------

func _m9_session(kind: String, events: Array) -> PlaytestSession:
	var s := PlaytestSession.new({"variant": "baseline", "build_kind": kind})
	for e: Array in events:
		s.add_event(float(e[0]), String(e[1]), "Relay", Vector2.ZERO, e[2] if e.size() > 2 else {})
	return s


func test_endgame_lines_from_fixture_sessions() -> void:
	var gold := ChallengeLibrary.by_id("tt_neon_roofs").medal_thresholds[2]
	var a := _analyzer([
		_m9_session("full", [[1.0, "achievement", {"id": "first_blade", "retro": false}],
			[2.0, "achievement", {"id": "reach_relay", "retro": false}],
			[3.0, "challenge_start", {"id": "tt_neon_roofs", "attempt": 1}],
			[4.0, "challenge_reset", {"id": "tt_neon_roofs", "reason": "reset"}],
			[5.0, "challenge_end", {"id": "tt_neon_roofs", "outcome": ChallengeData.Outcome.FINISHED, "value": gold - 60, "medal": 3, "new_best": true}],
			[6.0, "challenge_start", {"id": "null_static_lane", "attempt": 1}],
			[7.0, "challenge_reset", {"id": "null_static_lane", "reason": "death"}],
			[8.0, "challenge_end", {"id": "null_static_lane", "outcome": ChallengeData.Outcome.FINISHED, "value": 700, "medal": 2, "new_best": true}],
			[9.0, "ng_plus", {"cycle": 1, "remix": true}],
			[10.0, "rebind", {"action": "jump"}],
			[11.0, "assist_suggested", {"context": "WardenTower", "cause": "boss", "deaths": 4}],
			[12.0, "assist_answered", {"context": "WardenTower", "answer": "applied", "key": "damage_assist"}],
			[13.0, "locale", {"locale": "en_XA"}]]),
		_m9_session("demo", [[1.0, "achievement", {"id": "first_blade", "retro": false}],
			[300.0, "demo_end", {"from": "EscapeTunnel.tscn", "to": "Relay.tscn"}],
			[301.0, "assist_suggested", {"context": "CollectorBay", "cause": "boss", "deaths": 4}],
			[302.0, "assist_answered", {"context": "CollectorBay", "answer": "never", "key": ""}]]),
		_m9_session("demo", [[1.0, "ng_plus", {"cycle": 1, "remix": false}]]),
	])
	var r := a.analyze()
	var g: Dictionary = r["endgame"]
	check(g["achievements"] == [2, 1, 0] and int(g["achievement_ids"]["first_blade"]) == 2, "achievements per session %s" % [g["achievements"]])
	var ch: Dictionary = g["challenges"]["tt_neon_roofs"]
	check(int(ch["attempts"]) == 1 and int(ch["resets"]["reset"]) == 1 and int(ch["medals"][RankLadder.name(3)]) == 1, "challenge row %s" % ch)
	check(int(g["ng_cycles"]) == 2 and int(g["ng_remix"]) == 1, "NG+ cycles with the remix share")
	check(int(g["null_runs"]) == 1 and int(g["null_restarts"]["null_static_lane"]) == 1 and int(g["null_ranks"][RankLadder.name(2)]) == 1, "Deep Rig lines %s" % [g])
	check(int(g["rebind_players"]) == 1 and int(g["rebind_actions"]["jump"]) == 1, "rebinds")
	check(g["assist"] == {"shown": 2, "applied": 1, "opened_settings": 0, "declined": 1}, "assist answers %s" % g["assist"])
	check(int(g["demo_sessions"]) == 2 and int(g["demo_ends"]) == 1 and is_equal_approx(float(g["demo_end_minutes"][0]), 5.0), "demo end card N of M, minutes")
	check(int(g["locale_switches"]) == 1, "locale switches")
	var md := a.render_markdown(r)
	for line in ["## Endgame (M9)", "Achievements earned per session", "NG+ cycles started: 2 (remix on: 50%)", "Deep Rig: 1 runs",
			"Rebinds: 1 of 3 players", "Assist suggestions: shown 2 · applied 1", "Demo end card reached: 1 of 2 demo sessions",
			"Language switches: 1", "| tt_neon_roofs | 1 | reset 1 |", "Gold target"]:
		check(md.contains(line), "report has '%s'" % line)
	check(md.contains(PlaytestAnalyzer.gold_target("tt_neon_roofs")) and PlaytestAnalyzer.gold_target("tt_neon_roofs").ends_with(" s"), "the Gold target in seconds")
