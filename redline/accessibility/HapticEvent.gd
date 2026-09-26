class_name HapticEvent
extends Resource
## One vibration pulse (bible §24 vibration slider, D4 §6): which EventBus
## signal fires it and how hard. Haptics (T12) scales weak/strong by
## Settings.vibration_strength, so 0 there silences every row here.

## EventBus signal name (player_damaged, perfect_dodge, ...).
@export var event: StringName = &""
## Weak (high-frequency) motor, 0..1.
@export_range(0.0, 1.0) var weak: float = 0.0
## Strong (low-frequency) motor, 0..1.
@export_range(0.0, 1.0) var strong: float = 0.0
@export var seconds: float = 0.1


func validate() -> PackedStringArray:
	var out := PackedStringArray()
	if event == &"":
		out.append("haptic event without a signal name")
	if weak < 0.0 or weak > 1.0 or strong < 0.0 or strong > 1.0:
		out.append("haptic %s: motor strength outside 0..1" % event)
	if weak <= 0.0 and strong <= 0.0:
		out.append("haptic %s never vibrates" % event)
	if seconds <= 0.0 or seconds > 2.0:
		out.append("haptic %s: %.2f s is outside (0, 2]" % [event, seconds])
	return out
