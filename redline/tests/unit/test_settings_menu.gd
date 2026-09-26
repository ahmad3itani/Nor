extends RedlineTestCase
## M9 T03 (D4 §3-§4): the data-built Settings menu. Every page is reachable
## by focus, backs out one level with Cancel or Backspace, ends with an
## explicit Back row, fits the canvas or scrolls at every UI size, and never
## uses a word from the forbidden list.

const TMP := "user://test_settings_menu.cfg"
const SettingsRules := preload("res://devtools/content/rules/SettingsRules.gd")
## The explicit last row of each kind of page.
const BACK_ROWS := ["Back", "Done", "Cancel", "No"]

var _snap: Dictionary = {}
var _menu: MenuScreen


func before_each() -> void:
	_snap = snapshot_settings()
	Settings.remove_settings_files(TMP)
	# SettingsMenu.close_menu always saves: point it at a temp file.
	Settings.load_settings(TMP)
	Settings.apply_defaults()
	InputBindings.apply({})
	UiTheme.invalidate()
	_menu = load("res://ui/menus/SettingsMenu.gd").new()
	add_child(_menu)


func after_each() -> void:
	if is_instance_valid(_menu):
		_menu.close_menu()
		_menu.queue_free()
	get_tree().paused = false
	Challenges.force_active = false
	Challenges.force_reactor_mode = -1
	InputBindings.force_web = -1
	Settings.remove_settings_files(TMP)
	restore_settings(_snap)
	UiTheme.invalidate()


func _buttons() -> Array:
	return _menu._body.get_children().filter(func(n: Node) -> bool: return n is Button and not n.is_queued_for_deletion())


func _texts() -> PackedStringArray:
	var out := PackedStringArray()
	for b: Button in _buttons():
		out.append(b.text)
	return out


func _button(prefix: String) -> Button:
	for b: Button in _buttons():
		if b.text.begins_with(prefix):
			return b
	return null


## Every page id a player can reach, with how to get there from main.
func _page_paths() -> Array:
	var out: Array = [[]]
	for p in Settings.settings_catalog().pages:
		if p.link_label != "":
			out.append([p.id])
	out.append([&"controls", &"action"])
	out.append([&"controls", &"action", &"conflict"])
	out.append([&"visual", &"confirm"])
	out.append([&"confirm"])
	return out


## Opens the menu and walks to a page (main when `path` is empty).
func _open_path(path: Array) -> void:
	_menu.ctx = {}
	_menu.open_menu()
	for id: StringName in path:
		match id:
			&"action":
				_menu._open_action(&"jump")
			&"conflict":
				var l := InputEventKey.new()
				l.physical_keycode = KEY_L
				_menu._capture_slot = {"action": &"jump", "device": &"key", "index": 0, "prev": InputBindings.slots(&"jump", &"key")[0]}
				_menu._on_captured(l)
			&"confirm":
				var reset := _button("Reset")
				reset.pressed.emit()
			_:
				_menu._go(id)


func test_every_row_reachable() -> void:
	for path in _page_paths():
		_open_path(path)
		await get_tree().process_frame
		var rows := _buttons()
		check(rows.size() >= 1, "%s has rows" % str(path))
		for i in rows.size():
			_menu.focus_index(i)
			check((rows[i] as Button).has_focus(), "%s row %d takes focus" % [str(path), i])
			check((rows[i] as Button).focus_mode == Control.FOCUS_ALL, "%s row %d is focusable" % [str(path), i])
		_menu.close_menu()


func test_confirm_cycles_left_right_adjust() -> void:
	_menu.open_menu()
	_menu._go(&"visual")
	var shake := _button("Screen shake") as MenuScreen.OptionRowButton
	check(shake != null, "shake is an option row")
	shake.pressed.emit()
	check(is_equal_approx(Settings.screen_shake_scale, 0.0), "confirm wraps 100% -> 0%")
	(_button("Screen shake") as MenuScreen.OptionRowButton).on_right.call()
	check(is_equal_approx(Settings.screen_shake_scale, 0.1), "right +10%")
	(_button("Screen shake") as MenuScreen.OptionRowButton).on_left.call()
	(_button("Screen shake") as MenuScreen.OptionRowButton).on_left.call()
	check(is_equal_approx(Settings.screen_shake_scale, 0.0), "left clamps at 0%")
	var cvd := _button("Colour-blind mode") as MenuScreen.OptionRowButton
	cvd.pressed.emit()
	check(Settings.colorblind_mode == 1, "confirm cycles a choice")
	(_button("Colour-blind mode") as MenuScreen.OptionRowButton).on_right.call()
	(_button("Colour-blind mode") as MenuScreen.OptionRowButton).on_right.call()
	check(Settings.colorblind_mode == 2, "right clamps at the last choice")
	_button("Colour-blind mode").pressed.emit()
	check(Settings.colorblind_mode == 0, "confirm wraps")
	var flash := _button("Flash reduction") as MenuScreen.OptionRowButton
	flash.on_right.call()
	check(Settings.flash_reduction, "right turns a toggle on")
	(_button("Flash reduction") as MenuScreen.OptionRowButton).on_left.call()
	check(not Settings.flash_reduction, "left turns it off")
	_menu._back()
	_menu._go(&"audio")
	var ui := _button("Interface sounds") as MenuScreen.OptionRowButton
	ui.on_left.call()
	check(is_equal_approx(Settings.ui_volume, 0.7), "interface sounds -10%")


