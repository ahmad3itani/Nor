extends RedlineTestCase
## M8 scripted sequence runtime (T03): Cinematics, SequencePlayer, the steps,
## the overlay, the input lock and its restore contract, pause and skip.
## Fixtures: data/sequences/test_*.tres (theatre_only), played in
## tests/fixtures/WorldA.tscn (a world room with no enemies).

const ROOM := "res://tests/fixtures/WorldA.tscn"
const CLAMP_ROOM := "res://tests/fixtures/grid_clamp.tscn"
const SAVE_DIR := "user://test_sequences"
const PARITY := "res://data/sequences/test_seq_parity.tres"
const LINES := "res://data/sequences/test_seq_lines.tres"
const VIEW := "res://data/sequences/test_seq_view.tres"
const BARK := "res://data/sequences/test_seq_repeat_bark.tres"
const NEEDLE := "res://data/enemies/needle.tres"


## A step that only records its finish() calls (abort must run none).
class ProbeStep:
	extends SequenceStep
	var finishes: Array = []

	func run(_p: SequencePlayer) -> void:
		pass

	func finish(_p: SequencePlayer) -> void:
		finishes.append(1)


var root: Node2D
var room: Room
var _snap: Dictionary
## [id, skipped, seconds, step_index, step_count, nominal, frame]
var finished: Array = []
## [index, label, process frame]
var steps_seen: Array = []
var marks: Array = []
var perfects: Array = []


func before_each() -> void:
	_snap = use_default_m8_settings()
	SaveManager.save_dir = SAVE_DIR
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	Game.new_game()
	finished.clear()
	steps_seen.clear()
	marks.clear()
	perfects.clear()
	EventBus.sequence_finished.connect(_on_finished)
	EventBus.perfect_dodge.connect(_on_perfect)
	Cinematics.step_started.connect(_on_step)
	Cinematics.marked.connect(_on_mark)
	# A previous play's letterbox may still be sliding out.
	Cinematics.overlay.clear_all()
	room = await _enter(ROOM, &"start")


func after_each() -> void:
	EventBus.sequence_finished.disconnect(_on_finished)
	EventBus.perfect_dodge.disconnect(_on_perfect)
	Cinematics.step_started.disconnect(_on_step)
	Cinematics.marked.disconnect(_on_mark)
	get_tree().paused = false
	CinematicMode.teardown()
	restore_m8_settings(_snap)
	if DirAccess.dir_exists_absolute(SAVE_DIR):
		for f in DirAccess.get_files_at(SAVE_DIR):
			DirAccess.remove_absolute("%s/%s" % [SAVE_DIR, f])
	SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR
	SceneRouter.current_room = null
	SceneRouter.world_root = null
	root.queue_free()
	Game.new_game()
	await physics_frames(2)


func _on_finished(id: String, skipped: bool, seconds: float, step_index: int, step_count: int, nominal: float) -> void:
	finished.append([id, skipped, seconds, step_index, step_count, nominal, Engine.get_process_frames()])


func _on_step(index: int, label: String) -> void:
	steps_seen.append([index, label, Engine.get_process_frames()])


func _on_mark(mark: String) -> void:
	marks.append(mark)


func _on_perfect(_attacker: Node) -> void:
	perfects.append(1)


func _enter(path: String, entry: StringName) -> Room:
	SceneRouter.goto_room(path, entry)
	await physics_frames(3)
	return SceneRouter.current_room as Room


func _seq(path: String) -> SequenceData:
	return load(path) as SequenceData


func _auto(speed: float = 4.0) -> void:
	CinematicMode.set_mode(CinematicMode.Mode.AUTO)
	CinematicMode.auto_speed = speed


func _play() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.PLAY)


## Starts a play without waiting; the result lands in `into`.
func _start(seq: SequenceData, into: Array = [], ctx: SequenceContext = null) -> void:
	into.append(await Cinematics.play(seq, ctx if ctx else SequenceContext.for_room(room)))


func _until_finished(max_frames: int = 1200) -> void:
	var n := finished.size()
	for i in max_frames:
		if finished.size() > n:
			return
		await get_tree().process_frame


func _started(index: int) -> bool:
	return steps_seen.any(func(s: Array) -> bool: return s[0] == index)


func _start_frame(index: int) -> int:
	for s in steps_seen:
		if s[0] == index:
			return s[2]
	return -1


