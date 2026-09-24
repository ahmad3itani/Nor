class_name SlashArc
extends Node2D
## Placeholder slash smear: a crescent swept across the attack's hitbox for
## its active window, then fading. Readable at 480x270 without sprites.

const LIFETIME := 0.12

var rect: Rect2
var facing: int = 1
var color: Color = Color("ffffff")
var heavy: bool = false
var _age: float = 0.0


static func spawn(parent: Node, world_rect: Rect2, p_facing: int, p_color: Color, p_heavy: bool) -> SlashArc:
	var s := SlashArc.new()
	s.rect = world_rect
	s.facing = p_facing
	s.color = p_color
	s.heavy = p_heavy
	parent.add_child(s)
	return s


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := _age / LIFETIME
	var c := rect.get_center()
	var radius := Vector2(rect.size.x * 0.55, rect.size.y * 0.55)
	var start_angle := -PI * 0.55
	var sweep := PI * 1.1 * clampf(t * 2.5, 0.0, 1.0)
	var steps := 10
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var thickness := (4.0 if heavy else 2.5) * (1.0 - t)
	for i in steps + 1:
		var a := start_angle + sweep * float(i) / steps
		var dir := Vector2(cos(a) * facing, sin(a))
		outer.append(c + dir * radius)
		inner.append(c + dir * (radius - Vector2.ONE * thickness))
	var poly := outer.duplicate()
	inner.reverse()
	poly.append_array(inner)
	var col := color
	col.a = 1.0 - t
	if poly.size() >= 3:
		draw_colored_polygon(poly, col)
