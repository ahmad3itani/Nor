extends RedlineTestCase
## M8 foundation (T01): the Subtitles & scenes settings page, SkipGate (the one
## advance/skip rule for sequences, memory vignettes and endings),
## CinematicMode, SubtitleStyle/DialogueBox geometry and the HUD hint hold.
## Every test restores what it changes (settings, CinematicMode, pause).

const TEMP_SETTINGS := "user://test_m8_settings.cfg"

var _snap: Dictionary = {}


func before_each() -> void:
	_snap = use_default_m8_settings()
	# SettingsMenu.close_menu always saves: point it at a temp file.
	Settings.load_settings(TEMP_SETTINGS)


func after_each() -> void:
	Settings.load_settings(Settings.SETTINGS_PATH)
	DirAccess.remove_absolute(TEMP_SETTINGS)
	restore_m8_settings(_snap)
	get_tree().paused = false


func _button(menu: MenuScreen, prefix: String) -> Button:
	for n in menu._body.get_children():
		if n is Button and (n as Button).text.begins_with(prefix):
			return n
	return null


func test_settings_menu_fits_viewport() -> void:
	var menu: MenuScreen = load("res://ui/menus/SettingsMenu.gd").new()
	add_child(menu)
	menu.open_menu()
	var h_main: float = await menu_height(menu)
	check(h_main <= 270.0, "settings main page is %.0f px tall (> 270)" % h_main)
	check(h_main > 100.0, "panel height not measured (%.0f px)" % h_main)
	print("  settings main page %.0f px" % h_main)
	var sub := _button(menu, "Subtitles & scenes")
	check(sub != null, "main page has no 'Subtitles & scenes…' row")
	if sub == null:
		menu.close_menu()
		menu.queue_free()
		return
	sub.pressed.emit()
	check(menu.page == &"subtitles", "row did not open the sub-page")
	check(_button(menu, "Subtitle size: Small") != null, "sub-page lacks the size row")
	for prefix in ["Subtitle background: Box", "Speaker names: On", "Subtitle speed: Normal", "Skip scenes: Hold", "Memories play at Anchors: On", "Back"]:
		check(_button(menu, prefix) != null, "sub-page lacks row '%s'" % prefix)
	var h_sub: float = await menu_height(menu)
	check(h_sub <= 270.0, "subtitles page is %.0f px tall (> 270)" % h_sub)
	print("  subtitles page %.0f px" % h_sub)
	# Rows cycle their setting.
	_button(menu, "Subtitle size").pressed.emit()
	check(Settings.subtitle_size == 1, "size row did not cycle")
	_button(menu, "Subtitle size").pressed.emit()
	_button(menu, "Subtitle size").pressed.emit()
	check(Settings.subtitle_size == 0, "size row did not wrap")
	# Back returns to main and focuses the row that opened the page.
	_button(menu, "Back").pressed.emit()
	check(menu.page == &"main" and menu.is_open(), "Back did not return to the main page")
	await get_tree().process_frame
	var focused := menu.get_viewport().gui_get_focus_owner() as Button
	check(focused != null and focused.text.begins_with("Subtitles & scenes"), "Back did not focus the Subtitles row")
	# Cancel on the sub-page goes back instead of closing.
	_button(menu, "Subtitles & scenes").pressed.emit()
	await press_action(&"ui_cancel", 2)
	await get_tree().process_frame
	check(menu.is_open(), "ui_cancel on the sub-page closed the menu")
	check(menu.page == &"main", "ui_cancel on the sub-page did not return to main")
	menu.close_menu()
	check(not get_tree().paused, "menu did not unpause")
	menu.open_menu()
	check(menu.page == &"main", "open_menu must reset to the main page")
	menu.close_menu()
	menu.queue_free()


# --- SkipGate (pure logic) ---

const DT := 1.0 / 60.0

var _prev_skip := false
var _prev_adv := false