func _check_restored(where: String) -> void:
	var p := room.player
	check(p.input_override == null, "%s: input_override cleared" % where)
	check(not p.cinematic_lock, "%s: cinematic_lock cleared" % where)
	check(not room.camera.is_directed(), "%s: camera released" % where)
	check(MusicDirector._override == -1, "%s: music override cleared (%d)" % [where, MusicDirector._override])
	check(Cinematics.overlay.is_idle(), "%s: overlay cleared" % where)
	check(not CinematicMode.hud_hidden, "%s: HUD shown" % where)
	check(not CinematicMode.bark_line, "%s: bark_line cleared" % where)
	check(not Cinematics.is_playing() and Cinematics.current == null, "%s: nothing playing" % where)


func _button(menu: MenuScreen, text: String) -> Button:
	for c in menu._body.get_children():
		if c is Button and (c as Button).text == text:
			return c as Button
	return null


func _pause_menu() -> MenuScreen:
	var pm: MenuScreen = load("res://ui/menus/PauseMenu.gd").new()
	add_child(pm)
	return pm


# --- Tests --------------------------------------------------------------------------

func test_instant_mode_resolves_same_frame() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.INSTANT)
	var frame := Engine.get_process_frames()
	var pframe := Engine.get_physics_frames()
	var r := await Cinematics.play(_seq(PARITY), SequenceContext.for_room(room))
	check(Engine.get_process_frames() == frame and Engine.get_physics_frames() == pframe, "INSTANT play passed a frame")
	check(r != null and r.instant and not r.skipped and not r.refused and not r.aborted(), "INSTANT result")
	check(Game.has_flag("seen_seq_test_seq_parity"), "seen flag set")
	check(Game.has_flag("test_seq_parity_a") and Game.flag_int("test_seq_parity_b") == 2, "flags set by finish()")
	check(room.player.facing == -1, "facing set by finish()")
	check(marks.has("test_parity_end"), "SeqMark emitted in INSTANT")
	check(finished.size() == 1 and is_zero_approx(finished[0][2]), "sequence_finished with 0 s")
	_check_restored("instant")


func _parity_state() -> Dictionary:
	return {"flags": Game.state.flags.duplicate(true), "facing": room.player.facing, "music": MusicDirector._override}


func _parity_reset() -> void:
	Game.new_game()
	room.player.facing = 1
	MusicDirector.clear_override()


func test_skip_parity() -> void:
	var seq := _seq(PARITY)
	_parity_reset()
	_auto(4.0)
	_start(seq)
	await _until_finished()
	check(not finished[-1][1], "watched run not skipped")
	var watched := _parity_state()
	_parity_reset()
	CinematicMode.set_mode(CinematicMode.Mode.INSTANT)
	await Cinematics.play(seq, SequenceContext.for_room(room))
	var instant := _parity_state()
	_parity_reset()
	_auto(4.0)
	var res: Array = []
	_start(seq, res)
	# Skip while the SeqLine (step 4) shows: flag a already set by run(); b,
	# the music clear and the gated steps are still ahead.
	for i in 300:
		if Cinematics.is_playing() and Cinematics.current.index == 4:
			break
		await get_tree().process_frame
	check(Cinematics.is_playing() and Cinematics.current.index == 4 and Cinematics.overlay.line_on, "skip lands on the line")
	check(Game.has_flag("test_seq_parity_a") and Game.flag_int("test_seq_parity_b") == 0, "part-way: a set, b ahead")
	Cinematics.request_skip()
	await _until_finished(10)
	check(res.size() == 1 and res[0].skipped, "mid-way run skipped")
	check(finished.size() == 3 and finished[-1][1] and finished[-1][3] == 4,
		"skip reports the step it landed on (4): %s" % [finished[-1]])
	check(finished[0][3] == 9 and finished[1][3] == 9, "watched and INSTANT runs end on the last step")
	check(marks.size() == 3 and marks.count("test_parity_end") == 3, "one mark per run: %s" % [marks])
	var skipped := _parity_state()
	check(watched["flags"] == instant["flags"], "watched vs INSTANT flags: %s / %s" % [watched["flags"], instant["flags"]])
	check(watched["flags"] == skipped["flags"], "watched vs skipped flags: %s / %s" % [watched["flags"], skipped["flags"]])
	for s: Dictionary in [watched, instant, skipped]:
		check(s["facing"] == -1, "facing -1 in every path")
		check(s["music"] == -1, "music override cleared in every path")
	_check_restored("parity")


