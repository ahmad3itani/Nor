extends RedlineTestCase
## M8 telemetry (T10): Playtest records sequences, memory vignettes, arcs,
## the Act I choice and endings; scene time is cinematic_s, never pause time
## counted twice; PlaytestAnalyzer's Sequences table warns on first-view skips.
## Recording is local only and opt-in for headless runs (allow_headless + a
## temp dir), like test_playtest.gd.

const ROOM_A := "res://tests/fixtures/WorldA.tscn"
const TEST_DIR := "user://test_story_telemetry"
const LINES := "res://data/sequences/test_seq_lines.tres"

var root: Node2D
var room: Room
var _mp: MemoryScenePlayer
var _snap: Dictionary
var _saved_recording: bool
var _saved_variant: String


func before_each() -> void:
	_snap = use_default_m8_settings()
	_saved_recording = Settings.playtest_recording
	_saved_variant = Settings.playtest_variant
	Settings.playtest_recording = true
	Settings.playtest_variant = "baseline"
	Playtest.dir = TEST_DIR
	Playtest.allow_headless = true
	get_tree().paused = false
	CinematicMode.teardown()
	Cinematics.overlay.clear_all()
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	Game.new_game()
	Playtest.begin_session("new")
	SceneRouter.goto_room(ROOM_A, &"start")
	await physics_frames(5)
	room = SceneRouter.current_room as Room


func after_each() -> void:
	CinematicMode.teardown()
	if is_instance_valid(_mp):
		_mp.queue_free()
	_mp = null
	await get_tree().process_frame
	get_tree().paused = false
	Playtest.end_session("test_done")
	Playtest.allow_headless = false
	Playtest.dir = Playtest.DIR
	Settings.playtest_recording = _saved_recording
	Settings.playtest_variant = _saved_variant
	restore_m8_settings(_snap)
	SceneRouter.current_room = null
	SceneRouter.world_root = null
	root.queue_free()
	if DirAccess.dir_exists_absolute(TEST_DIR):
		for f in DirAccess.get_files_at(TEST_DIR):
			DirAccess.remove_absolute("%s/%s" % [TEST_DIR, f])
	Game.new_game()
	await physics_frames(2)


func _events(type: String) -> Array:
	return Playtest.session.events_of(type) if Playtest.session else []


func _counter(key: String) -> float:
	return float((Playtest.session.data["counters"] as Dictionary).get(key, 0.0)) if Playtest.session else 0.0


func _samples() -> int:
	return ((Playtest.session.data["samples"] as Dictionary).get(Playtest._room, []) as Array).size()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Starts a locking fixture sequence in AUTO (real time) without awaiting it.
func _start_lines(speed: float = 1.0) -> void:
	CinematicMode.set_mode(CinematicMode.Mode.AUTO)
	CinematicMode.auto_speed = speed
	Cinematics.play(load(LINES) as SequenceData, SequenceContext.for_room(room))


func _until_idle(max_frames: int = 1200) -> void:
	for i in max_frames:
		if not Cinematics.is_playing():
			return
		await get_tree().process_frame


func test_playtest_records_sequences() -> void:
	check(Playtest.is_recording(), "the test session records")
	await _frames(40)
	var before := _samples()
	check(before > 0, "samples recorded while free: %d" % before)
	var cine := _counter("cinematic_s")
	_start_lines(1.0)
	await _frames(2)
	check(Cinematics.locks_input(), "the fixture locks input")
	var during := _samples()
	await _frames(90)
	check(Cinematics.locks_input(), "still locked after 90 frames")
	check(_samples() == during, "no position samples while locked (%d -> %d)" % [during, _samples()])
	check(_counter("cinematic_s") - cine >= 1.4, "cinematic_s counted while locked: %.2f" % (_counter("cinematic_s") - cine))
	await _until_idle()
	var starts := _events("seq_start")
	var ends := _events("seq_end")
	check(starts.size() == 1 and starts[0]["id"] == "test_seq_lines" and starts[0]["first"] == true, "seq_start {id, first}: %s" % [starts])
	check(ends.size() == 1, "one seq_end: %s" % [ends])
	if ends.size() == 1:
		var e: Dictionary = ends[0]
		check(e["id"] == "test_seq_lines" and e["skipped"] == false and int(e["of"]) == 3 and int(e["step"]) >= 0,
			"seq_end {id, skipped, step, of}: %s" % e)
		check(float(e["seconds"]) > 1.0 and float(e["nominal"]) > 0.0, "seq_end seconds/nominal: %s" % e)
		check(e["first"] == true and e["locked"] == true, "seq_end copies first/locked: %s" % e)
	# Theatre replays (dev) are not recorded.
	CinematicMode.theatre = true
	_start_lines(8.0)
	await _until_idle()
	CinematicMode.theatre = false
	check(_events("seq_start").size() == 1 and _events("seq_end").size() == 1, "nothing recorded while theatre")