## Feeds `gate` frame by frame. segments: [seconds, skip_held, adv_held];
## just_pressed is derived from the previous frame. Returns every non-NONE
## output as [Out, time].
func _drive(gate: SkipGate, segments: Array) -> Array:
	var outs: Array = []
	var t := 0.0
	for seg in segments:
		var frames := roundi(float(seg[0]) / DT)
		for i in frames:
			var s: bool = seg[1]
			var a: bool = seg[2]
			var o := gate.update(DT, s, s and not _prev_skip, a, a and not _prev_adv)
			_prev_skip = s
			_prev_adv = a
			t += DT
			if o != SkipGate.Out.NONE:
				outs.append([o, t])
	return outs


func _new_gate(first_view: bool) -> SkipGate:
	_prev_skip = false
	_prev_adv = false
	return SkipGate.new(first_view)


func _kinds(outs: Array) -> Array:
	return outs.map(func(o: Array) -> int: return o[0])


func test_skip_gate_first_view_needs_hold() -> void:
	var g := _new_gate(true)
	check(not g.prompt_visible, "first view prompt must start hidden")
	# A 0.5 s hold (Space = skip + advance) then release: neither TAP nor SKIP.
	var outs := _drive(g, [[0.3, false, false], [0.5, true, true], [0.1, false, false]])
	check(outs.is_empty(), "a 0.5 s hold must do nothing on a first view (got %s)" % str(_kinds(outs)))
	check(g.progress_ratio() == 0.0, "progress must reset on release")
	outs = _drive(g, [[0.85, true, true]])
	check(_kinds(outs) == [SkipGate.Out.SKIP], "a 0.85 s hold must skip (got %s)" % str(_kinds(outs)))
	# Prompt: hidden until the first tracked press, then 2 s after a tap.
	g = _new_gate(true)
	_drive(g, [[0.3, false, false]])
	check(not g.prompt_visible, "prompt visible before any press")
	outs = _drive(g, [[0.1, true, true], [0.05, false, false]])
	check(_kinds(outs) == [SkipGate.Out.TAP], "single tap should TAP")
	check(g.prompt_visible, "prompt must show right after a tap on a first view")
	check(g.prompt_text().begins_with("Hold ["), "hold prompt text: %s" % g.prompt_text())
	_drive(g, [[2.0, false, false]])
	check(not g.prompt_visible, "prompt must hide 2 s after the last press")
	# Progress grows while holding and resets on release.
	g = _new_gate(true)
	_drive(g, [[0.3, false, false], [0.5, true, true]])
	check(g.progress_ratio() > 0.3, "progress must grow while holding (%.2f)" % g.progress_ratio())
	_drive(g, [[DT, false, false]])
	check(g.progress_ratio() == 0.0, "progress must reset on release")


func test_skip_gate_tap_advances_never_skips() -> void:
	for first in [true, false]:
		var g := _new_gate(first)
		var outs := _drive(g, [[0.3, false, false], [0.2, true, true], [0.3, false, false]])
		check(_kinds(outs) == [SkipGate.Out.TAP], "first_view=%s: a 0.2 s tap must TAP once (got %s)" % [first, str(_kinds(outs))])
		if outs.size() == 1:
			# Fired on the release frame (0.3 + 0.2 s, then the release frame).
			check_near(outs[0][1], 0.5 + DT, 0.001, "TAP must fire on the release frame")


func test_skip_gate_repeat_short_hold() -> void:
	var g := _new_gate(false)
	check(g.prompt_visible, "repeat view prompt must show from frame 0")
	var outs := _drive(g, [[0.3, false, false], [0.45, true, false]])
	check(_kinds(outs) == [SkipGate.Out.SKIP], "repeat view 0.45 s hold must skip (got %s)" % str(_kinds(outs)))
	g = _new_gate(false)
	outs = _drive(g, [[0.3, false, false], [1.0, false, true], [0.1, false, false]])
	check(outs.is_empty(), "holding an advance-only action must never skip (got %s)" % str(_kinds(outs)))