## Built in code: runtime rules the content checks leave to the player.
func _code_seq(id: String, steps: Array[SequenceStep], locking: bool) -> SequenceData:
	var seq := SequenceData.new()
	seq.id = id
	seq.steps = steps
	seq.lock_input = locking
	seq.letterbox = locking
	seq.hide_hud = locking
	seq.theatre_only = true
	return seq


func test_parallel_abort_and_tapless_rules() -> void:
	# A non-blocking step whose run() completed is not finish()ed again.
	var mark := SeqMark.new()
	mark.mark = "test_parallel"
	mark.blocking = false
	var probe := ProbeStep.new()
	probe.blocking = false
	var pause := SeqWait.new()
	pause.seconds = 0.2
	_auto(4.0)
	_start(_code_seq("test_code_parallel", [mark, probe, pause] as Array[SequenceStep], true))
	await _until_finished()
	check(marks == ["test_parallel"], "a non-blocking SeqMark emits once in AUTO: %s" % [marks])
	check(probe.finishes.is_empty(), "a completed parallel step is not finish()ed again")
	# hold_for_input in a non-locking play (no SkipGate, no tap) keeps its clock.
	var line := SeqLine.new()
	line.text = "Hold."
	line.seconds = 2.0
	line.hold_for_input = true
	_play()
	var res: Array = []
	_start(_code_seq("test_code_tapless", [line] as Array[SequenceStep], false), res)
	for i in 180:
		if not res.is_empty():
			break
		await get_tree().process_frame
	check(res.size() == 1 and not res[0].aborted(), "a tapless hold_for_input line ends on its clock")
	# An aborted bark leaves no actor tinted; its SeqLine clears nothing later.
	var flash := SeqActorFlash.new()
	flash.actor = "@rook"
	flash.color = Color(1, 0, 0)
	flash.seconds = 2.0
	flash.pulses = 1
	flash.blocking = false
	var bark_line := SeqLine.new()
	bark_line.text = "Bark."
	bark_line.seconds = 2.0
	var base := room.player.modulate
	_auto(1.0)
	var bark_res: Array = []
	_start(_code_seq("test_code_bark", [flash, bark_line] as Array[SequenceStep], false), bark_res)
	await physics_frames(20)
	check(room.player.modulate != base, "the bark tints Rook")
	var ended_in_listener: Array = []
	var chain := func(id: String, _s: bool, _t: float, _i: int, _n: int, _nom: float) -> void:
		if id == "test_code_bark":
			ended_in_listener.append(1)
	EventBus.sequence_finished.connect(chain)
	_start(_seq(PARITY))
	EventBus.sequence_finished.disconnect(chain)
	await physics_frames(2)
	check(bark_res.size() == 1 and bark_res[0].aborted() and ended_in_listener.size() == 1, "the locking play aborted the bark")
	check(room.player.modulate == base, "the aborted flash put modulate back")
	check(Cinematics.locks_input() and Cinematics.current.seq.id == "test_seq_parity", "the locking play is current")
	# A play a finished-listener starts inside Cinematics.abort() stays current.
	var restarted: Array = []
	var restart := func(id: String, _s: bool, _t: float, _i: int, _n: int, _nom: float) -> void:
		if id == "test_seq_parity" and restarted.is_empty():
			restarted.append(1)
			_start(_code_seq("test_code_after", [pause] as Array[SequenceStep], false))
	EventBus.sequence_finished.connect(restart)
	Cinematics.abort()
	EventBus.sequence_finished.disconnect(restart)
	check(restarted.size() == 1 and Cinematics.is_playing() and Cinematics.current.seq.id == "test_code_after",
		"a play started from the abort's listener stays current")
	await _until_finished()
	_check_restored("parallel/abort")


func test_input_locked_during_sequence() -> void:
	var walk := ScriptedInputSource.new()
	room.player.input_source = walk
	_auto(4.0)
	_start(_seq(PARITY))
	await physics_frames(1)
	walk.move_x = 1
	var x0 := room.player.global_position.x
	await physics_frames(20)
	check(Cinematics.locks_input(), "still locked")
	check_near(room.player.global_position.x, x0, 0.5, "Rook does not move while locked")
	await _until_finished()
	check(room.player.input_source == walk, "RouteBot-style input_source kept")
	await physics_frames(10)
	check(room.player.global_position.x > x0 + 5.0, "Rook moves once control returns")


