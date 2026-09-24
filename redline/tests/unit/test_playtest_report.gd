extends RedlineTestCase
## M4 analysis: known sessions in, known numbers out; plus one real recorded
## RouteBot run through the pipeline (record -> file -> report -> heatmap).

const TEST_DIR := "user://test_playtest_report"


func after_each() -> void:
	Playtest.end_session("test_done")
	Playtest.allow_headless = false
	Playtest.dir = Playtest.DIR
	for sub in [TEST_DIR + "/heatmaps", TEST_DIR]:
		if DirAccess.dir_exists_absolute(sub):
			for f in DirAccess.get_files_at(sub):
				DirAccess.remove_absolute("%s/%s" % [sub, f])
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
