class_name SwayCable
extends Node2D
## A Decor CABLES span as a 1 px verlet polyline that sways in wind gusts
## and when Rook dashes under it. Frozen in its rest sag (exactly the old
## Decor drawing) whenever ambient motion is below Full (Motion.cloth()).
## Visual only; its own RandomNumberGenerator.

const POINTS := 9
const STIFFNESS := 18.0
const DAMPING := 0.94
const GUST_EVERY := Vector2(3.0, 7.0)

var color: Color = Color.WHITE
var rest: PackedVector2Array = []
var pts: PackedVector2Array = []
var prev: PackedVector2Array = []
var _rng := RandomNumberGenerator.new()
var _gust: float = 0.0
var _next_gust: float = 2.0
var _wind: float = 0.0


static func create(size: Vector2, p_color: Color, seed_value: int) -> SwayCable:
	var c := SwayCable.new()
	c.name = "SwayCable"
	c.color = p_color
	c._rng.seed = seed_value
	for i in POINTS:
		var t := i / float(POINTS - 1)
		c.rest.append(Vector2(-size.x * 0.5 + size.x * t, -size.y + sin(t * PI) * size.y * 0.7))
	c.pts = c.rest.duplicate()
	c.prev = c.rest.duplicate()
	c._next_gust = c._rng.randf_range(GUST_EVERY.x, GUST_EVERY.y)
	return c


func moving() -> bool:
	return Motion.cloth()


func _physics_process(delta: float) -> void:
	if not moving():
		if pts != rest:
			pts = rest.duplicate()
			prev = rest.duplicate()
			queue_redraw()
		return
	_next_gust -= delta
	if _next_gust <= 0.0:
		_gust = _rng.randf_range(-1.0, 1.0) * 40.0
		_next_gust = _rng.randf_range(GUST_EVERY.x, GUST_EVERY.y)
	_gust = move_toward(_gust, 0.0, 30.0 * delta)
	_wind = _gust + _dash_push()
	for i in range(1, POINTS - 1):
		var p := pts[i]
		var v := (p - prev[i]) * DAMPING
		var t := i / float(POINTS - 1)
		var acc := (rest[i] - p) * STIFFNESS + Vector2(_wind * sin(t * PI), 0.0)
		prev[i] = p
		pts[i] = p + v + acc * delta * delta
	queue_redraw()


## A dash or fast run under the span pushes it (a small shove, both ways).
func _dash_push() -> float:
	var p := AmbientLife.player_near(self)
	if p == null:
		return 0.0
	var local := to_local(p.global_position)
	if absf(local.x) < absf(rest[0].x) + 8.0 and local.y > rest[0].y - 8.0 and local.y < 48.0 and absf(p.velocity.x) > 200.0:
		return signf(p.velocity.x) * 60.0
	return 0.0


func _draw() -> void:
	draw_polyline(pts, color, 1.0)