func test_first_view_hold_and_repeat_short_hold() -> void:
	_play()
	var skip_press: Array[StringName] = [&"jump", &"cinematic_skip"]
	_start(_seq(PARITY))
	await physics_frames(20)
	await press_actions(skip_press, 30)
	await physics_frames(3)
	check(Cinematics.is_playing() and finished.is_empty(), "0.5 s hold does not skip a first view")
	await press_actions(skip_press, 51)
	await physics_frames(3)
	check(finished.size() == 1 and finished[0][1], "0.85 s hold skips a first view")
	# Seen now: a repeat view.
	_start(_seq(PARITY))
	await physics_frames(20)
	await press_actions(skip_press, 27)
	await physics_frames(3)
	check(finished.size() == 2 and finished[1][1], "0.45 s hold skips a repeat view")
	_start(_seq(PARITY))
	await physics_frames(20)
	await press_actions(skip_press, 6)
	await physics_frames(5)
	check(Cinematics.is_playing() and finished.size() == 2, "a 0.1 s tap never skips")


func test_pause_freezes_sequence() -> void:
	_auto(1.0)
	_start(_seq(PARITY))
	await physics_frames(10)
	var clock := Cinematics.current.clock()
	var cam := room.camera.global_position
	get_tree().paused = true
	await physics_frames(60)
	check(is_equal_approx(Cinematics.current.clock(), clock), "clock frozen under pause")
	check(room.camera.global_position.is_equal_approx(cam), "camera frozen under pause")
	var pm := _pause_menu()
	pm.open_menu()
	var skip := _button(pm, "Skip scene")
	check(skip != null, "PauseMenu lists 'Skip scene'")
	if skip:
		skip.pressed.emit()
	await _until_finished(10)
	check(finished.size() == 1 and finished[0][1], "Skip scene skips")
	pm.queue_free()


func test_room_leave_aborts() -> void:
	var probe := ProbeStep.new()
	var wait := SeqWait.new()
	wait.seconds = 1.0
	var flag := SeqFlag.new()
	flag.flags = PackedStringArray(["test_abort_flag"])
	var seq := SequenceData.new()
	seq.id = "test_abort"
	seq.steps = [wait, probe, flag]
	_auto(1.0)
	var res: Array = []
	_start(seq, res)
	await physics_frames(10)
	EventBus.room_leaving.emit(room)
	await physics_frames(1)
	check(res.size() == 1 and res[0].aborted() and not res[0].skipped, "play() resolves aborted, not skipped")
	check(finished.size() == 1 and finished[0][3] == -1 and not finished[0][1], "sequence_finished step_index -1")
	check(not Game.has_flag("test_abort_flag"), "a SeqFlag after the abort point stays unset")
	check(probe.finishes.is_empty(), "abort runs no finish()")
	check(not Game.has_flag("seen_seq_test_abort"), "seen flag stays unset")
	_check_restored("abort")


func test_music_override_step() -> void:
	_auto(4.0)
	_start(_seq(PARITY))
	await physics_frames(2)
	check(MusicDirector._override == MusicDirector.State.SILENT, "SeqMusic SILENT applied")
	await _until_finished()
	check(MusicDirector._override == -1, "override cleared at the end")


func test_narration_speaker_and_for_overlay() -> void:
	var line := SeqLine.new()
	line.speaker_id = ""
	line.text = "Static on every band at once."
	var seq := SequenceData.new()
	seq.id = "test_narration"
	seq.theatre_only = true
	seq.steps = [line]
	check(seq.content_check().is_empty(), "narration line validates: %s" % seq.content_check())
	_auto(4.0)
	var res: Array = []
	_start(seq, res, SequenceContext.for_overlay(null))
	await physics_frames(3)
	var ov := Cinematics.overlay
	check(ov.line_on and ov.line_narration and ov.line_speaker == "", "narration line shows without a label")
	await _until_finished()
	check(res.size() == 1 and not res[0].refused and not res[0].aborted(), "plays under for_overlay(null)")


func _lint(seq: SequenceData) -> PackedStringArray:
	var v := ContentValidator.new()
	v.check_resource(seq, "res://data/test/x.tres")
	return v.errors


