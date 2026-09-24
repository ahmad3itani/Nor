extends RedlineTestCase
## M4 playtest instrumentation: session recording, death causes, variants,
## survey data, and the recorder staying silent when it should.

const ROOM_A := "res://tests/fixtures/WorldA.tscn"
const TEST_DIR := "user://test_playtests"

var root: Node2D
var _saved_recording: bool
var _saved_variant: String


func before_each() -> void:
	_saved_recording = Settings.playtest_recording
	_saved_variant = Settings.playtest_variant
	Settings.playtest_recording = true
	Settings.playtest_variant = ""
	Playtest.dir = TEST_DIR
	Playtest.allow_headless = true
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	Game.new_game()


func after_each() -> void:
	Playtest.end_session("test_done")
	Playtest.allow_headless = false
	Playtest.dir = Playtest.DIR
	Settings.playtest_recording = _saved_recording
	Settings.playtest_variant = _saved_variant
	SceneRouter.current_room = null
	SceneRouter.world_root = null
	root.queue_free()
	if DirAccess.dir_exists_absolute(TEST_DIR):
		for f in DirAccess.get_files_at(TEST_DIR):
			DirAccess.remove_absolute("%s/%s" % [TEST_DIR, f])
	Game.new_game()
	await physics_frames(2)


func _start(variant_id: String = "baseline") -> Player:
	Settings.playtest_variant = variant_id
	Playtest.begin_session("new")
	SceneRouter.goto_room(ROOM_A, &"start")
	await physics_frames(45)
	return (SceneRouter.current_room as Room).player


func _types(s: PlaytestSession) -> Array:
	return (s.data["events"] as Array).map(func(e: Dictionary) -> String: return e["type"])


func test_config_and_variants_validate() -> void:
	var errors := Playtest.config.validate()
	check(errors.is_empty(), "playtest config invalid: %s" % ", ".join(errors))
	check(Playtest.config.variant("baseline") != null, "baseline arm missing")
	var scored := Playtest.config.survey.filter(func(q: SurveyQuestion) -> bool: return q.criterion != "")
	check(scored.size() == 10, "all ten §44 criteria should have a survey question, got %d" % scored.size())


func test_session_records_rooms_damage_death_and_frames() -> void:
	var p := await _start()
	check(Playtest.is_recording(), "session should be recording")
	p.combat.take_damage(1, Vector2.ZERO, 0.0, false, "needle/needle_stab")
	await physics_frames(2)
	p.combat.take_damage(99, Vector2.ZERO, 0.0, false, "hazard")
	await physics_frames(2)
	var path := Playtest.session_path
	Playtest.end_session("test")
	var s := PlaytestSession.load_file(path)
	check(s != null, "session file should load back")
	if s == null:
		return
	var types := _types(s)
	for t in ["session_start", "room_enter", "damage", "death", "session_end"]:
		check(types.has(t), "missing %s event (got %s)" % [t, str(types)])
	var deaths := s.events_of("death")
	check(not deaths.is_empty() and deaths[0]["cause"] == "hazard", "death cause should be the last damage source")
	check(s.events_of("damage")[0]["cause"] == "needle/needle_stab", "damage cause lost")
	check(s.events_of("room_enter")[0]["room"] == "WorldA", "room id should be the scene name")
	var frames := 0
	for n in s.data["perf"]["histogram"]:
		frames += int(n)
	check(frames > 10, "frame-time histogram should fill (%d)" % frames)
	check(not (s.data["samples"] as Dictionary).is_empty(), "position samples missing")
	check(not FileAccess.file_exists(path + ".tmp"), "atomic save left a temp file")


func test_enemy_hits_carry_enemy_and_attack_ids() -> void:
	var hit := HitInfo.new()
	var e := Enemy.new()
	e.data = load("res://data/enemies/needle.tres")
	hit.attacker = e
	hit.attack = e.data.attacks[0]
	check(PlayerCombat._source_of(hit) == "needle/%s" % e.data.attacks[0].id, "cause format: %s" % PlayerCombat._source_of(hit))
	e.free()
	check(PlayerCombat._source_of(hit).begins_with("unknown/"), "a freed attacker must not crash or leak")


func test_recording_off_means_no_session_and_no_file() -> void:
	Settings.playtest_recording = false
	await _start()
	check(not Playtest.is_recording(), "recording should be off")
	var files := DirAccess.get_files_at(TEST_DIR) if DirAccess.dir_exists_absolute(TEST_DIR) else PackedStringArray()
	var sessions := Array(files).filter(func(f: String) -> bool: return f.begins_with("session_"))
	check(sessions.is_empty(), "no session file may be written when recording is off")


