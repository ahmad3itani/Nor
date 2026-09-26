extends RedlineTestCase
## M8 dev tooling (T09): the story DevActions (gates, preview, theatres,
## satisfy_ending, replays), the DevConsole Story pages (build, fit the
## 270 px viewport, close-then-play, memory rows), the SequenceInspector,
## DebugOverlay story lines and StoryTestKit.

const RELAY := "res://world/rooms/lowlight/Relay.tscn"
const STORY_PAGES: Array[StringName] = [&"story", &"seq", &"mem", &"presets", &"arcs", &"endings", &"intros"]

var root: Node2D
var _snap: Dictionary
var _extras: Array[Node] = []
var _mp: MemoryScenePlayer
## [id, first_view]
var started: Array = []
## [id, skipped]
var finished: Array = []
## [id, theatre, skipped]
var endings_done: Array = []
## step indices seen by Cinematics.step_started
var steps_seen: Array = []


func before_each() -> void:
	_snap = use_default_m8_settings()
	get_tree().paused = false
	CinematicMode.teardown()
	Cinematics.overlay.clear_all()
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	SaveManager.save_dir = "user://test_story_tools"
	Game.new_game()
	for a: Array in [started, finished, endings_done, steps_seen]:
		a.clear()
	EventBus.sequence_started.connect(_on_started)
	EventBus.sequence_finished.connect(_on_finished)
	EventBus.ending_finished.connect(_on_ending)
	Cinematics.step_started.connect(_on_step)


func after_each() -> void:
	EventBus.sequence_started.disconnect(_on_started)
	EventBus.sequence_finished.disconnect(_on_finished)
	EventBus.ending_finished.disconnect(_on_ending)
	Cinematics.step_started.disconnect(_on_step)
	DevActions.force_unavailable = false
	CinematicMode.teardown()
	Cinematics.overlay.clear_all()
	if is_instance_valid(_mp):
		MemoryScenePlayer.abort_active()
		_mp.free()
	_mp = null
	for n in _extras:
		if is_instance_valid(n):
			n.queue_free()
	_extras.clear()
	get_tree().paused = false
	SceneRouter.current_room = null
	SceneRouter.current_room_path = ""
	SceneRouter.world_root = null
	root.queue_free()
	SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR
	restore_m8_settings(_snap)
	Game.new_game()
	await physics_frames(2)


func _on_started(id: String, first_view: bool) -> void:
	started.append([id, first_view])


func _on_finished(id: String, skipped: bool, _s: float, _i: int, _n: int, _nom: float) -> void:
	finished.append([id, skipped])


func _on_ending(id: String, theatre: bool, skipped: bool) -> void:
	endings_done.append([id, theatre, skipped])


func _on_step(index: int, _label: String) -> void:
	steps_seen.append(index)


func _console() -> MenuScreen:
	var c: MenuScreen = load("res://ui/menus/DevConsole.gd").new()
	add_child(c)
	_extras.append(c)
	return c


func _buttons(menu: MenuScreen) -> Array[Button]:
	var out: Array[Button] = []
	for c in menu._body.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c as Button)
	return out


func _button_starting(menu: MenuScreen, prefix: String) -> Button:
	for b in _buttons(menu):
		if b.text.begins_with(prefix):
			return b
	return null


