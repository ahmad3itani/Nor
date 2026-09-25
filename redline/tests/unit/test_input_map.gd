extends RedlineTestCase
## Keyboard/controller parity (bible §24, §37.8): every gameplay action must be
## reachable from both. Debug-only actions are exempt.

const REQUIRED := [
	"move_left", "move_right", "move_up", "move_down", "jump", "dodge",
	"attack_light", "attack_heavy", "ranged", "grapple", "heal", "interact",
	"pause", "reset", "debug_toggle", "debug_next_spawn", "cinematic_skip",
]


func test_required_actions_exist() -> void:
	for action in REQUIRED:
		check(InputMap.has_action(action), "missing action %s" % action)


func test_gameplay_actions_have_keyboard_and_controller() -> void:
	for action in InputMap.get_actions():
		var a := String(action)
		if a.begins_with("ui_") or (a.begins_with("debug_") and not a in REQUIRED):
			continue
		var has_key := false
		var has_pad := false
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				has_key = true
			elif ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				has_pad = true
		check(has_key, "%s has no keyboard binding" % a)
		check(has_pad, "%s has no controller binding" % a)
	# M8: cinematic_skip = every jump key plus Enter, and pad A. Physical
	# keycodes only, or InputGlyphs.label prints "Hold [] to skip".
	var skip_keys: Array[int] = []
	var skip_pad_a := false
	for ev in InputMap.action_get_events(&"cinematic_skip"):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			check(k.physical_keycode != 0, "cinematic_skip key event without physical_keycode")
			skip_keys.append(k.physical_keycode)
		elif ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == JOY_BUTTON_A:
			skip_pad_a = true
	check(skip_pad_a, "cinematic_skip has no pad A")
	for ev in InputMap.action_get_events(&"jump"):
		if ev is InputEventKey:
			var pk := (ev as InputEventKey).physical_keycode
			check(pk in skip_keys, "jump key %s is not a cinematic_skip key" % OS.get_keycode_string(pk))
	check(KEY_ENTER in skip_keys, "Enter is not a cinematic_skip key")


## M8 (T01): the built-in menu actions have no pad events in 4.3, so the
## project overrides them; every MenuScreen button and Cancel works on a pad.
func test_ui_accept_cancel_have_pad() -> void:
	var accept_keys: Array[int] = []
	var accept_pad := false
	for ev in InputMap.action_get_events(&"ui_accept"):
		if ev is InputEventKey:
			accept_keys.append((ev as InputEventKey).physical_keycode)
		elif ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == JOY_BUTTON_A:
			accept_pad = true
	check(KEY_SPACE in accept_keys and KEY_ENTER in accept_keys, "ui_accept lacks physical Space/Enter (got %s)" % str(accept_keys))
	check(accept_pad, "ui_accept has no pad A")
	var cancel_esc := false
	var cancel_pad := false
	for ev in InputMap.action_get_events(&"ui_cancel"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_ESCAPE:
			cancel_esc = true
		elif ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == JOY_BUTTON_B:
			cancel_pad = true
	check(cancel_esc, "ui_cancel lacks physical Escape")
	check(cancel_pad, "ui_cancel has no pad B")
	var was_pad := InputGlyphs.using_pad
	InputGlyphs.using_pad = false
	var key_label := InputGlyphs.label(&"ui_accept")
	check(key_label == "Enter" or key_label == "Space", "keyboard ui_accept label is '%s'" % key_label)
	InputGlyphs.using_pad = true
	check(InputGlyphs.label(&"ui_accept") == "A", "pad ui_accept label is '%s'" % InputGlyphs.label(&"ui_accept"))
	InputGlyphs.using_pad = was_pad
