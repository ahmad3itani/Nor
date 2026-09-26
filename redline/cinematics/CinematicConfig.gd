class_name CinematicConfig
extends Resource
## Timing players feel in scripted sequences and dialogue (bible §37.3:
## tuning lives in data; data/cinematics/cinematic_config.tres, read through
## CinematicMode.config()). The memory side keeps its own values in
## MemoryConfig. D-108 documents the defaults.

const PATH := "res://data/cinematics/cinematic_config.tres"

@export_group("Skip gate")
## A press released within this is a TAP (advances text), never a skip.
@export var tap_seconds: float = 0.25
## Hold of cinematic_skip that skips a first view / a repeat view.
@export var hold_seconds: float = 0.8
@export var repeat_hold_seconds: float = 0.4
## "Press twice": the window that arms arm_delay_seconds after a TAP.
@export var double_tap_seconds: float = 0.6
@export var arm_delay_seconds: float = 0.15
## Presses that start this soon after the gate opens (or after a pause) wait
## for a full release.
@export var grace_seconds: float = 0.25
## How long a press keeps the skip prompt up on a first view.
@export var prompt_show_seconds: float = 2.0

@export_group("Sequences")
@export var letterbox_seconds: float = 0.35
## First views: an early advance needs the full line up this share of its hold.
@export var early_fraction: float = 0.5
## Scene lines type out at this rate.
@export var type_cps: float = 70.0
## A line's auto time: clamp(base + per_char * length, min, max) seconds at
## subtitle speed Normal (the budget linter uses the same formula).
@export var line_base_seconds: float = 1.0
@export var line_seconds_per_char: float = 0.065
@export var line_min_seconds: float = 2.0
@export var line_max_seconds: float = 7.0
## A SequenceTrigger held back by danger or another play retries this often.
@export var trigger_retry_seconds: float = 0.5

@export_group("Dialogue")
## Choices ignore input for this long (real time) after they appear.
@export var choice_arm_seconds: float = 0.4


func line_seconds(length: int) -> float:
	return clampf(line_base_seconds + line_seconds_per_char * length, line_min_seconds, line_max_seconds)


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for f in ["tap_seconds", "hold_seconds", "repeat_hold_seconds", "double_tap_seconds", "grace_seconds",
			"prompt_show_seconds", "type_cps", "line_min_seconds", "trigger_retry_seconds"]:
		if float(get(f)) <= 0.0:
			errors.append("cinematic config: %s must be > 0" % f)
	for f in ["arm_delay_seconds", "letterbox_seconds", "line_base_seconds", "line_seconds_per_char", "choice_arm_seconds"]:
		if float(get(f)) < 0.0:
			errors.append("cinematic config: %s must be >= 0" % f)
	if line_max_seconds < line_min_seconds:
		errors.append("cinematic config: line_max_seconds < line_min_seconds")
	if early_fraction < 0.0 or early_fraction > 1.0:
		errors.append("cinematic config: early_fraction must be 0..1")
	# A hold must outlast a tap, or every press would skip.
	if repeat_hold_seconds <= tap_seconds or hold_seconds <= tap_seconds:
		errors.append("cinematic config: hold times must exceed tap_seconds")
	return errors
