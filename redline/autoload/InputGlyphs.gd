extends Node
## Tracks whether the player last used keyboard or controller and names the
## binding for an action accordingly (bible §24 controller glyph switching;
## text labels until glyph art exists).
##
## M9 (D4 §5): pad names come from a GlyphSet family (Xbox, PlayStation,
## Nintendo) chosen by Settings.pad_glyphs or detected from the last pad's
## name, and keyboard names follow the player's layout (an AZERTY player sees
## "A" for the key a QWERTY board calls Q). Prompts read label() every time
## they draw, so a rebind shows everywhere with no extra wiring.

signal device_changed(using_pad: bool)

const GLYPH_PATH := "res://data/input/glyphs/%s.tres"
## Settings.pad_glyphs 1..3 in order (0 = Auto).
const FAMILIES: Array[StringName] = [&"xbox", &"playstation", &"nintendo"]

var using_pad: bool = false
## Device id of the last pad event (Auto family detection, Haptics).
var last_pad_device: int = 0

## family id -> GlyphSet.
var _sets: Dictionary = {}


func _input(event: InputEvent) -> void:
	var pad := event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5)
	var keys := event is InputEventKey or event is InputEventMouseButton
	if pad:
		last_pad_device = event.device
	if (pad and not using_pad) or (keys and using_pad):
		using_pad = pad
		device_changed.emit(using_pad)


## The family in use: forced by Settings.pad_glyphs, else detected from the
## last pad's name (Steam Deck and unknown pads read as Xbox).
func family() -> GlyphSet:
	return glyph_set(family_id())


func family_id() -> StringName:
	var forced := int(Settings.pad_glyphs)
	if forced >= 1 and forced <= FAMILIES.size():
		return FAMILIES[forced - 1]
	return family_for_name(Input.get_joy_name(last_pad_device))


## Pure detection from a joypad name (tests).
static func family_for_name(joy_name: String) -> StringName:
	var n := joy_name.to_lower()
	for w in ["dualsense", "dualshock", "playstation", "sony", "ps3", "ps4", "ps5"]:
		if n.contains(w):
			return &"playstation"
	for w in ["nintendo", "switch", "joy-con", "pro controller"]:
		if n.contains(w):
			return &"nintendo"
	return &"xbox"


func glyph_set(id: StringName) -> GlyphSet:
	if not _sets.has(id):
		var path := GLYPH_PATH % id
		_sets[id] = load(path) as GlyphSet if ResourceLoader.exists(path) else null
	return _sets[id] as GlyphSet


## Short label for the first binding of `action` on the active device (the
## signature every prompt uses since M1). Stick directions are skipped, so
## move_* name their D-pad button.
func label(action: StringName) -> String:
	for ev in InputMap.action_get_events(action):
		if using_pad:
			if ev is InputEventJoypadButton:
				return pad_label(ev)
			if ev is InputEventJoypadMotion and (ev as InputEventJoypadMotion).axis >= JOY_AXIS_TRIGGER_LEFT:
				return pad_label(ev)
		elif ev is InputEventKey:
			return key_label((ev as InputEventKey).physical_keycode)
	return String(action)


## Every binding of `action` on `device` (&"key" / &"pad"; default the active
## one), joined with " · " (the Controls page). Sticks are listed on pads.
func labels(action: StringName, device: StringName = &"", max_count: int = 3) -> String:
	var dev := device if device != &"" else (&"pad" if using_pad else &"key")
	var out := PackedStringArray()
	for ev in InputMap.action_get_events(action):
		var is_key := ev is InputEventKey
		var is_pad := ev is InputEventJoypadButton or ev is InputEventJoypadMotion
		if (dev == &"key" and not is_key) or (dev == &"pad" and not is_pad):
			continue
		var l := event_label(ev)
		if l != "" and not out.has(l):
			out.append(l)
		if out.size() >= max_count:
			break
	return " · ".join(out)


## One event's label on the active family (keys follow the layout).
func event_label(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		return key_label(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)
	return pad_label(ev)


func pad_label(ev: InputEvent) -> String:
	var gs := family()
	if ev is InputEventJoypadButton:
		var i := (ev as InputEventJoypadButton).button_index
		var n := gs.button_name(i) if gs else ""
		return n if n != "" else "Pad %d" % i
	if ev is InputEventJoypadMotion:
		var m := ev as InputEventJoypadMotion
		var n := gs.axis_name(m.axis, m.axis_value >= 0.0) if gs else ""
		return n if n != "" else "Pad"
	return ""


## The printed name of a physical key on the player's layout. Headless runs
## (and servers without layout support) fall back to the QWERTY name.
func key_label(physical: Key) -> String:
	var shown := physical
	if DisplayServer.get_name() != "headless":
		var l := DisplayServer.keyboard_get_label_from_physical(physical)
		if l != KEY_NONE:
			shown = l
	return OS.get_keycode_string(shown)