func _wait(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


# --- DevActions --------------------------------------------------------------------

func test_dev_actions_gated() -> void:
	DevActions.force_unavailable = true
	check(not DevActions.available(), "force_unavailable closes the gate")
	Game.set_flag("mem_seen_mem_first_rest")
	Game.set_flag(MemoryLibrary.REMEMBERED_FLAG, 1)
	Game.set_flag("collector_drone_intro_seen")
	var before: Dictionary = Game.state.flags.duplicate(true)
	var frags := Game.state.memory_fragments.duplicate()
	var requested: Array = []
	var on_req := func(ids: PackedStringArray, _s: StringName) -> void: requested.append(ids)
	EventBus.memory_playback_requested.connect(on_req)
	DevActions.apply_story_preset("krail_down")
	DevActions.grant_all_fragments()
	DevActions.reset_memories()
	DevActions.force_arc_stage("mara", Game.arcs.arc("mara").stages[0].id)
	DevActions.reset_arcs()
	DevActions.play_memory("mem_first_rest")
	DevActions.play_ending("release")
	var restore := DevActions.satisfy_ending("release")
	DevActions.replay_boss_intro("collector_drone")
	DevActions.replay_act1_close()
	var res: Variant = await DevActions.preview_sequence("relay_arrival")
	var res2: Variant = await DevActions.play_sequence("relay_arrival")
	EventBus.memory_playback_requested.disconnect(on_req)
	check(res == null and res2 == null, "preview/play refuse when unavailable")
	check(Game.state.flags == before, "no flag changed: %s" % [Game.state.flags])
	check(Game.state.memory_fragments == frags, "no fragment granted")
	check(requested.is_empty(), "no memory requested")
	check(EndingDirector.running_count() == 0 and not Cinematics.is_playing(), "no ending or sequence started")
	check(not CinematicMode.theatre, "theatre untouched")
	check(not SceneRouter.transitioning and SceneRouter.current_room == null, "no teleport")
	check(restore.is_valid(), "satisfy_ending still returns a callable")
	restore.call()
	check(Game.state.flags == before, "the no-op restore changes nothing")


func test_preview_restores_seen_flag() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.AUTO)
	CinematicMode.auto_speed = 8.0
	# The Relay trigger's own conditions hold, so only the theatre guard can
	# keep it quiet.
	Game.set_flag("collector_drone_defeated")
	for seen: bool in [true, false]:
		started.clear()
		Game.set_flag("seen_seq_relay_arrival", seen)
		var res: SequenceResult = await DevActions.preview_sequence("relay_arrival")
		check(res != null and not res.refused and not res.aborted(), "preview ran (seen=%s)" % seen)
		check(SceneRouter.current_room_path == RELAY, "preview teleported to the Relay")
		for i in 10:
			await get_tree().process_frame
		check(started == [["relay_arrival", true]], "exactly one first view (seen=%s): %s" % [seen, started])
		check(Game.has_flag("seen_seq_relay_arrival") == seen, "seen flag restored to %s" % seen)
		check(not CinematicMode.theatre, "theatre cleared after the preview")
		StoryTestKit.assert_restored(self)
	# A repeat view on request.
	started.clear()
	await DevActions.preview_sequence("relay_arrival", 0)
	check(started == [["relay_arrival", false]], "view 0 plays a repeat: %s" % [started])


func test_satisfy_ending_restores() -> void:
	Game.set_flag("met_orr")
	var snap: Dictionary = Game.state.flags.duplicate(true)
	var restore := DevActions.satisfy_ending("release")
	var r := EndingResolver.resolve()
	check(r != null and r.id == "release", "release resolves when satisfied (%s)" % (r.id if r else "none"))
	restore.call()
	check(Game.state.flags == snap, "profile flags equal the snapshot after restore")
	check(EndingResolver.resolve() == null, "nothing resolves after restore")


func test_act1_max_state_resolves_nothing() -> void:
	StoryTestKit.act1_max_state()
	check(Game.has_flag("act1_complete") and Game.has_flag("warden_krail_defeated"), "Act I max state reached the end of Act I")
	check(EndingResolver.offered().is_empty(), "no ending offered")
	check(EndingResolver.resolve() == null, "no ending resolves in the Act I max state")
	check(DevActions.ending_report().ends_with("resolves now: none"), "ending_report agrees")


func test_state_summary_story_lines() -> void:
	Game.set_flag("seen_seq_uc_opening")
	var text := DevActions.state_summary()
	check(text.contains("Story: act 1 · arcs ") and text.contains("endings seen none"), "story line: %s" % text)
	check(text.contains("SEQ idle") and text.contains("SEQ seen: uc_opening"), "SEQ lines")
	var lines: PackedStringArray = load("res://ui/debug/DebugOverlay.gd").story_lines()
	check(lines.size() == 1 and lines[0] == "ACT 1 (RUN)", "overlay act line: %s" % [lines])


# --- DevConsole Story pages -----------------------------------------------------

func test_dev_console_story_pages_build() -> void:
	var c := _console()
	c.open_menu()
	c._go(&"main")
	check(_button_starting(c, "Story…") != null, "main page has Story…")
	for p in STORY_PAGES:
		c._go(p)
		var usable := _buttons(c).filter(func(b: Button) -> bool:
			return not b.disabled and b.focus_mode == Control.FOCUS_ALL and b.text != "Back" and b.text != "Close")
		check(usable.size() >= 1, "page %s has a focusable row" % p)
		check(_button_starting(c, "Back") != null, "page %s has Back" % p)
	c._go(&"seq")
	# 12 shipped sequences + the view row + the fixture toggle: 2 pages.
	var rows := _buttons(c).map(func(b: Button) -> String: return b.text)
	check(rows.has("View: full") and not rows.any(func(t: String) -> bool: return t.begins_with("test_")), "no fixtures by default: %s" % [rows])
	check(DevActions.sequence_ids().size() == 12, "12 non-test sequences (%d)" % DevActions.sequence_ids().size())
	c.show_test_sequences = true
	c._go(&"seq")
	check(_button_starting(c, "More…") != null, "a long theatre paginates")
	c._next_list_page()
	check(_button_starting(c, "test_") != null or _button_starting(c, "uc_") != null, "the second page lists the rest")
	c._go(&"endings")
	check(_button_starting(c, "Play resolved ending: none in Act I").disabled, "no resolved ending in Act I")
	check(_button_starting(c, "REDLINE  [hidden]") != null, "the hidden ending is tagged")
	check(c._detail.text.contains("✗"), "the focus detail explains the first ending")
	c.close_menu()