func _one_error(seq: SequenceData, needle: String, what: String) -> void:
	var errors := _lint(seq)
	var hits := Array(errors).filter(func(e: String) -> bool: return e.contains(needle)).size()
	check(hits == 1, "%s: expected one '%s' error, got %d in %s" % [what, needle, hits, errors])


func _bad(steps: Array[SequenceStep]) -> SequenceData:
	var seq := SequenceData.new()
	seq.id = "x"
	seq.theatre_only = true
	seq.steps = steps
	return seq


func test_validator_sequence_rules() -> void:
	var speaker := SeqLine.new()
	speaker.speaker_id = "nobody_here"
	speaker.text = "Hello."
	_one_error(_bad([speaker]), "unknown speaker", "speaker")
	var long := SeqLine.new()
	long.speaker_id = "pa"
	long.text = "x".repeat(130)
	_one_error(_bad([long]), "130 chars", "long line")
	var zoom := SeqCamera.new()
	zoom.zoom = 2.0
	zoom.seconds = 0.5
	_one_error(_bad([zoom]), "outside 1.0..1.5", "zoom")
	var move := SeqActorMove.new()
	move.actor = "@rook"
	_one_error(_bad([move]), "may not move @rook", "move rook")
	var door := SeqActorFace.new()
	door.actor = "Interactables/NPC_mara_door"
	_one_error(_bad([door]), "names no data/npcs profile", "post node actor")
	var text_flag := SeqFlag.new()
	text_flag.flags = PackedStringArray(["test_x"])
	text_flag.value = "yes"
	_one_error(_bad([text_flag]), "must be bool or int", "string flag value")
	var early := SeqWait.new()
	early.only_when = "flag:test_later"
	var later := SeqFlag.new()
	later.flags = PackedStringArray(["test_later"])
	_one_error(_bad([early, later]), "set later by step 1", "only_when order")
	var cam := SeqCamera.new()
	cam.seconds = 0.5
	var repeat := _bad([cam])
	repeat.repeat_locks_input = false
	_one_error(repeat, "repeat views play without a lock", "repeat_locks_input false")
	# A room-bound NPC path resolves in its room.
	var face := SeqActorFace.new()
	face.actor = "Interactables/NPC_orr"
	var good := _bad([face])
	good.room = "res://world/rooms/lowlight/Relay.tscn"
	check(_lint(good).is_empty(), "NPC_orr in the Relay validates: %s" % _lint(good))
	var roomless := _bad([face])
	_one_error(roomless, "needs the sequence's room", "NPC path without a room")


func test_menu_gating() -> void:
	var host: GDScript = load("res://ui/menus/MenuHost.gd")
	check(host.can_open(&"map", false, false), "map opens in a world room when unlocked")
	check(host.can_open(&"pause", false, false), "pause opens when unlocked")
	check(not host.can_open(&"map", true, false) and not host.can_open(&"map", false, true), "never under a pause or a menu")
	_auto(1.0)
	_start(_seq(PARITY))
	await physics_frames(2)
	check(Cinematics.locks_input(), "locked")
	check(not host.can_open(&"map", false, false), "map shut while locked")
	check(not host.can_open(&"debug_console", false, false), "dev console shut while locked")
	check(host.can_open(&"pause", false, false), "pause still opens while locked")


func test_grid_clamp_and_core_frozen_while_locked() -> void:
	var core := room.player.reactor
	core.enter_flow()
	core.charge = 50.0
	_auto(1.0)
	_start(_seq(PARITY))
	await physics_frames(20)
	check(Cinematics.locks_input(), "locked")
	check(is_equal_approx(core.charge, 50.0), "Core does not drain while locked (%.2f)" % core.charge)
	Cinematics.abort()
	await physics_frames(20)
	check(core.charge < 50.0, "Core drains again after the lock (%.2f)" % core.charge)
	core.exit_flow()
	room = await _enter(CLAMP_ROOM, &"from_bell")
	var clamp := room.find_child("Clamp_wt_clamp", true, false) as GridClamp
	var krail := room.find_child("WardenKrail1", true, false) as Enemy
	krail.process_mode = Node.PROCESS_MODE_DISABLED
	clamp._on_boss_started(krail, "")
	await physics_frames(5)
	var armed := clamp._armed_time
	check(armed > 0.0, "clamp armed and counting")
	_start(_seq(PARITY))
	await physics_frames(1)
	var locked_at := clamp._armed_time
	await physics_frames(30)
	check(is_equal_approx(clamp._armed_time, locked_at), "armed time frozen while locked")
	Cinematics.abort()
	await physics_frames(5)
	check(clamp._armed_time > locked_at, "armed time runs again after the lock")


