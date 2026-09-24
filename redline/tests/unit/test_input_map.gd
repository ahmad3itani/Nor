extends RedlineTestCase
## Keyboard/controller parity (bible §24, §37.8): every gameplay action must be
## reachable from both. Debug-only actions are exempt.

const REQUIRED := [
	"move_left", "move_right", "move_up", "move_down", "jump", "dodge",
	"attack_light", "attack_heavy", "ranged", "grapple", "heal", "interact",
	"pause", "reset", "debug_toggle", "debug_next_spawn",
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
