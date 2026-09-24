class_name PlayerCamera
extends Camera2D
## Follow camera for fast platforming (bible §26).
##
## - A focus point is pushed by the player only when they leave the dead zone,
##   so small moves don't drag the view ("camera does not fight the player").
## - Vertical: while grounded the focus settles on the floor height; in the air
##   only the dead zone moves it, so ordinary jumps don't bob the screen.
## - Look-ahead scales with horizontal speed and holds when stopping, so the
##   view doesn't swing back each time the player lets go of the stick.
## - Impulses (landing, hits) run through a damped spring; shake is trauma^2
##   noise, scaled by Settings.screen_shake_scale (0 = off).

@export var config: CameraConfig

var target: Player
var bounds: Rect2 = Rect2()

var _focus: Vector2
var _look_ahead: Vector2
var _impulse: Vector2
var _impulse_vel: Vector2
var _trauma: float = 0.0
var _noise := FastNoiseLite.new()
var _time: float = 0.0


func _ready() -> void:
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	position_smoothing_enabled = false
	_noise.frequency = 1.0
	_noise.seed = 1337
	EventBus.camera_shake_requested.connect(add_trauma)
	EventBus.camera_impulse_requested.connect(add_impulse)
	EventBus.player_landed.connect(_on_player_landed)


func set_bounds(rect: Rect2) -> void:
	bounds = rect
	limit_left = int(rect.position.x)
	limit_top = int(rect.position.y)
	limit_right = int(rect.end.x)
	limit_bottom = int(rect.end.y)


func follow(new_target: Player) -> void:
	target = new_target
	snap_to_target()


## Hard cut, used on spawn/respawn/teleport so the view never travels across the map.
func snap_to_target() -> void:
	if target == null:
		return
	_focus = _target_point()
	_look_ahead = Vector2(target.facing * config.look_ahead_distance * 0.5, 0.0)
	_impulse = Vector2.ZERO
	_impulse_vel = Vector2.ZERO
	global_position = _clamp_to_bounds(_focus + _look_ahead)
	reset_smoothing()


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func add_impulse(offset_px: Vector2) -> void:
	# Instant displacement, then the spring eases the view back: reads as a kick.
	_impulse += offset_px


func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	_time += delta
	_update_focus(delta)
	_update_look_ahead(delta)

	var desired := _clamp_to_bounds(_focus + _look_ahead)
	global_position.x = lerpf(global_position.x, desired.x, 1.0 - exp(-config.follow_rate_x * delta))
	global_position.y = lerpf(global_position.y, desired.y, 1.0 - exp(-config.follow_rate_y * delta))

	# Damped spring returns impulses to rest.
	_impulse_vel += (-config.impulse_stiffness * _impulse - config.impulse_damping * _impulse_vel) * delta
	_impulse += _impulse_vel * delta

	_trauma = maxf(_trauma - config.shake_decay * delta, 0.0)
	var shake := Vector2.ZERO
	var amount := _trauma * _trauma * Settings.screen_shake_scale
	if amount > 0.0:
		var t := _time * config.shake_frequency
		shake = Vector2(_noise.get_noise_2d(t, 0.0), _noise.get_noise_2d(0.0, t)) * config.shake_max_offset * amount
	offset = _impulse + shake


func _target_point() -> Vector2:
	return target.global_position + Vector2(0.0, config.vertical_offset)


func _update_focus(delta: float) -> void:
	var p := _target_point()
	if target.is_on_floor():
		_focus.y = lerpf(_focus.y, p.y, 1.0 - exp(-config.follow_rate_y * delta))
	var half := config.dead_zone * 0.5
	_focus.x = clampf(_focus.x, p.x - half.x, p.x + half.x)
	_focus.y = clampf(_focus.y, p.y - half.y, p.y + half.y)


func _update_look_ahead(delta: float) -> void:
	var vx := target.velocity.x
	var goal := _look_ahead
	if absf(vx) > 20.0:
		var speed_factor := clampf(absf(vx) / config.look_ahead_full_speed, 0.0, 1.0)
		goal.x = signf(vx) * config.look_ahead_distance * speed_factor
	var vy := target.velocity.y
	var fall_span := maxf(target.config.fast_fall_speed - config.fall_look_threshold, 1.0)
	goal.y = config.fall_look_distance * clampf((vy - config.fall_look_threshold) / fall_span, 0.0, 1.0)
	_look_ahead = _look_ahead.lerp(goal, 1.0 - exp(-config.look_ahead_rate * delta))


func _clamp_to_bounds(p: Vector2) -> Vector2:
	if bounds.size == Vector2.ZERO:
		return p
	var half_view := get_viewport_rect().size * 0.5 / zoom
	var min_p := bounds.position + half_view
	var max_p := bounds.end - half_view
	return Vector2(
		clampf(p.x, min_p.x, maxf(min_p.x, max_p.x)),
		clampf(p.y, min_p.y, maxf(min_p.y, max_p.y)))


func _on_player_landed(impact_speed: float) -> void:
	if target == null:
		return
	var excess := impact_speed - target.config.hard_land_speed * 0.5
	if excess > 0.0:
		add_impulse(Vector2(0.0, excess * config.landing_impulse_scale))
	if impact_speed >= target.config.hard_land_speed:
		add_trauma(config.hard_landing_trauma)