func test_skip_gate_grace_and_carried_press() -> void:
	var g := _new_gate(true)
	var outs := _drive(g, [[0.1, false, false], [1.0, true, true], [0.1, false, false]])
	check(outs.is_empty(), "a press begun inside the grace must never fire (got %s)" % str(_kinds(outs)))
	# A press already down when the gate starts (entry mash).
	g = _new_gate(true)
	_prev_skip = true
	_prev_adv = true
	outs = _drive(g, [[1.0, true, true]])
	check(outs.is_empty(), "a press held from before the gate must never fire")
	# A press carried across a pause is dropped until released.
	g = _new_gate(true)
	_drive(g, [[0.3, false, false], [0.5, true, true]])
	g.notify_unpaused()
	outs = _drive(g, [[1.0, true, true]])
	check(outs.is_empty(), "a press held across notify_unpaused must be ignored (got %s)" % str(_kinds(outs)))
	outs = _drive(g, [[0.3, false, false], [0.1, true, true], [0.1, false, false]])
	check(_kinds(outs) == [SkipGate.Out.TAP], "after release, a new tap works again (got %s)" % str(_kinds(outs)))


func test_skip_gate_press_twice_setting() -> void:
	Settings.cinematic_skip_hold = false
	var tap := [0.05, true, true]
	# Repeat view (gaps are release to next press).
	var g := _new_gate(false)
	var outs := _drive(g, [[0.3, false, false], tap, [0.3, false, false], tap, [0.1, false, false]])
	check(_kinds(outs) == [SkipGate.Out.TAP, SkipGate.Out.SKIP], "repeat: taps 0.3 s apart -> TAP, SKIP (got %s)" % str(_kinds(outs)))
	g = _new_gate(false)
	outs = _drive(g, [[0.3, false, false], tap, [0.1, false, false], tap, [0.1, false, false]])
	check(_kinds(outs) == [SkipGate.Out.TAP], "repeat: taps 0.1 s apart -> TAP, NONE (got %s)" % str(_kinds(outs)))
	g = _new_gate(false)
	outs = _drive(g, [[0.3, false, false], tap, [0.9, false, false], tap, [0.1, false, false]])
	check(_kinds(outs) == [SkipGate.Out.TAP, SkipGate.Out.TAP], "repeat: taps 0.9 s apart -> TAP, TAP (got %s)" % str(_kinds(outs)))
	# First view.
	g = _new_gate(true)
	outs = _drive(g, [[0.3, false, false], tap, [0.1, false, false], tap, [0.1, false, false]])
	check(_kinds(outs) == [SkipGate.Out.TAP], "first: taps 0.1 s apart -> one advance, no skip (got %s)" % str(_kinds(outs)))
	g = _new_gate(true)
	outs = _drive(g, [[0.3, false, false], tap, [0.3, false, false], tap, [0.1, false, false]])
	check(_kinds(outs) == [SkipGate.Out.TAP, SkipGate.Out.TAP], "first: the first window only teaches (got %s)" % str(_kinds(outs)))
	check(g.prompt_visible and g.prompt_text().contains("again to skip"), "press-twice prompt not shown: %s" % g.prompt_text())
	outs = _drive(g, [[1.0, false, false], tap, [0.3, false, false], tap, [0.1, false, false]])
	check(_kinds(outs) == [SkipGate.Out.TAP, SkipGate.Out.SKIP], "first: a later pair skips (got %s)" % str(_kinds(outs)))
	# Holds keep working under Press twice.
	g = _new_gate(true)
	outs = _drive(g, [[0.3, false, false], [0.85, true, true]])
	check(_kinds(outs) == [SkipGate.Out.SKIP], "hold must still skip under Press twice (got %s)" % str(_kinds(outs)))