func test_story_pages_fit_viewport() -> void:
	var c := _console()
	c.open_menu()
	for p in STORY_PAGES:
		c._go(p)
		var h := await menu_height(c)
		check(h <= 270.0, "page %s is %.0f px tall" % [p, h])
	c.show_test_sequences = true
	c._go(&"seq")
	for i in 2:
		var h := await menu_height(c)
		check(h <= 270.0, "sequence theatre with fixtures, page %d: %.0f px" % [i + 1, h])
		c._next_list_page()
	# The detail of the longest checklist (Release) still fits.
	c._go(&"endings")
	c._show_explain("release")
	var h := await menu_height(c)
	check(h <= 270.0, "ending theatre with Release's checklist: %.0f px" % h)
	c.close_menu()


func test_theatre_row_closes_console() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.AUTO)
	CinematicMode.auto_speed = 1.0
	var c := _console()
	c.open_menu()
	c._go(&"seq")
	check(get_tree().paused, "the console pauses")
	var row := _button_starting(c, "relay_arrival")
	check(row != null, "relay_arrival has a row")
	row.pressed.emit()
	check(not c.is_open() and not get_tree().paused, "the row closes the console first")
	check(await _wait(func() -> bool: return steps_seen.has(0), 5), "step 0 started within 5 frames")
	check(Cinematics.is_playing() and CinematicMode.theatre, "the preview plays under theatre")
	var clock_at := Cinematics.current.clock() if Cinematics.is_playing() else -1.0
	await physics_frames(3)
	check(Cinematics.is_playing() and Cinematics.current.clock() > clock_at, "the sequence advances (not frozen)")
	StoryTestKit.skip_current()
	check(await _wait(func() -> bool: return not finished.is_empty(), 60), "the skip ends it")
	for i in 3:
		await get_tree().process_frame
	check(not CinematicMode.theatre, "theatre cleared")
	check(not Game.has_flag("seen_seq_relay_arrival"), "the preview marks nothing")


func test_play_ending_fire_and_forget() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.AUTO)
	CinematicMode.auto_speed = 8.0
	Game.set_flag("met_nix")
	var before: Dictionary = Game.state.flags.duplicate(true)
	DevActions.play_ending("release")
	check(CinematicMode.theatre, "theatre on while the ending plays")
	check(await _wait(func() -> bool: return not endings_done.is_empty(), 1200), "ending_finished without await")
	await get_tree().process_frame
	check(endings_done.size() == 1 and endings_done[0][0] == "release" and endings_done[0][1], "a theatre ending: %s" % [endings_done])
	check(not CinematicMode.theatre, "theatre off afterwards")
	check(Game.state.flags == before, "flags equal the pre-call snapshot")
	check(not Game.state.flags.keys().any(func(f: String) -> bool: return f.begins_with("finale_choice_")), "no finale_choice_* leaked")
	# Trigger autoplay works again (theatre off): the Relay arrival plays.
	CinematicMode.set_mode(CinematicMode.Mode.INSTANT)
	Game.set_flag("collector_drone_defeated")
	started.clear()
	SceneRouter.goto_room(RELAY, &"from_undercity")
	await physics_frames(3)
	check(started == [["relay_arrival", true]], "the arrival autoplays after the ending: %s" % [started])
	# The Act I close + card replay, fire and forget.
	CinematicMode.set_mode(CinematicMode.Mode.AUTO)
	var card: MenuScreen = load("res://ui/menus/SliceEndMenu.gd").new()
	card.name = "SliceEndMenu"
	add_child(card)
	_extras.append(card)
	var open_card := func(id: StringName) -> void:
		if id == &"slice_end":
			card.open_menu()
	EventBus.menu_requested.connect(open_card)
	before = Game.state.flags.duplicate(true)
	DevActions.replay_act1_close()
	check(await _wait(func() -> bool: return card.is_open(), 1200), "the card opens after the close")
	EventBus.menu_requested.disconnect(open_card)
	check(CinematicMode.theatre, "theatre stays on while the card is up")
	check(Game.has_flag("act1_complete") and Game.has_flag("slice_end_seen"), "the card sees a finished Act I")
	card.close_menu()
	await get_tree().process_frame
	check(not CinematicMode.theatre, "theatre off after the card")
	check(Game.state.flags == before, "flags restored after the replay (act1_complete, slice_end_seen)")
	check(not Game.has_flag("act1_complete") and not Game.has_flag("slice_end_seen"), "the replay marked nothing")