func test_context_first_view_wins() -> void:
	Game.set_flag("seen_seq_test_seq_view")
	_auto(1.0)
	var ctx := SequenceContext.for_room(room)
	ctx.first_view = 1
	_start(_seq(VIEW), [], ctx)
	await physics_frames(2)
	check(_started(0) and not _started(1), "context first_view=1 plays the First-view steps")
	await physics_frames(20)
	var skip_press: Array[StringName] = [&"jump", &"cinematic_skip"]
	await press_actions(skip_press, 27)
	await physics_frames(3)
	check(finished.is_empty(), "first view: a 0.45 s hold does not skip")
	await press_actions(skip_press, 51)
	await physics_frames(3)
	check(finished.size() == 1 and finished[0][1], "first view: a 0.85 s hold skips")
	steps_seen.clear()
	CinematicMode.set_mode(CinematicMode.Mode.INSTANT)
	await Cinematics.play(_seq(VIEW), SequenceContext.for_room(room))
	check(_started(1) and not _started(0), "first_view -1 falls back to the seen flag (repeat)")


func test_tap_advances_line_not_skip() -> void:
	Game.set_flag("seen_seq_test_seq_lines")
	_play()
	_start(_seq(LINES))
	await physics_frames(50)
	check(_started(0) and not _started(1), "line 1 showing")
	await press_action(&"jump", 3)
	await physics_frames(2)
	check(_started(1), "a tap advances to line 2")
	check(Cinematics.is_playing() and finished.is_empty(), "the tap did not skip")


func test_first_view_mash_keeps_lines() -> void:
	_play()
	var seq := _seq(LINES)
	_start(seq)
	for i in 160:
		if not finished.is_empty():
			break
		await press_action(&"jump", 3)
		await physics_frames(4)
	await _until_finished()
	check(finished.size() == 1 and not finished[0][1], "mashing never skips")
	for i in 3:
		var from := _start_frame(i)
		var to := _start_frame(i + 1) if i < 2 else int(finished[0][6])
		var auto := SeqLine.auto_seconds((seq.steps[i] as SeqLine).text)
		check(from >= 0 and (to - from) / 60.0 >= 0.5 * auto - 0.02,
			"line %d visible %.2f s, needs >= %.2f" % [i, (to - from) / 60.0, 0.5 * auto])


func test_resume_press_does_not_skip() -> void:
	Game.set_flag("seen_seq_test_seq_lines")
	_play()
	_start(_seq(LINES))
	await physics_frames(30)
	get_tree().paused = true
	await physics_frames(30)
	get_tree().paused = false
	var resume: Array[StringName] = [&"ui_accept", &"jump", &"cinematic_skip"]
	await press_actions(resume, 18)
	await physics_frames(3)
	check(finished.is_empty() and Cinematics.is_playing(), "the Resume press does not skip")
	check(not _started(1), "the Resume press does not advance the line")


func test_lock_leaves_invulnerable_alone() -> void:
	var input := ScriptedInputSource.new()
	var p := room.player
	p.input_source = input
	input.press_dodge()
	for i in 10:
		await physics_frames(1)
		if p.invulnerable:
			break
	check(p.current_state_id() == &"dodge" and p.invulnerable, "dodging with i-frames (%s)" % p.current_state_id())
	_auto(1.0)
	_start(_seq(PARITY))
	var attack: AttackData = (load(NEEDLE) as EnemyData).attacks[0]
	var hit := HitInfo.create(null, attack, Vector2(100, 0), Vector2.RIGHT)
	hit.source_position = p.global_position - Vector2(10, 0)
	check(p.receive_hit(hit) == CombatResult.IGNORED, "hits are ignored under the lock")
	check(perfects.is_empty(), "no perfect dodge under the lock")
	check(p.combat.health == p.combat.config.max_health, "no damage")
	Cinematics.request_skip()
	await physics_frames(40)
	check(not p.cinematic_lock, "lock released")
	check(not p.invulnerable, "invulnerable false once the dodge ended")