func test_skip_gate_skip_action_alone() -> void:
	var g := _new_gate(true)
	var outs := _drive(g, [[0.3, false, false], [0.85, true, false]])
	check(_kinds(outs) == [SkipGate.Out.SKIP], "cinematic_skip alone held 0.85 s must skip (got %s)" % str(_kinds(outs)))
	g = _new_gate(true)
	outs = _drive(g, [[0.3, false, false], [0.1, true, false], [0.1, false, false]])
	check(outs.is_empty(), "a short cinematic_skip-only press is not an advance (got %s)" % str(_kinds(outs)))
	g = _new_gate(true)
	outs = _drive(g, [[0.3, false, false], [0.1, true, true], [0.1, false, false]])
	check(_kinds(outs) == [SkipGate.Out.TAP], "the same press with an advance action must TAP (got %s)" % str(_kinds(outs)))


func test_advance_actions_match_dialogue_box() -> void:
	var box_script: GDScript = preload("res://ui/dialogue/DialogueBox.gd")
	check(SkipGate.ADVANCE_ACTIONS == box_script.ADVANCE_ACTIONS, "SkipGate.ADVANCE_ACTIONS drifted from DialogueBox")


func test_cinematic_mode_headless_is_instant() -> void:
	CinematicMode.teardown()
	check(CinematicMode.current() == CinematicMode.Mode.INSTANT, "headless runner must default to INSTANT")
	CinematicMode.set_mode(CinematicMode.Mode.AUTO)
	check(CinematicMode.current() == CinematicMode.Mode.AUTO, "set_mode(AUTO) did not stick")
	check(CinematicMode.current() == CinematicMode.Mode.AUTO, "set_mode(AUTO) did not stick on a second read")
	var calls: Array = []
	var probe := func() -> void: calls.append(1)
	CinematicMode.register_teardown(probe)
	CinematicMode.register_teardown(probe)
	CinematicMode.push_hud_hide(&"sequence")
	CinematicMode.bark_line = true
	CinematicMode.theatre = true
	CinematicMode.teardown()
	check(calls.size() == 1, "teardown must run each registered callable once (ran %d)" % calls.size())
	check(CinematicMode.current() == CinematicMode.Mode.INSTANT, "teardown must restore INSTANT")
	check(not CinematicMode.hud_hidden and not CinematicMode.bark_line and not CinematicMode.theatre, "teardown left a flag set")
	CinematicMode._teardowns.erase(probe)


func test_glyph_labels_nonempty() -> void:
	var was_pad := InputGlyphs.using_pad
	var expected := {false: ["Space", "Space", "E"], true: ["A", "A", "D-Pad Up"]}
	var names := ["cinematic_skip", "jump", "interact"]
	for pad in [false, true]:
		InputGlyphs.using_pad = pad
		var labels := [InputGlyphs.label(&"cinematic_skip"), InputGlyphs.label(&"jump"), InputGlyphs.label(&"interact")]
		for i in 3:
			check(labels[i] != "" and labels[i] != names[i], "pad=%s: %s label is '%s'" % [pad, names[i], labels[i]])
		check(labels == expected[pad], "pad=%s: labels %s, expected %s" % [pad, str(labels), str(expected[pad])])
		for first in [true, false]:
			for hold in [true, false]:
				Settings.cinematic_skip_hold = hold
				var g := SkipGate.new(first)
				check(not g.prompt_text().contains("[]"), "prompt has an empty glyph: %s" % g.prompt_text())
	InputGlyphs.using_pad = was_pad


func test_press_action_helper_timing() -> void:
	var probe := _InputProbe.new()
	add_child(probe)
	await get_tree().process_frame
	await press_action(&"cinematic_skip", 3)
	await get_tree().process_frame
	check(probe.just_frames == 1, "expected exactly one just_pressed frame, got %d" % probe.just_frames)
	check(probe.held_frames == 3, "expected 3 held frames, got %d" % probe.held_frames)
	check(not Input.is_action_pressed(&"cinematic_skip"), "the helper did not release the action")
	probe.queue_free()


