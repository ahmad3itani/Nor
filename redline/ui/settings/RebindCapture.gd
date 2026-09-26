class_name RebindCapture
extends Node
## Listens for one input to bind (D4 §4.5). A small state machine:
## ARMING waits until every key and button is released (and a short real-time
## pause passes), so the confirm press that started the capture never binds
## itself; LISTENING takes the first key (key slot) or pad button / trigger
## (pad slot). Esc, Backspace and pad Start cancel any slot (R03.7, R03.17),
## so even "Rebind wait: No limit" with no pad connected can always be left.
## Sticks are ignored (drift never binds), and so is the mouse.
## Every event it handles is marked handled, so the menu under it never sees
## the press; SettingsMenu also ignores ui_cancel on the frame it ends.

signal captured(ev: InputEvent)
signal cancelled(reason: StringName)
## The prompt or the "waiting for" line changed (SettingsMenu redraws it).
signal message_changed(text: String)

enum State { IDLE, ARMING, LISTENING, DONE }

## Keys that cancel a capture of either kind (never bindable: RebindCatalog).
const CANCEL_KEYS: Array[int] = [KEY_ESCAPE, KEY_BACKSPACE]

var state: State = State.IDLE
## &"key" or &"pad": what this capture accepts.
var device: StringName = &"key"
var action_label: String = ""
## Seconds LISTENING waits (0 = no limit).
var timeout_sec: float = 10.0
var arm_sec: float = 0.15
var trigger_threshold: float = 0.6
## Process frame the capture ended on (the menu skips its cancel check then).
var end_frame: int = -1
var message: String = ""

var _arm_left: float = 0.0
var _time_left: float = 0.0
## Test seam: replaces Input.is_anything_pressed() (headless tests have no devices).
var held_probe: Callable = Callable()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Starts a capture; the timing comes from AccessibilityConfig and
## Settings.rebind_wait unless a caller overrides the vars afterwards.
func start(label: String, slot_device: StringName) -> void:
	var cfg := Settings.config()
	if cfg != null:
		timeout_sec = cfg.rebind_timeout(Settings.rebind_wait)
		arm_sec = cfg.rebind_arm_sec
		trigger_threshold = cfg.rebind_trigger_threshold
	action_label = label
	device = slot_device
	state = State.ARMING
	_arm_left = arm_sec
	_time_left = timeout_sec
	end_frame = -1
	_set_message("")


func is_active() -> bool:
	return state == State.ARMING or state == State.LISTENING


## Cancels from outside (the menu closing, a device change).
func cancel(reason: StringName = &"cancelled") -> void:
	if not is_active():
		return
	_finish()
	cancelled.emit(reason)


## The line the page shows while capturing.
func prompt_text() -> String:
	var args := {"action": Loc.upper(action_label)}
	var line := Loc.f("Press a key for {action} (Esc to cancel)", args) if device == &"key" \
		else Loc.f("Press a button for {action} (Start to cancel)", args)
	if state == State.LISTENING and timeout_sec > 0.0:
		line += " · %d" % ceili(maxf(_time_left, 0.0))
	return line


func _process(delta: float) -> void:
	match state:
		State.ARMING:
			_arm_left -= delta
			if _arm_left <= 0.0 and not _anything_held():
				state = State.LISTENING
				_time_left = timeout_sec
				_set_message(prompt_text())
		State.LISTENING:
			if timeout_sec > 0.0:
				var before := ceili(maxf(_time_left, 0.0))
				_time_left -= delta
				if _time_left <= 0.0:
					cancel(&"timeout")
				elif ceili(_time_left) != before:
					_set_message(prompt_text())


func _input(event: InputEvent) -> void:
	if not is_active():
		return
	if event is InputEventMouse:
		return
	_handled()
	if state != State.LISTENING:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		if CANCEL_KEYS.has(int(k.physical_keycode)):
			cancel(&"cancelled")
			return
		if device != &"key":
			_set_message(Loc.t("Waiting for a controller button."))
			return
		var ev := InputEventKey.new()
		ev.physical_keycode = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		_capture(ev)
	elif event is InputEventJoypadButton:
		var b := event as InputEventJoypadButton
		if not b.pressed:
			return
		if b.button_index == JOY_BUTTON_START:
			cancel(&"cancelled")
			return
		if device != &"pad":
			_set_message(Loc.t("Waiting for a key."))
			return
		var ev := InputEventJoypadButton.new()
		ev.button_index = b.button_index
		_capture(ev)
	elif event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		# Only the triggers bind; a stick never does (drift, D4 §4.5).
		if m.axis < JOY_AXIS_TRIGGER_LEFT or m.axis_value < trigger_threshold or device != &"pad":
			return
		var ev := InputEventJoypadMotion.new()
		ev.axis = m.axis
		ev.axis_value = 1.0
		_capture(ev)


func _capture(ev: InputEvent) -> void:
	_finish()
	captured.emit(ev)


func _finish() -> void:
	state = State.DONE
	end_frame = Engine.get_process_frames()
	_set_message("")


func _anything_held() -> bool:
	if held_probe.is_valid():
		return bool(held_probe.call())
	return Input.is_anything_pressed()


func _handled() -> void:
	if is_inside_tree() and get_viewport() != null:
		get_viewport().set_input_as_handled()


func _set_message(text: String) -> void:
	message = text
	message_changed.emit(text)