func test_subtitle_speed_scales_line() -> void:
	var seq := _seq(LINES)
	var nominal := seq.nominal_seconds(true)
	var spans: Array = []
	for speed in [0, 2]:
		Settings.subtitle_speed = speed
		steps_seen.clear()
		_auto(4.0)
		_start(seq)
		await _until_finished()
		spans.append(_start_frame(1) - _start_frame(0))
	check(spans[0] > 0 and absf(float(spans[1]) / float(spans[0]) - 2.0) < 0.1,
		"x2 subtitle speed doubles the hold (%d -> %d frames)" % [spans[0], spans[1]])
	check(is_equal_approx(seq.nominal_seconds(true), nominal), "nominal_seconds unchanged")


func test_non_locking_repeat_play() -> void:
	Game.set_flag("seen_seq_test_seq_repeat_bark")
	var walk := ScriptedInputSource.new()
	room.player.input_source = walk
	walk.move_x = 1
	var x0 := room.player.global_position.x
	_auto(1.0)
	_start(_seq(BARK))
	await physics_frames(2)
	check(Cinematics.is_playing() and not Cinematics.locks_input(), "plays without a lock")
	check(room.player.global_position.x > x0, "Rook keeps moving")
	check(not Cinematics.overlay.letterbox_on and is_zero_approx(Cinematics.overlay.letterbox_ratio), "no letterbox")
	check(not CinematicMode.hud_hidden, "HUD stays")
	check(Cinematics.current.gate == null, "no skip gate")
	check(Cinematics.overlay.line_on and CinematicMode.bark_line, "bark_line set while its line shows")
	check(not _started(0) and not _started(1), "camera steps are first-view only")
	await _until_finished()
	check(not CinematicMode.bark_line, "bark_line cleared")


func test_pause_quit_aborts_first() -> void:
	_auto(1.0)
	CinematicMode.theatre = true
	var ran: Array = []
	var dummy := func() -> void: ran.append(1)
	CinematicMode.register_teardown(dummy)
	_start(_seq(PARITY))
	await physics_frames(5)
	var pm := _pause_menu()
	pm.open_menu()
	var seen: Array = []
	pm.quit_to_title.connect(func() -> void:
		seen.append([Cinematics.is_playing(), finished[-1][3] if not finished.is_empty() else 99]))
	pm._quit()
	CinematicMode._teardowns.erase(dummy)
	check(seen.size() == 1 and not seen[0][0] and seen[0][1] == -1, "aborted before quit_to_title: %s" % [seen])
	check(ran.size() == 1, "registered teardown ran once")
	check(CinematicMode.current() == CinematicMode.Mode.AUTO and CinematicMode.theatre, "abort_all keeps mode and theatre")
	_check_restored("quit")
	pm.queue_free()


func test_sequence_hud_hide_owner() -> void:
	var hidden_at_end: Array = []
	var probe := func(_id: String, _s: bool, _t: float, _i: int, _n: int, _nom: float) -> void:
		hidden_at_end.append(CinematicMode.hud_hidden)
	EventBus.sequence_finished.connect(probe)
	_auto(4.0)
	_start(_seq(PARITY))
	await physics_frames(2)
	check(CinematicMode.hud_hidden, "a locking play hides the HUD")
	CinematicMode.push_hud_hide(&"memory")
	CinematicMode.pop_hud_hide(&"memory")
	check(CinematicMode.hud_hidden, "a memory's pop leaves the sequence's hide")
	await _until_finished()
	EventBus.sequence_finished.disconnect(probe)
	check(hidden_at_end == [false], "HUD shown by sequence_finished: %s" % [hidden_at_end])


func test_pause_skip_resolves_after_unpause() -> void:
	_auto(1.0)
	_start(_seq(PARITY))
	await physics_frames(5)
	var pm := _pause_menu()
	pm.open_menu()
	var seen: Array = []
	var probe := func(_id: String, skipped: bool, _t: float, _i: int, _n: int, _nom: float) -> void:
		seen.append([skipped, pm.is_open(), get_tree().paused])
	EventBus.sequence_finished.connect(probe)
	var skip := _button(pm, "Skip scene")
	check(skip != null, "Skip scene row")
	if skip:
		skip.pressed.emit()
	check(Cinematics.is_playing(), "the request is deferred to the next unpaused frame")
	check(not pm.is_open(), "the menu closed first")
	await get_tree().process_frame
	await get_tree().process_frame
	EventBus.sequence_finished.disconnect(probe)
	check(seen.size() == 1 and seen[0] == [true, false, false], "skipped after unpause, menu closed: %s" % [seen])
	pm.queue_free()