# --- SubtitleStyle / DialogueBox ---

## DialogueBox has no class_name, so the box is handled untyped here.
func _open_box(text: String) -> Variant:
	var box = load("res://ui/dialogue/DialogueBox.gd").new()
	add_child(box)
	var line := DialogueLine.new()
	line.speaker = "Orr"
	line.text = text
	var d := DialogueData.new()
	d.id = "test_m8_geometry"
	d.lines = [line]
	box.open(d, "Orr")
	return box


func _close_box(box: Variant) -> void:
	box.dialogue = null
	box.visible = false
	get_tree().paused = false
	box.queue_free()


func test_dialogue_box_geometry() -> void:
	var box = _open_box("Keep your head down in the Relay.")
	await get_tree().process_frame
	var view: Vector2 = box._root.size
	check(view == Vector2(480, 270), "dialogue root is %s, expected the 480x270 canvas" % str(view))
	check(SubtitleStyle.font_size() == 7, "default font must be 7 (got %d)" % SubtitleStyle.font_size())
	check(SubtitleStyle.label_y() == 12, "default label offset must be 12 (got %d)" % SubtitleStyle.label_y())
	check(SubtitleStyle.text_y() == 25, "default text offset must be 25 (got %d)" % SubtitleStyle.text_y())
	var r: Rect2 = box.box_rect()
	check(box.line_count() == 1, "short line should be one row (got %d)" % box.line_count())
	check(r == Rect2(24, view.y - 78, view.x - 48, 62), "default box must be the M7 rect, got %s" % str(r))
	# Largest size: a 200-character line fits inside its taller box, same bottom.
	var long_text := "The lift cables hum all night, and every hum is someone climbing out of the Undercity with nothing but a wrench, a name and a debt to the Relay that nobody ever finishes paying back."
	while long_text.length() < 200:
		long_text += " Again."
	_close_box(box)
	Settings.subtitle_size = 2
	box = _open_box(long_text.substr(0, 200))
	await get_tree().process_frame
	r = box.box_rect()
	var lines: int = box.line_count()
	check(SubtitleStyle.font_size() == 11, "size 2 must be 11 px")
	check(lines >= 2, "a 200-char line at 11 px should wrap (got %d rows)" % lines)
	check(SubtitleStyle.text_y() + lines * 13 + 6 <= r.size.y, "200-char line overflows: %d rows in a %.0f px box" % [lines, r.size.y])
	check(SubtitleStyle.text_y() + lines * SubtitleStyle.line_spacing() + 6 <= r.size.y, "rows at the real spacing overflow the box")
	check(is_equal_approx(r.end.y, view.y - 16), "the box bottom must stay at view.y - 16")
	check(r.position.y >= 0.0, "the box must stay on screen")
	# Speaker labels off: text moves up to the label row.
	Settings.speaker_labels = false
	check(SubtitleStyle.text_y() == SubtitleStyle.label_y(), "without labels text starts at the label row")
	_close_box(box)


func test_background_three_looks() -> void:
	var expected_box := [0.0, 0.92, 1.0]
	var expected_sub := [0.0, 0.6, 0.92]
	for i in 3:
		Settings.subtitle_background = i
		check(is_equal_approx(SubtitleStyle.box_alpha(), expected_box[i]), "box_alpha(%d) = %.2f" % [i, SubtitleStyle.box_alpha()])
		check(is_equal_approx(SubtitleStyle.subtitle_alpha(), expected_sub[i]), "subtitle_alpha(%d) = %.2f" % [i, SubtitleStyle.subtitle_alpha()])
		check(SubtitleStyle.outline() == (i == 0), "outline must be on only for setting 0")
	Settings.subtitle_speed = 2
	check(is_equal_approx(SubtitleStyle.time_scale(), 2.0), "Slower must scale line time by 2")