func test_cancel_steps_back_one_level() -> void:
	_menu.open_menu()
	_menu._go(&"controls")
	_button("Dodge / dash:").pressed.emit()
	check(_menu.page == &"action", "action page")
	await press_action(&"ui_cancel", 2)
	check(_menu.page == &"controls" and _menu.is_open(), "cancel: action -> controls (%s)" % _menu.page)
	var focused := _menu.get_viewport().gui_get_focus_owner() as Button
	check(focused != null and focused.text.begins_with("Dodge / dash"), "focus back on the action's row")
	await press_action(&"ui_cancel", 2)
	check(_menu.page == &"main" and _menu.is_open(), "cancel: controls -> main")
	await press_action(&"ui_cancel", 2)
	check(not _menu.is_open(), "cancel on main closes")


func test_forbidden_words_absent() -> void:
	var errs := SettingsRules.wording_errors(Settings.settings_catalog())
	check(errs.is_empty(), "SE-3 clean: %s" % "; ".join(errs))
	var cat := Settings.settings_catalog()
	check(cat.forbidden_in("An easy mode") == PackedStringArray(["easy"]), "the lint finds a forbidden word")
	check(cat.forbidden_in("Hard mode only.") == PackedStringArray(["hard mode"]), "and phrases")
	for path in _page_paths():
		_open_path(path)
		for n in _menu._body.get_children():
			var text := ""
			if n is Button:
				text = (n as Button).text
			elif n is Label:
				text = (n as Label).text
			check(cat.forbidden_in(text).is_empty(), "%s shows '%s'" % [str(path), text])
		_menu.close_menu()


func test_subtitle_rows_unchanged() -> void:
	_menu.open_menu()
	_menu._go(&"subtitles")
	var texts := _texts()
	var m8 := ["Subtitle size: Small", "Subtitle background: Box", "Speaker names: On", "Subtitle speed: Normal",
		"Skip scenes: Hold", "Memories play at Anchors: On"]
	for i in m8.size():
		check(i < texts.size() and texts[i] == m8[i], "M8 row %d is '%s' (%s)" % [i, m8[i], texts[i] if i < texts.size() else "-"])
	check(texts.size() > m8.size() and texts[m8.size()] == "Text auto-advance: Off", "auto-advance appended after the M8 rows")
	check(texts[texts.size() - 1] == "Back", "Back last")


func test_quick_page_from_context() -> void:
	_menu.ctx = {"page": &"quick"}
	_menu.open_menu()
	check(_menu.page == &"quick", "the title link opens the quick page")
	var texts := _texts()
	var want := ["UI size:", "Subtitle size:", "Flash reduction:", "Screen shake:", "Colour-blind mode:", "Button prompts:"]
	for i in want.size():
		check(i < texts.size() and texts[i].begins_with(want[i]), "quick row %d is %s (%s)" % [i, want[i], texts[i] if i < texts.size() else "-"])
	check(texts[texts.size() - 1] == "Done", "Done last")
	_button("Done").pressed.emit()
	check(not _menu.is_open(), "Done closes Settings (saves on close)")
	check(FileAccess.file_exists(TMP), "saved")
	_menu.ctx = {}
	_menu.open_menu()
	check(_menu.page == &"main", "a plain open starts on the main page")


func test_every_page_fits_or_scrolls_at_each_ui_scale() -> void:
	for scale_i in 3:
		Settings.ui_scale = scale_i
		UiTheme.invalidate()
		for path in _page_paths():
			_open_path(path)
			var h := await panel_height(_menu)
			check(h <= 270.0, "ui %d %s: panel %.0f px fits the canvas" % [scale_i, str(path), h])
			check(_menu._panel.get_combined_minimum_size().x <= 480.0, "ui %d %s: fits the width" % [scale_i, str(path)])
			var rows := _buttons()
			_menu.focus_index(rows.size() - 1)
			await get_tree().process_frame
			await get_tree().process_frame
			var last := rows[rows.size() - 1] as Control
			check(_menu._scroll.get_global_rect().grow(1.0).encloses(last.get_global_rect()),
				"ui %d %s: the last row scrolls into view" % [scale_i, str(path)])
			_menu.close_menu()


