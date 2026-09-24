class_name MovementMetrics
extends RefCounted
## Live measurements for the M1 metrics overlay: lets testers verify that the
## numbers in PlayerMovementConfig produce the jump arcs they expect.

var last_jump_height: float = 0.0
var last_jump_distance: float = 0.0
var last_airtime: float = 0.0
var top_speed: float = 0.0
var jumps: int = 0
var slides: int = 0
var dodges: int = 0
var dashes: int = 0

var _air_start_pos: Vector2
var _last_ground_pos: Vector2
var _air_min_y: float
var _air_time: float = 0.0
var _airborne: bool = false


func track(body_pos: Vector2, velocity: Vector2, on_floor: bool, delta: float) -> void:
	top_speed = maxf(top_speed, absf(velocity.x))
	if not on_floor:
		if not _airborne:
			# Measure from the last grounded position, not the first airborne
			# tick, or every jump under-reports by one frame of rise.
			_airborne = true
			_air_start_pos = _last_ground_pos
			_air_min_y = minf(body_pos.y, _last_ground_pos.y)
			_air_time = 0.0
		_air_time += delta
		_air_min_y = minf(_air_min_y, body_pos.y)
	else:
		_last_ground_pos = body_pos
	if on_floor and _airborne:
		_airborne = false
		last_airtime = _air_time
		last_jump_height = _air_start_pos.y - _air_min_y
		last_jump_distance = absf(body_pos.x - _air_start_pos.x)


## Teleports must not count as a jump from the previous ground position.
func on_respawn(at: Vector2) -> void:
	_airborne = false
	_last_ground_pos = at


func reset_session() -> void:
	top_speed = 0.0
	jumps = 0
	slides = 0
	dodges = 0
	dashes = 0
