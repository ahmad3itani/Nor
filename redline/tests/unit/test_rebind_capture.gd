extends RedlineTestCase
## M9 T03 (D4 §4.5): RebindCapture listens for exactly one input. Driven with
## synthetic events and manual _process ticks; no real device is used.

const TMP := "user://test_rebind_capture.cfg"

var _snap: Dictionary = {}
var _cap: RebindCapture
## [held?] read by the capture's held_probe (headless has no devices).
var _held: Array = [false]
var _got: Array = []
var _cancelled: Array = []


func before_each() -> void:
	_snap = snapshot_settings()
	Settings.load_settings(TMP)
	InputBindings.apply({})
	_held = [false]
	_got = []
	_cancelled = []
	_cap = RebindCapture.new()
	add_child(_cap)
	var held := _held
	_cap.held_probe = func() -> bool: return bool(held[0])
	var got := _got
	var cancelled := _cancelled
	_cap.captured.connect(func(ev: InputEvent) -> void: got.append(ev))
	_cap.cancelled.connect(func(reason: StringName) -> void: cancelled.append(reason))


func after_each() -> void:
	_cap.queue_free()
	get_tree().paused = false
	Settings.remove_settings_files(TMP)
	restore_settings(_snap)


func _key(code: int, pressed := true, echo := false) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code as Key
	k.keycode = code as Key
	k.pressed = pressed
	k.echo = echo
	return k


func _button(i: int, pressed := true) -> InputEventJoypadButton:
	var b := InputEventJoypadButton.new()
	b.button_index = i as JoyButton
	b.pressed = pressed
	return b


func _motion(axis: int, value: float) -> InputEventJoypadMotion:
	var m := InputEventJoypadMotion.new()
	m.axis = axis as JoyAxis
	m.axis_value = value
	return m


## Starts a capture and ticks it past arming.
func _listen(device: StringName) -> void:
	_cap.start("Jump", device)
	_cap._process(1.0)


func test_arming_ignores_held_confirm() -> void:
	_held[0] = true
	_cap.start("Jump", &"key")
	_cap._process(0.5)
	check(_cap.state == RebindCapture.State.ARMING, "still arming while the confirm key is held")
	_cap._input(_key(KEY_ENTER))
	check(_got.is_empty(), "the held confirm never binds")
	_held[0] = false
	_cap._process(0.05)
	check(_cap.state == RebindCapture.State.LISTENING, "listening once released")
	_cap._input(_key(KEY_J))
	check(_got.size() == 1, "captured after arming")


func test_key_captured_physical() -> void:
	_listen(&"key")
	_cap._input(_key(KEY_J))
	check(_got.size() == 1, "one capture")
	var k := _got[0] as InputEventKey
	check(k != null and k.physical_keycode == KEY_J and k.keycode == KEY_NONE, "stored by physical keycode only")
	check(_cap.state == RebindCapture.State.DONE and _cap.end_frame == Engine.get_process_frames(), "done this frame")


func test_echo_ignored() -> void:
	_listen(&"key")
	_cap._input(_key(KEY_J, true, true))
	_cap._input(_key(KEY_J, false))
	check(_got.is_empty(), "echo and release ignored")
	_cap._input(_key(KEY_K))
	check(_got.size() == 1, "a real press captures")


func test_trigger_threshold() -> void:
	_listen(&"pad")
	_cap._input(_motion(JOY_AXIS_TRIGGER_RIGHT, 0.3))
	check(_got.is_empty(), "a light trigger touch is ignored")
	_cap._input(_motion(JOY_AXIS_TRIGGER_RIGHT, 0.8))
	check(_got.size() == 1 and InputBindings.encode(_got[0]) == "a5+", "a full pull binds a5+")


func test_stick_ignored() -> void:
	_listen(&"pad")
	_cap._input(_motion(JOY_AXIS_LEFT_X, 1.0))
	_cap._input(_motion(JOY_AXIS_RIGHT_Y, -1.0))
	check(_got.is_empty() and _cap.is_active(), "sticks never bind (drift)")
	_cap._input(_button(JOY_BUTTON_X))
	check(_got.size() == 1 and InputBindings.encode(_got[0]) == "b2", "a button binds")


func test_device_mismatch_message() -> void:
	_listen(&"pad")
	_cap._input(_key(KEY_J))
	check(_got.is_empty() and _cap.message == "Waiting for a controller button.", "pad slot names what it waits for (%s)" % _cap.message)
	_listen(&"key")
	_cap._input(_button(JOY_BUTTON_A))
	check(_got.is_empty() and _cap.message == "Waiting for a key.", "key slot too (%s)" % _cap.message)