## R03.8: while a challenge forces the Core mode the row is shown, disabled,
## and confirming it changes nothing (the live ReactorCore keeps the mode).
func test_core_mode_locked_during_forced_challenge() -> void:
	Challenges.force_active = true
	Challenges.force_reactor_mode = 2
	Settings.reactor_mode = 0
	_menu.open_menu()
	_menu._go(&"assists")
	var row := _button("Core mode")
	check(row != null and row.disabled, "row disabled")
	check(row != null and row.text.contains("set by this challenge"), "neutral note (%s)" % (row.text if row else ""))
	if row:
		row.pressed.emit()
	_menu._step(Settings.settings_catalog().def(&"reactor_mode"), 1, true)
	check(Settings.reactor_mode == 0, "the stored mode is untouched")
	Challenges.force_active = false
	Challenges.force_reactor_mode = -1
	_menu._redraw()
	row = _button("Core mode")
	check(row != null and not row.disabled and row.text == "Core mode: Normal", "row back outside challenges")


## R03.17: every page returns to its parent with Backspace alone and shows
## an explicit Back row (web fullscreen keeps Backspace, not Esc).
func test_every_page_backs_out_with_backspace() -> void:
	InputBindings.force_web = 1
	for path in _page_paths():
		_open_path(path)
		var texts := _texts()
		check(BACK_ROWS.has(texts[texts.size() - 1]), "%s ends with an explicit back row (%s)" % [str(path), texts[texts.size() - 1]])
		var depth: int = _menu._stack.size()
		await press_action(&"ui_back", 2)
		await get_tree().process_frame
		if path.is_empty():
			check(not _menu.is_open(), "Backspace on main closes Settings")
		else:
			check(_menu.is_open() and _menu._stack.size() == depth - 1, "%s: Backspace steps back one level" % str(path))
		_menu.close_menu()
	# The quick page (title link) backs out to the title.
	_menu.ctx = {"page": &"quick"}
	_menu.open_menu()
	await press_action(&"ui_back", 2)
	await get_tree().process_frame
	check(not _menu.is_open(), "Backspace on the quick page closes")
	_menu.ctx = {}


func test_rebind_through_the_menu() -> void:
	_menu.open_menu()
	_menu._go(&"controls")
	var jump_row := _button("Jump:")
	check(jump_row != null and jump_row.text == "Jump: Space · K · Z", "Controls lists the keyboard bindings (%s)" % (jump_row.text if jump_row else ""))
	_menu._open_action(&"jump")
	var y := InputEventKey.new()
	y.physical_keycode = KEY_Y
	_menu._capture_slot = {"action": &"jump", "device": &"key", "index": 1, "prev": InputBindings.slots(&"jump", &"key")[1]}
	_menu._on_captured(y)
	check(Settings.bindings == {"jump": {"key": ["k32", "k%d" % KEY_Y, "k90"]}}, "slot 2 rebound (%s)" % Settings.bindings)
	check(InputGlyphs.labels(&"jump", &"key") == "Space · Y · Z", "prompts follow")
	# A conflict opens the conflict page; Swap resolves it.
	var l := InputEventKey.new()
	l.physical_keycode = KEY_L
	_menu._capture_slot = {"action": &"jump", "device": &"key", "index": 1, "prev": y}
	_menu._on_captured(l)
	check(_menu.page == &"conflict", "conflict page")
	check(_button("Swap") != null and _button("Move it here") != null and _button("Cancel") != null, "swap, move and cancel offered")
	_button("Swap").pressed.emit()
	check(_menu.page == &"action", "back on the action page")
	check(InputGlyphs.labels(&"jump", &"key") == "Space · L · Z" and InputGlyphs.labels(&"dodge", &"key").contains("Y"), "swapped")
	# Remove mode refuses the last pad button.
	_menu._device = &"pad"
	_menu._redraw()
	_menu._remove_mode = true
	_menu._slot_pressed(0)
	check(_menu._notice.contains("Keep at least one button"), "parity note (%s)" % _menu._notice)
	_menu.close_menu()
	var cfg := ConfigFile.new()
	cfg.load(TMP)
	check((cfg.get_value("input", "bindings", {}) as Dictionary).has("jump"), "bindings saved on close")
