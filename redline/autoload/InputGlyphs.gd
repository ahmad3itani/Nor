extends Node
## Tracks whether the player last used keyboard or controller and names the
## binding for an action accordingly (bible §24 controller glyph switching;
## text labels until glyph art exists).

signal device_changed(using_pad: bool)

const PAD_BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "View", JOY_BUTTON_START: "Menu", JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-Pad Up", JOY_BUTTON_DPAD_DOWN: "D-Pad Down",
	JOY_BUTTON_DPAD_LEFT: "D-Pad Left", JOY_BUTTON_DPAD_RIGHT: "D-Pad Right",
}
const PAD_AXIS_NAMES := {JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT"}

var using_pad: bool = false


func _input(event: InputEvent) -> void:
	var pad := event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5)
	var keys := event is InputEventKey or event is InputEventMouseButton
	if (pad and not using_pad) or (keys and using_pad):
		using_pad = pad
		device_changed.emit(using_pad)


## Short label for the first binding of `action` on the active device.
func label(action: StringName) -> String:
	for ev in InputMap.action_get_events(action):
		if using_pad:
			if ev is InputEventJoypadButton:
				return PAD_BUTTON_NAMES.get((ev as InputEventJoypadButton).button_index, "Pad")
			if ev is InputEventJoypadMotion and PAD_AXIS_NAMES.has((ev as InputEventJoypadMotion).axis):
				return PAD_AXIS_NAMES[(ev as InputEventJoypadMotion).axis]
		elif ev is InputEventKey:
			return OS.get_keycode_string((ev as InputEventKey).physical_keycode)
	return String(action)