# --- HUD hint hold ---

## CombatHud has no class_name; it is handled untyped like in test_onboarding.
func _hud() -> Variant:
	var hud = load("res://ui/hud/CombatHud.gd").new()
	add_child(hud)
	return hud


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func test_hint_during_hidden_hud_is_queued() -> void:
	CinematicMode.teardown()
	var hud = _hud()
	await get_tree().process_frame
	hud._banner_time = 2.0
	hud._lore_time = 5.0
	CinematicMode.hud_hidden = true
	EventBus.hint_requested.emit("x", 3.0)
	var shown := false
	for i in 60:
		await get_tree().process_frame
		if hud.current_hint() != "":
			shown = true
	check(not shown, "a hint showed while the HUD was hidden")
	check(hud._hint_queue.size() == 1 and hud._hint_queue[0][0] == "x", "the hint was not queued: %s" % str(hud._hint_queue))
	check(is_equal_approx(hud._banner_time, 2.0), "banner timer ran while hidden (%.2f)" % hud._banner_time)
	check(is_equal_approx(hud._lore_time, 5.0), "fragment card timer ran while hidden (%.2f)" % hud._lore_time)
	CinematicMode.hud_hidden = false
	await _frames(2)
	check(hud.current_hint() == "x", "the queued hint did not show when the HUD returned")
	check(hud._hint_time >= 2.9, "the hint lost time while queued (%.2f s left)" % hud._hint_time)
	await _frames(170)
	check(hud.current_hint() == "x", "the hint must stay up for its full duration")
	hud.queue_free()
	CinematicMode.teardown()


func test_bark_line_holds_hints() -> void:
	CinematicMode.teardown()
	var hud = _hud()
	await get_tree().process_frame
	CinematicMode.bark_line = true
	EventBus.hint_requested.emit("y", 2.0)
	await _frames(10)
	check(hud.current_hint() == "", "a hint showed under a bark line")
	check(hud._hint_queue.size() == 1, "the hint was not queued under the bark")
	check(not CinematicMode.hud_hidden, "a bark must not hide the HUD")
	CinematicMode.bark_line = false
	await _frames(2)
	check(hud.current_hint() == "y", "the hint did not show after the bark")
	hud.queue_free()
	CinematicMode.teardown()


func test_hud_hide_owner_counted() -> void:
	CinematicMode.teardown()
	var hud = _hud()
	await get_tree().process_frame
	CinematicMode.push_hud_hide(&"sequence")
	CinematicMode.push_hud_hide(&"memory")
	CinematicMode.pop_hud_hide(&"memory")
	check(CinematicMode.hud_hidden, "popping one owner must keep the HUD hidden for the other")
	EventBus.hint_requested.emit("z", 2.0)
	await _frames(5)
	check(hud.current_hint() == "", "hint showed while the sequence still hides the HUD")
	CinematicMode.pop_hud_hide(&"never_pushed")
	check(CinematicMode.hud_hidden, "popping an unknown owner must be a no-op")
	CinematicMode.pop_hud_hide(&"sequence")
	check(not CinematicMode.hud_hidden, "HUD still hidden after the last owner popped")
	await _frames(2)
	check(hud.current_hint() == "z", "the hint did not show after the last owner popped")
	CinematicMode.push_hud_hide(&"sequence")
	CinematicMode.push_hud_hide(&"memory")
	CinematicMode.teardown()
	check(not CinematicMode.hud_hidden and CinematicMode._hud_owners.is_empty(), "teardown must clear every owner")
	hud.queue_free()


class _InputProbe extends Node:
	var just_frames := 0
	var held_frames := 0

	func _process(_delta: float) -> void:
		if Input.is_action_just_pressed(&"cinematic_skip"):
			just_frames += 1
		if Input.is_action_pressed(&"cinematic_skip"):
			held_frames += 1