func test_variant_overrides_a_copy_only() -> void:
	var shipped: PlayerMovementConfig = load("res://data/movement/default_movement.tres")
	var before := shipped.slide_jump_bonus
	var p := await _start("strong_slide_jump")
	check(Playtest.variant != null and Playtest.variant.id == "strong_slide_jump", "forced variant not picked")
	check_near(p.config.slide_jump_bonus, 60.0, 0.01, "variant override not applied")
	check_near(shipped.slide_jump_bonus, before, 0.01, "variant must never modify the shipped preset")
	var s := PlaytestSession.load_file(Playtest.session_path)
	check(s != null and s.data["meta"]["variant"] == "strong_slide_jump", "variant not recorded in meta")


func test_auto_variant_rotates_between_sessions() -> void:
	var seen := {}
	for i in 4:
		Playtest.begin_session("new")
		seen[Playtest.variant.id] = true
		Playtest.end_session("test")
	check(seen.size() == Playtest.config.variants.size(), "auto mode should rotate through every arm: %s" % [seen.keys()])


func test_moment_and_survey_are_saved() -> void:
	await _start()
	Playtest.report_moment("Confusing / lost", "where now?")
	Playtest.submit_survey({"boss_fair": 4, "noticed_secrets": true})
	var s := PlaytestSession.load_file(Playtest.session_path)
	var m := s.events_of("moment")
	check(m.size() == 1 and m[0]["tag"] == "Confusing / lost" and m[0]["note"] == "where now?", "moment not recorded")
	check(int(s.data["survey"]["boss_fair"]) == 4, "survey answers not saved")


func test_survey_pass_rules() -> void:
	var scale := SurveyQuestion.new()
	scale.kind = SurveyQuestion.Kind.SCALE
	check(scale.passes(4) and not scale.passes(3), "scale passes at 4+")
	var choice := SurveyQuestion.new()
	choice.kind = SurveyQuestion.Kind.CHOICE
	choice.choices = PackedStringArray(["Needle", "Krail", "None"])
	check(choice.passes(1) and not choice.passes(2) and not choice.passes(-1), "last choice means 'none'")


func test_survey_menu_walks_every_question_and_saves() -> void:
	await _start()
	var menu: MenuScreen = load("res://ui/menus/SurveyMenu.gd").new()
	add_child(menu)
	menu.open_menu()
	var qs: Array[SurveyQuestion] = menu.questions()
	for i in qs.size():
		match qs[i].kind:
			SurveyQuestion.Kind.SCALE:
				menu.answer(4)
			SurveyQuestion.Kind.YES_NO:
				menu.answer(true)
			_:
				menu.answer(null if i % 2 == 0 else 0)  # skip some
	var saved: Dictionary = Playtest.session.data["survey"]
	check(saved.size() >= qs.size() - 2, "survey answers not all saved (%d)" % saved.size())
	check(int(saved.get("boss_fair", 0)) == 4, "scale answer lost")
	menu.close_menu()
	menu.queue_free()


func test_moment_menu_saves_tag_with_note() -> void:
	await _start()
	var menu: MenuScreen = load("res://ui/menus/MomentMenu.gd").new()
	add_child(menu)
	menu.open_menu()
	menu._pick("Bug")
	menu._note.text = "  fell through floor  "
	menu._save()
	check(not menu.is_open() and not get_tree().paused, "moment menu should close and unpause")
	var m: Array = Playtest.session.events_of("moment")
	check(m.size() == 1 and m[0]["tag"] == "Bug" and m[0]["note"] == "fell through floor", "moment not saved: %s" % [m])
	menu.queue_free()


## The D-036 experiment's hypothesis, measured in the real room: with the
## stronger slide-jump a sloppy slide (starting 40 px early) still clears the
## Neon Roofs gap while a plain run-jump from the lip still does not, so the
## gap becomes a real slide-jump gate. Baseline needs a precise slide.
func _gap_attempt(variant_id: String, steps: Array) -> bool:
	SceneRouter.goto_room("res://world/rooms/lowlight/NeonRoofs.tscn", &"from_stack")
	await physics_frames(3)
	var room := SceneRouter.current_room as Room
	for e in room.find_children("*", "Enemy", true, false):
		(e as Enemy).ai_enabled = false
		(e as Enemy).set_ai(Enemy.AI.IDLE)
	Playtest.config.variant(variant_id).apply_to_player(room.player)
	var bot := RouteBot.new(get_tree(), room.player)
	await physics_frames(5)
	await bot.run([["run", 370], ["runjump", 396, 520]] + steps)
	return bot.player.global_position.y < -90.0 and bot.player.global_position.x > 872.0


func test_strong_slide_jump_variant_turns_the_gap_into_a_gate() -> void:
	var sloppy := [["slidejump", 762, 900, 40.0]]
	var run_jump := [["runjump", 764, 900]]
	check(not await _gap_attempt("baseline", sloppy), "baseline: a slide started 40 px early should fall short")
	check(await _gap_attempt("strong_slide_jump", sloppy), "strong variant: a sloppy slide-jump should clear")
	check(not await _gap_attempt("strong_slide_jump", run_jump), "strong variant: a plain run-jump must still fall short")
	check(await _gap_attempt("baseline", [["slidejump", 762, 900]]), "baseline: a precise slide-jump clears")
