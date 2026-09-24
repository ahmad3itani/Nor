class_name CameraConfig
extends Resource
## Camera framing and feel (bible §26). Never create constant nausea:
## defaults favour stability; shake/impulses are short and scaled by Settings.

@export_group("Follow")
## Target can move inside this box (px, centred) without moving the camera.
@export var dead_zone: Vector2 = Vector2(20, 36)
## Exponential follow rates (1/s). Higher = tighter.
@export var follow_rate_x: float = 9.0
@export var follow_rate_y: float = 6.0
## Vertical framing offset: keep the player a little below centre to show more above.
@export var vertical_offset: float = -18.0

@export_group("Look-ahead")
## Max look-ahead in the direction of travel (px).
@export var look_ahead_distance: float = 56.0
## Speed at which the full look-ahead is reached (speed-sensitive framing).
@export var look_ahead_full_speed: float = 220.0
## How quickly look-ahead shifts (1/s). Low so turning doesn't whip the camera.
@export var look_ahead_rate: float = 2.5
## When falling faster than this, start looking down.
@export var fall_look_threshold: float = 260.0
@export var fall_look_distance: float = 48.0

@export_group("Impulse & Shake")
## Spring that returns impulse offsets to rest.
@export var impulse_stiffness: float = 220.0
@export var impulse_damping: float = 18.0
## Max positional shake (px) at trauma = 1.
@export var shake_max_offset: Vector2 = Vector2(6, 5)
@export var shake_decay: float = 1.8
@export var shake_frequency: float = 22.0
## Landing impulse (px) per unit of fall speed above the hard-landing threshold.
@export var landing_impulse_scale: float = 0.025
## Tiny shake on hard landings only; normal landings use the impulse alone.
@export var hard_landing_trauma: float = 0.12
