extends RedlineTestCase
## M9 T12 (bible §24 vibration slider, D4 §6, D-157): Haptics pulses the
## HapticEvent rows, scaled by Settings.vibration_strength, only for pad
## players and never while paused. The sink seam replaces the Input call.

const HAPTICS_PATH := "res://accessibility/Haptics.gd"

var _snap: Dictionary = {}
var _was_pad: bool = false
var _was_device: int = 0
var _haptics: Node
## [device, weak, strong, seconds] per pulse the sink received.
var _calls: Array = []


func before_each() -> void:
	_snap = snapshot_settings()
	_was_pad = InputGlyphs.using_pad
	_was_device = InputGlyphs.last_pad_device
	_calls = []
	_haptics = (load(HAPTICS_PATH) as GDScript).new()
	add_child(_haptics)
	var calls := _calls
	_haptics.set("sink", func(device: int, weak: float, strong: float, seconds: float) -> void:
		calls.append([device, weak, strong, seconds]))


func after_each() -> void:
	get_tree().paused = false
	InputGlyphs.using_pad = _was_pad
	InputGlyphs.last_pad_device = _was_device
	restore_settings(_snap)
	if is_instance_valid(_haptics):
		_haptics.free()


func test_scaled_by_strength() -> void:
	InputGlyphs.using_pad = true
	InputGlyphs.last_pad_device = 2
	Settings.vibration_strength = 0.5
	var row := Settings.config().haptic(&"player_damaged")
	check(row != null, "player_damaged has a row")
	check(bool(_haptics.call("pulse", &"player_damaged")), "a pad player feels the hit")
	check(_calls.size() == 1, "one pulse sent")
	if _calls.size() == 1:
		var c: Array = _calls[0]
		check(int(c[0]) == 2, "sent to the last pad used")
		check_near(float(c[1]), row.weak * 0.5, 0.0001, "weak motor scaled by the slider")
		check_near(float(c[2]), row.strong * 0.5, 0.0001, "strong motor scaled by the slider")
		check_near(float(c[3]), row.seconds, 0.0001, "duration from the row")
	Settings.vibration_strength = 1.0
	_haptics.call("pulse", &"player_damaged")
	check(_calls.size() == 2 and is_equal_approx(float(_calls[1][2]), row.strong), "full strength sends the row as authored")
	check(not bool(_haptics.call("pulse", &"not_a_row")), "an event without a row sends nothing")
	# The rumble default stays on for pad players (D-157 flag, R12.3).
	check(is_equal_approx(Settings.defaults()["vibration_strength"], 1.0), "vibration_strength default stays 1.0")


func test_zero_strength_silent() -> void:
	InputGlyphs.using_pad = true
	Settings.vibration_strength = 0.0
	for h in Settings.config().haptics:
		check(not bool(_haptics.call("pulse", h.event)), "%s silent at 0" % h.event)
	check(_calls.is_empty(), "nothing reached the motors")


func test_keyboard_user_silent() -> void:
	InputGlyphs.using_pad = false
	Settings.vibration_strength = 1.0
	for h in Settings.config().haptics:
		check(not bool(_haptics.call("pulse", h.event)), "%s silent for a keyboard player" % h.event)
	_haptics.call("_on_challenge_finished", "tt_test", 0, 100, 2, true)
	check(_calls.is_empty(), "keyboard-only players never get rumble")


func test_paused_silent() -> void:
	InputGlyphs.using_pad = true
	Settings.vibration_strength = 1.0
	get_tree().paused = true
	check(not bool(_haptics.call("pulse", &"player_died")), "paused: no pulse")
	get_tree().paused = false
	check(bool(_haptics.call("pulse", &"player_died")), "unpaused: the pulse comes back")
	check(_calls.size() == 1, "one pulse after unpausing")


func test_table_events_are_eventbus_signals() -> void:
	var cfg := Settings.config()
	check(cfg.haptics.size() >= 6, "the D4 table plus challenge_finished")
	for h in cfg.haptics:
		check(EventBus.has_signal(h.event), "%s is an EventBus signal" % h.event)
	check(AccessRules.haptic_errors(cfg).is_empty(), "AC-4 clean")
	check(cfg.haptic(&"challenge_finished") != null, "challenge_finished row present")
	# Every row is wired to its signal.
	for h in cfg.haptics:
		var wired := false
		for c: Dictionary in EventBus.get_signal_connection_list(h.event):
			if (c["callable"] as Callable).get_object() == _haptics:
				wired = true
		check(wired, "%s is connected to Haptics" % h.event)
	# challenge_finished pulses only on a new best.
	InputGlyphs.using_pad = true
	Settings.vibration_strength = 1.0
	_haptics.call("_on_challenge_finished", "tt_test", 0, 100, 2, false)
	check(_calls.is_empty(), "no pulse without a new best")
	_haptics.call("_on_challenge_finished", "tt_test", 0, 100, 2, true)
	check(_calls.size() == 1, "a new best pulses")