func test_console_memory_row_returns() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.AUTO)
	CinematicMode.auto_speed = 8.0
	_mp = MemoryScenePlayer.new()
	add_child(_mp)
	var c := _console()
	c.open_menu()
	c._go(&"mem")
	c.focus_index(1)
	var row := _buttons(c)[1]
	var id := row.text.get_slice(" ", 0)
	var done: Array = []
	var on_done := func(src: StringName) -> void: done.append(src)
	EventBus.memory_playback_finished.connect(on_done)
	row.pressed.emit()
	check(not c.visible and get_tree().paused and _mp.is_playing(), "console hidden, tree paused, memory playing")
	check(await _wait(func() -> bool: return not done.is_empty(), 3000), "the memory finished in AUTO")
	EventBus.memory_playback_finished.disconnect(on_done)
	await get_tree().process_frame
	check(done == [&"dev"], "source dev: %s" % [done])
	check(c.visible and c.is_open(), "the console is back")
	check(get_tree().paused, "the tree is still paused by the console")
	check(c.focused_index() == 1, "focus back on the row that started it (%d)" % c.focused_index())
	check(MemoryLibrary.is_seen(id), "%s remembered" % id)
	c.close_menu()


# --- Inspector and kit ------------------------------------------------------------

func _probe_sequence() -> SequenceData:
	var seq := SequenceData.new()
	seq.id = "probe_inspector"
	seq.lock_input = true
	seq.letterbox = false
	var a := SeqWait.new()
	a.seconds = 2.0
	var gated := SeqWait.new()
	gated.seconds = 0.5
	gated.only_when = "flag:never_set_probe"
	var repeat_only := SeqWait.new()
	repeat_only.views = 2
	var b := SeqWait.new()
	b.seconds = 1.0
	for s: SequenceStep in [a, gated, repeat_only, b]:
		seq.steps.append(s)
	return seq


func test_inspector_reports_ineligible_steps() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.AUTO)
	CinematicMode.auto_speed = 1.0
	var insp := SequenceInspector.new()
	add_child(insp)
	_extras.append(insp)
	check(insp.build_text() == "SEQ idle", "idle with no history")
	var seq := _probe_sequence()
	Cinematics.play(seq, SequenceContext.for_overlay(null))
	await get_tree().process_frame
	var text := insp.build_text()
	check(text.begins_with("SEQ probe_inspector  first  AUTO"), "header: %s" % text)
	check(text.contains("[skip: flag:never_set_probe]"), "only_when reason shown: %s" % text)
	check(text.contains("[skip: repeat view only]"), "views reason shown")
	check(text.contains("▸ 0 SeqWait"), "cursor on the current step")
	check(text.contains("skip hold") and text.contains("flags set: seen_seq_probe_inspector"), "skip bar and flags")
	var line: PackedStringArray = load("res://ui/debug/DebugOverlay.gd").story_lines()
	check(line.size() == 2 and line[1].begins_with("SEQ probe_inspector 1/4 SeqWait") and line[1].ends_with("first"), "overlay SEQ line: %s" % [line])
	check(DevActions.state_summary().contains("SEQ playing probe_inspector step 1/4 first"), "inspector text in the state summary")
	StoryTestKit.skip_current()
	check(await _wait(func() -> bool: return not Cinematics.is_playing(), 30), "skipped")
	check(insp.build_text().begins_with("SEQ idle · last probe_inspector"), "idle shows the last play: %s" % insp.build_text())
	check(insp.build_text().contains("skipped"), "last play was skipped")


func test_story_test_kit() -> void:
	SceneRouter.goto_room(RELAY, &"start")
	await physics_frames(2)
	var restore := StoryTestKit.flag_sandbox()
	StoryTestKit.apply_preset("relay_met")
	check(Game.has_flag("met_mara") and Game.has_flag("collector_drone_defeated"), "preset applied")
	var mode_before := CinematicMode.current()
	var res: SequenceResult = await StoryTestKit.play_sequence_auto("relay_arrival", 16.0)
	check(res != null and not res.refused and not res.aborted() and not res.instant, "AUTO play ran in real time")
	check(CinematicMode.current() == mode_before and is_equal_approx(CinematicMode.auto_speed, 1.0), "mode and speed put back")
	StoryTestKit.assert_restored(self)
	var all := await StoryTestKit.play_all_instant(PackedStringArray(["relay_arrival", "act1_close"]))
	check(all.size() == 2 and all.all(func(r: SequenceResult) -> bool: return r.instant), "INSTANT plays resolve at once")
	restore.call()
	check(not Game.has_flag("met_mara") and not Game.has_flag("seen_seq_relay_arrival"), "sandbox restored")