func test_playtest_records_memories_arcs_choices_endings() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.INSTANT)
	_mp = MemoryScenePlayer.new()
	add_child(_mp)
	EventBus.memory_playback_requested.emit(PackedStringArray(["mem_first_rest"]), &"anchor")
	var ms := _events("memory_start")
	var me := _events("memory_end")
	check(ms.size() == 1 and ms[0]["id"] == "mem_first_rest" and ms[0]["source"] == "anchor", "memory_start: %s" % [ms])
	check(me.size() == 1 and me[0]["first"] == true and me[0]["skipped"] == false and int(me[0]["beats"]) >= 3
		and me[0].has("detail") and me[0].has("seconds"), "memory_end: %s" % [me])
	EventBus.arc_stage_entered.emit("mara", "met", true)
	check(_events("arc").is_empty(), "on_load arc entries are not events")
	EventBus.arc_stage_entered.emit("mara", "krail", false)
	var arcs := _events("arc")
	check(arcs.size() == 1 and arcs[0]["npc"] == "mara" and arcs[0]["stage"] == "krail", "arc event: %s" % [arcs])
	EventBus.dialogue_choice_made.emit("orr_on_air", "named")
	var ch := _events("choice")
	check(ch.size() == 1 and ch[0]["dialogue"] == "orr_on_air" and ch[0]["choice"] == "named", "choice event: %s" % [ch])
	EventBus.ending_started.emit("sever", true)
	EventBus.ending_finished.emit("sever", true, true)
	var en := _events("ending")
	check(en.size() == 1 and en[0]["id"] == "sever" and en[0]["theatre"] == true and en[0]["skipped"] == true, "ending event: %s" % [en])
	check(_events("ending_start").size() == 1, "ending_start event")
	Game.set_flag("arc_mara_stage", 2)
	Game.set_flag("arcbeat_mara_krail", true)
	Game.set_flag("orr_air_named", true)
	EventBus.slice_completed.emit()
	var sc := _events("slice_complete")
	check(sc.size() == 1, "slice_complete recorded")
	if sc.size() == 1:
		var e: Dictionary = sc[0]
		check(int(e["memories"]) == MemoryLibrary.remembered_count() and int(e["memories"]) >= 1, "memories: %s" % e)
		check(e.has("memory_details") and e.has("memories_pending"), "memory detail/pending counts: %s" % e)
		check(int(e["arc_beats_heard"]) >= 1, "arc_beats_heard: %s" % e)
		check(e["arcs"] is Dictionary and int((e["arcs"] as Dictionary).get("mara", -1)) == 2 and (e["arcs"] as Dictionary).size() == 5,
			"arcs {npc: stage}: %s" % [e["arcs"]])
		check(e["orr_air"] == "named", "orr_air: %s" % e)
		check(e.has("act1_complete"), "act1_complete field")
		var standing: Array = e["standing"]
		check(not standing.is_empty() and Array(ActLibrary.standing_lines(ActLibrary.act(1))) == standing, "standing lines shown: %s" % [standing])


func test_memory_counts_cinematic_not_pause() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.PLAY)
	_mp = MemoryScenePlayer.new()
	add_child(_mp)
	var pauses := _events("pause").size()
	EventBus.memory_playback_requested.emit(PackedStringArray(["mem_first_rest"]), &"anchor")
	await _frames(3)
	check(get_tree().paused and _mp.is_playing(), "the vignette pauses the tree")
	var cine := _counter("cinematic_s")
	var paused := _counter("paused_s")
	await _frames(60)
	check_near(_counter("cinematic_s") - cine, 1.0, 0.1, "a playing memory is cinematic_s")
	check(is_equal_approx(_counter("paused_s"), paused), "a memory adds no paused_s (%.2f)" % (_counter("paused_s") - paused))
	check(_events("pause").size() == pauses, "a memory writes no 'pause' event")
	MemoryScenePlayer.abort_active()
	await _frames(3)
	check(not get_tree().paused, "abort unpauses")
	# A PauseMenu pause (the tree paused with no scene) is still a pause.
	get_tree().paused = true
	await _frames(30)
	check(_events("pause").size() == pauses + 1, "a PauseMenu pause still writes one 'pause' event")
	check(_counter("paused_s") - paused >= 0.4, "and counts paused_s")
	get_tree().paused = false


