extends Node
## Controller rumble (bible §24 vibration slider, D4 §6, D-157). Main adds it
## as an optional system. Like Playtest it only listens to typed EventBus
## signals, one per HapticEvent row in AccessibilityConfig.haptics, so the
## event list and strengths are data (provisional until §44 and the M10
## controller pass; if the owner declines rumble on by default the fix is
## data only: every row's strength to 0, the slider stays).
##
## Rules: strengths scale by Settings.vibration_strength (0 = silent); only a
## player on a pad feels anything (keyboard players never do); nothing pulses
## while the tree is paused (menus, dialogue); challenge_finished pulses only
## on a new personal best.

## Test seam: when valid, called as sink.call(device, weak, strong, seconds)
## instead of Input.start_joy_vibration.
var sink: Callable = Callable()
## The last pulse sent (tests, the dev overlay): {event, device, weak, strong, seconds}.
var last_pulse: Dictionary = {}


func _ready() -> void:
	# Pausing would stop a menu from getting its own feedback; pulses check
	# the paused flag themselves instead.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := _config()
	if cfg == null:
		return
	for h in cfg.haptics:
		if h == null or not EventBus.has_signal(h.event):
			continue
		if h.event == &"challenge_finished":
			EventBus.challenge_finished.connect(_on_challenge_finished)
			continue
		var argc := _signal_argc(h.event)
		var cb := pulse.bind(h.event)
		EventBus.connect(h.event, cb.unbind(argc) if argc > 0 else cb)


## Sends the row for `event` scaled by the vibration setting. Returns whether
## anything was sent (tests).
func pulse(event: StringName) -> bool:
	var cfg := _config()
	var row := cfg.haptic(event) if cfg else null
	if row == null:
		return false
	var s := float(Settings.vibration_strength)
	if s <= 0.0:
		return false
	if not InputGlyphs.using_pad:
		return false
	if is_inside_tree() and get_tree().paused:
		return false
	var device := int(InputGlyphs.last_pad_device)
	var weak := clampf(row.weak * s, 0.0, 1.0)
	var strong := clampf(row.strong * s, 0.0, 1.0)
	if sink.is_valid():
		sink.call(device, weak, strong, row.seconds)
	else:
		if not Input.get_connected_joypads().has(device):
			return false
		Input.start_joy_vibration(device, weak, strong, row.seconds)
	last_pulse = {"event": event, "device": device, "weak": weak, "strong": strong, "seconds": row.seconds}
	return true


func _on_challenge_finished(_id: String, _outcome: int, _value: int, _medal: int, new_best: bool) -> void:
	if new_best:
		pulse(&"challenge_finished")


func _config() -> AccessibilityConfig:
	return Settings.config()


func _signal_argc(sig: StringName) -> int:
	for s in EventBus.get_signal_list():
		if StringName(s["name"]) == sig:
			return (s["args"] as Array).size()
	return 0
