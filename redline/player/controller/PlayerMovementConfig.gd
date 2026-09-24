class_name PlayerMovementConfig
extends Resource
## Every movement tuning value lives here (bible §5, §38.9).
## Controller/state code must read from this resource and never hardcode feel.
##
## Units: pixels and seconds at the 480x270 reference canvas. Rook is ~36 px tall.
## Jump is authored as height + time-to-apex; gravity and launch speed are derived
## so designers tune what the player perceives rather than raw physics numbers.

@export var preset_name: String = "default"

@export_group("Run")
@export var max_run_speed: float = 150.0
## Ground acceleration toward max speed when input matches velocity direction.
@export var ground_accel: float = 1500.0
## Ground deceleration with no input.
@export var ground_decel: float = 2000.0
## Used when input opposes current velocity: high value = snappy turnarounds.
@export var ground_turn_accel: float = 3000.0
## When faster than max_run_speed (slide/dash exit) and still holding forward,
## bleed speed this slowly to preserve momentum instead of snapping to run speed.
@export var ground_overspeed_decel: float = 450.0
@export var crouch_move_speed: float = 55.0
## Analog stick magnitude below which horizontal input is ignored.
@export_range(0.0, 0.9) var stick_deadzone: float = 0.25
## Stick Y needed to count as "down" (crouch/slide). Higher than deadzone so
## diagonal running on a stick does not trigger accidental crouches.
@export_range(0.1, 1.0) var down_threshold: float = 0.6

@export_group("Air")
@export var air_accel: float = 1100.0
@export var air_decel: float = 600.0
@export var air_turn_accel: float = 1800.0
@export var air_overspeed_decel: float = 150.0

@export_group("Jump")
@export var jump_height: float = 56.0
@export var jump_time_to_apex: float = 0.34
## Multiplies vertical speed once when jump is released while rising (variable jump).
@export_range(0.0, 1.0) var jump_cut_multiplier: float = 0.45
## Gravity multiplier while falling: heavier fall reads as "snappy", not floaty.
@export var fall_gravity_multiplier: float = 1.7
## Near the apex (|vy| below threshold) with jump held, gravity is reduced for hang time.
@export var apex_speed_threshold: float = 40.0
@export var apex_gravity_multiplier: float = 0.55
## Extra air acceleration granted at the apex so small corrections feel precise.
@export var apex_air_accel_bonus: float = 1.25
@export var max_fall_speed: float = 400.0
## Holding down while falling raises the fall cap and gravity (fast-fall).
@export var fast_fall_speed: float = 520.0
@export var fast_fall_gravity_multiplier: float = 2.2

@export_group("Forgiveness")
@export var coyote_time: float = 0.10
@export var jump_buffer_time: float = 0.12
## Max horizontal nudge (px) to slip past a ceiling corner when jumping.
@export_range(0, 12) var corner_correction_px: int = 6
## Max vertical step-up (px) when grazing a ledge corner while airborne.
@export_range(0, 12) var ledge_forgiveness_px: int = 5
## Buffer for dodge/dash presses made slightly before they are allowed.
@export var action_buffer_time: float = 0.10

@export_group("Landing")
## Fall speed above which a landing counts as "hard" (camera impulse, bigger squash).
@export var hard_land_speed: float = 340.0

@export_group("Slide")
## Minimum horizontal speed to start a slide; slower down-presses crouch instead.
@export var slide_min_entry_speed: float = 90.0
@export var slide_entry_boost: float = 70.0
@export var slide_max_speed: float = 260.0
@export var slide_friction: float = 240.0
@export var slide_min_duration: float = 0.18
@export var slide_max_duration: float = 0.65
## Slide ends (stands or crouches) once horizontal speed falls below this.
@export var slide_exit_speed: float = 60.0
@export var slide_cooldown: float = 0.12
## Horizontal speed added when jumping out of a slide (slide-jump tech).
@export var slide_jump_bonus: float = 30.0
## Slide-jump height as a fraction of a normal jump: long and low.
@export_range(0.3, 1.0) var slide_jump_height_ratio: float = 0.8

@export_group("Dodge")
@export var dodge_speed: float = 270.0
@export var dodge_duration: float = 0.22
## Invulnerability window inside the dodge (seconds from start). Consumed by M2 combat.
@export var dodge_iframe_start: float = 0.02
@export var dodge_iframe_end: float = 0.18
@export var dodge_cooldown: float = 0.30
## Speed kept on exit, as a fraction of max_run_speed (momentum preservation).
@export_range(0.0, 1.5) var dodge_exit_speed_ratio: float = 1.0
## After this much of the dodge has elapsed, jump may cancel it.
@export var dodge_jump_cancel_time: float = 0.08
## Air dodges allowed per airtime (restored on landing).
@export_range(0, 3) var air_dodges: int = 1

@export_group("Dash (unlock)")
@export var dash_speed: float = 400.0
@export var dash_duration: float = 0.16
@export var dash_cooldown: float = 0.25
## Exit speed after a dash; above run speed on purpose so overspeed decel carries it.
@export var dash_exit_speed: float = 230.0
@export var dash_jump_cancel_time: float = 0.05
## I-frames at the very start of a dash so the unlock never feels worse than Dodge.
@export var dash_iframe_end: float = 0.08

@export_group("Collision")
@export var standing_size: Vector2 = Vector2(12, 34)
@export var low_size: Vector2 = Vector2(12, 16)


## Initial upward speed (negative = up in Godot 2D).
func jump_velocity() -> float:
	return -2.0 * jump_height / jump_time_to_apex


## Rising gravity derived from jump height and time-to-apex.
func rise_gravity() -> float:
	return 2.0 * jump_height / (jump_time_to_apex * jump_time_to_apex)


func fall_gravity() -> float:
	return rise_gravity() * fall_gravity_multiplier


## Returns human-readable problems; empty means the config is usable.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var positives := {
		"max_run_speed": max_run_speed, "ground_accel": ground_accel, "ground_decel": ground_decel,
		"ground_turn_accel": ground_turn_accel, "air_accel": air_accel, "jump_height": jump_height,
		"jump_time_to_apex": jump_time_to_apex, "max_fall_speed": max_fall_speed,
		"dodge_speed": dodge_speed, "dodge_duration": dodge_duration, "dash_speed": dash_speed,
		"dash_duration": dash_duration, "slide_max_duration": slide_max_duration,
	}
	for key: String in positives:
		if float(positives[key]) <= 0.0:
			errors.append("%s must be > 0" % key)
	if coyote_time < 0.0 or coyote_time > 0.25:
		errors.append("coyote_time should be within 0..0.25s (feels like cheating beyond)")
	if jump_buffer_time < 0.0 or jump_buffer_time > 0.25:
		errors.append("jump_buffer_time should be within 0..0.25s")
	if fast_fall_speed < max_fall_speed:
		errors.append("fast_fall_speed must be >= max_fall_speed")
	if slide_min_duration > slide_max_duration:
		errors.append("slide_min_duration must be <= slide_max_duration")
	if slide_exit_speed >= slide_min_entry_speed:
		errors.append("slide_exit_speed must be < slide_min_entry_speed or slides end instantly")
	if dodge_iframe_end > dodge_duration or dodge_iframe_start > dodge_iframe_end:
		errors.append("dodge i-frame window must sit inside dodge_duration")
	if low_size.y >= standing_size.y:
		errors.append("low_size.y must be smaller than standing_size.y")
	if dash_speed <= max_run_speed:
		errors.append("dash_speed should exceed max_run_speed")
	return errors