func test_paused_sequence_not_double_counted() -> void:
	_start_lines(0.25)
	await _frames(5)
	check(Cinematics.locks_input(), "the fixture locks input")
	var cine := _counter("cinematic_s")
	var paused := _counter("paused_s")
	get_tree().paused = true
	await _frames(60)
	check_near(_counter("paused_s") - paused, 1.0, 0.1, "a paused sequence counts paused_s")
	check(is_equal_approx(_counter("cinematic_s"), cine), "and no cinematic_s (%.2f)" % (_counter("cinematic_s") - cine))
	get_tree().paused = false
	var cine2 := _counter("cinematic_s")
	var paused2 := _counter("paused_s")
	await _frames(30)
	check(Cinematics.locks_input(), "still playing")
	check_near(_counter("cinematic_s") - cine2, 0.5, 0.1, "unpaused, it counts cinematic_s")
	check(is_equal_approx(_counter("paused_s"), paused2), "and no paused_s")
	Cinematics.abort()


## A synthetic session: `views` first views of one sequence, `skips` of them skipped.
func _seq_session(id: String, skipped: bool) -> PlaytestSession:
	var s := PlaytestSession.new({"variant": "baseline", "kind": "new"})
	s.add_event(0.0, "session_start", "", Vector2.ZERO)
	s.add_event(1.0, "room_enter", "Wake", Vector2.ZERO)
	s.add_event(2.0, "seq_start", "Wake", Vector2.ZERO, {"id": id, "first": true})
	s.add_event(4.0 if skipped else 16.0, "seq_end", "Wake", Vector2.ZERO, {"id": id, "skipped": skipped,
		"seconds": 2.0 if skipped else 14.0, "step": 3 if skipped else 12, "of": 13, "nominal": 14.0, "first": true, "locked": true})
	s.add_event(60.0, "weapon_granted", "Wake", Vector2.ZERO, {"id": "pulse_blade", "pt": 60.0})
	s.add_event(70.0, "ending", "", Vector2.ZERO, {"id": "crown", "theatre": true, "skipped": false})
	s.add_event(80.0, "slice_complete", "WardenTower", Vector2.ZERO, {"play_time": 80.0, "secrets": 1, "dead_air": false,
		"memories": 2, "memory_details": 0, "memories_pending": 1, "arc_beats_heard": 3, "arcs": {"mara": 2},
		"orr_air": "ghost", "act1_complete": true, "standing": ["Line A", "Line B"]})
	return s


func test_analyzer_sequence_skip_warning() -> void:
	var a := PlaytestAnalyzer.new(Playtest.config)
	var list: Array[PlaytestSession] = [_seq_session("uc_opening", true), _seq_session("uc_opening", true),
		_seq_session("uc_opening", true), _seq_session("uc_opening", false)]
	a.sessions = list
	var r := a.analyze()
	var row: Dictionary = r["sequences"].get("uc_opening", {})
	check(int(row.get("views", 0)) == 4 and int(row.get("first_views", 0)) == 4 and int(row.get("first_skips", 0)) == 3,
		"sequence row: %s" % row)
	var md := a.render_markdown(r)
	check(md.contains("### Sequences") and md.contains("| uc_opening | 4 | 4 | 75% | 14.0 / 14.0 |"), "Sequences table row")
	check(md.contains("uc_opening first-view skip rate 75% > 50%"), "the '> 50%' warning line")
	check(md.contains("minus cinematic_s"), "timeline has the minus cinematic_s column")
	check(md.contains("Act I standing") and md.contains("| Line A | 4 |"), "Act I standing table")
	check(not md.contains("| crown"), "theatre endings ignored")
	check(md.contains("Orr on-air split: ghost 4"), "Orr on-air split")
	# The unskipped session's blade beat: minute 1.0, minus 14 s of scene.
	var tl: Array = r["timeline"]["campaign"]
	check(tl.size() == 4 and is_equal_approx(float((tl[3] as Dictionary)["blade" + PlaytestAnalyzer.CINE_SUFFIX]), (60.0 - 14.0) / 60.0),
		"timeline minus cinematic_s: %s" % [tl])
	# Half skipped is not over the line.
	var b := PlaytestAnalyzer.new(Playtest.config)
	var half: Array[PlaytestSession] = [_seq_session("relay_arrival", true), _seq_session("relay_arrival", false)]
	b.sessions = half
	check(PlaytestAnalyzer.sequence_warnings(b.analyze()).is_empty(), "50% first-view skips does not warn")