func test_timeout_cancels() -> void:
	_cap.start("Jump", &"key")
	_cap.timeout_sec = 1.0
	_cap._process(0.2)
	_cap._process(0.6)
	check(_cap.is_active(), "still listening")
	_cap._process(0.6)
	check(not _cap.is_active() and _cancelled == [&"timeout"], "timed out (%s)" % str(_cancelled))


func test_timeout_from_config_and_none() -> void:
	Settings.rebind_wait = 0
	_cap.start("Jump", &"key")
	check_near(_cap.timeout_sec, 5.0, 0.001, "5 s wait")
	Settings.rebind_wait = 1
	_cap.start("Jump", &"key")
	check_near(_cap.timeout_sec, 10.0, 0.001, "10 s default")
	Settings.rebind_wait = 2
	_cap.start("Jump", &"key")
	check(_cap.timeout_sec == 0.0, "no limit")
	_cap._process(0.5)
	_cap._process(600.0)
	check(_cap.is_active() and _cancelled.is_empty(), "no limit never times out")
	check(not _cap.prompt_text().contains("·"), "no countdown shown")


func test_start_cancels_key_slot() -> void:
	_listen(&"key")
	_cap._input(_button(JOY_BUTTON_START))
	check(_cancelled == [&"cancelled"] and _got.is_empty(), "Start cancels a key capture")


func test_esc_cancels_pad_slot() -> void:
	_listen(&"pad")
	_cap._input(_key(KEY_ESCAPE))
	check(_cancelled == [&"cancelled"] and _got.is_empty(), "Esc cancels a pad capture")


## R03.17: Backspace cancels any capture, even with no time limit and no
## pad, and can never be bound.
func test_backspace_cancels_and_is_reserved() -> void:
	Settings.rebind_wait = 2
	_listen(&"key")
	_cap._input(_key(KEY_BACKSPACE))
	check(_cancelled.size() == 1 and _got.is_empty(), "Backspace cancels a key capture")
	_listen(&"pad")
	_cap._input(_key(KEY_BACKSPACE))
	check(_cancelled.size() == 2 and _got.is_empty(), "Backspace cancels a pad capture")
	var bs := InputEventKey.new()
	bs.physical_keycode = KEY_BACKSPACE
	for a in InputBindings.catalog().action_names():
		check(InputBindings.conflicts(a, bs).has(&"reserved"), "%s cannot take Backspace" % a)
	# Through the menu: a reserved capture result binds nothing.
	var menu := _menu()
	menu._open_action(&"jump")
	var before := Settings.bindings.duplicate(true)
	menu._capture_slot = {"action": &"jump", "device": &"key", "index": 0, "prev": null}
	menu._on_captured(bs)
	check(Settings.bindings == before, "no binding changed")
	check(menu._notice.contains("Backspace"), "neutral note (%s)" % menu._notice)
	menu.close_menu()
	menu.queue_free()


func test_esc_cancels_and_does_not_close_page() -> void:
	var menu := _menu()
	menu._go(&"controls")
	menu._open_action(&"jump")
	check(menu.page == &"action", "on the action page")
	menu._capture.held_probe = func() -> bool: return false
	menu._slot_pressed(0)
	check(menu._capture.is_active(), "capture started")
	menu._capture._process(1.0)
	check(menu._capture.state == RebindCapture.State.LISTENING, "listening")
	# The real Esc press is both a key event for the capture and ui_cancel
	# for the menu on the same frame.
	menu._capture._input(_key(KEY_ESCAPE))
	await press_action(&"ui_cancel", 2)
	await get_tree().process_frame
	check(menu.is_open() and menu.page == &"action", "the Esc that cancelled the capture did not leave the page (%s)" % menu.page)
	check(not menu._capture.is_active(), "capture cancelled")
	check(Settings.bindings.is_empty(), "nothing bound")
	# A later Esc steps back one level as usual.
	await press_action(&"ui_cancel", 2)
	await get_tree().process_frame
	check(menu.page == &"controls", "next Esc goes back to Controls (%s)" % menu.page)
	menu.close_menu()
	menu.queue_free()


func _menu() -> MenuScreen:
	var menu: MenuScreen = load("res://ui/menus/SettingsMenu.gd").new()
	add_child(menu)
	menu.open_menu()
	return menu
