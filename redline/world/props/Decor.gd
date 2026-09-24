@tool
class_name Decor
extends Node2D
## Non-colliding set dressing drawn procedurally (placeholder art that still
## tells the place's story: bible §25 "old, layered and inhabited").
## Origin is bottom-centre so props sit on floors.

enum Kind { PILLAR, LAMP, CRATES, BENCH, TRAIN_CAR, RADIO, WORKBENCH, PIPES, AC_UNIT, BANNER, PLANTER, CABLES }

@export var kind: Kind = Kind.CRATES:
	set(v):
		kind = v
		queue_redraw()
@export var size: Vector2 = Vector2(24, 24):
	set(v):
		size = v
		queue_redraw()
@export var color: Color = Color("3a3448"):
	set(v):
		color = v
		queue_redraw()
@export var accent: Color = Color("ffcf5a"):
	set(v):
		accent = v
		queue_redraw()

var _t: float = 0.0


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or (kind != Kind.LAMP and kind != Kind.RADIO):
		return
	_t += delta
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var base := Rect2(-w * 0.5, -h, w, h)
	match kind:
		Kind.PILLAR:
			draw_rect(base, color)
			draw_rect(Rect2(base.position.x - 2, -h, w + 4, 4), color.lightened(0.1))
			draw_rect(Rect2(base.position.x - 2, -4, w + 4, 4), color.lightened(0.1))
			draw_rect(Rect2(base.position.x + 2, -h + 4, 1, h - 8), color.darkened(0.25))
		Kind.LAMP:
			draw_rect(Rect2(-1, -h, 2, h - 6), color)
			var glow := 0.75 + 0.25 * sin(_t * 2.0 + position.x)
			draw_rect(Rect2(-4, -h - 3, 8, 4), Color(accent, glow))
			draw_rect(Rect2(-10, -h + 1, 20, 12), Color(accent, 0.07 * glow))
		Kind.CRATES:
			draw_rect(Rect2(-w * 0.5, -h * 0.5, w * 0.55, h * 0.5), color)
			draw_rect(Rect2(-w * 0.5 + w * 0.5, -h * 0.5, w * 0.5, h * 0.5), color.lightened(0.08))
			draw_rect(Rect2(-w * 0.3, -h, w * 0.55, h * 0.5), color.darkened(0.08))
			draw_rect(Rect2(-w * 0.3 + 2, -h + 2, w * 0.55 - 4, 1), color.lightened(0.2))
		Kind.BENCH:
			draw_rect(Rect2(-w * 0.5, -h * 0.6, w, 3), color.lightened(0.1))
			draw_rect(Rect2(-w * 0.5 + 2, -h * 0.6, 2, h * 0.6), color)
			draw_rect(Rect2(w * 0.5 - 4, -h * 0.6, 2, h * 0.6), color)
		Kind.TRAIN_CAR:
			draw_rect(base, color)
			draw_rect(Rect2(base.position.x, -h, w, 3), color.lightened(0.15))
			var x := base.position.x + 6.0
			while x < base.end.x - 14.0:
				draw_rect(Rect2(x, -h + 8, 10, 8), accent.darkened(0.5))
				x += 16.0
			draw_rect(Rect2(base.position.x + 4, -6, w - 8, 3), color.darkened(0.4))
		Kind.RADIO:
			draw_rect(base, color)
			for i in 3:
				var on := sin(_t * 4.0 + i * 1.7) > 0.0
				draw_rect(Rect2(base.position.x + 3 + i * 5, -h + 3, 3, 3), accent if on else accent.darkened(0.7))
			draw_line(Vector2(w * 0.3, -h), Vector2(w * 0.5, -h - 14), color.lightened(0.3), 1.0)
		Kind.WORKBENCH:
			draw_rect(Rect2(-w * 0.5, -h, w, 4), color.lightened(0.12))
			draw_rect(Rect2(-w * 0.5 + 1, -h + 4, 3, h - 4), color)
			draw_rect(Rect2(w * 0.5 - 4, -h + 4, 3, h - 4), color)
			draw_rect(Rect2(-w * 0.2, -h - 5, 8, 5), accent.darkened(0.3))
		Kind.PIPES:
			draw_rect(Rect2(-w * 0.5, -h, w, 4), color)
			draw_rect(Rect2(-w * 0.5, -h + 7, w, 3), color.darkened(0.15))
			var px := -w * 0.5 + 10.0
			while px < w * 0.5:
				draw_rect(Rect2(px, -h - 1, 3, 6), color.lightened(0.15))
				px += 32.0
		Kind.AC_UNIT:
			draw_rect(base, color)
			draw_rect(Rect2(base.position.x + 2, -h + 2, w - 4, h - 4), color.darkened(0.2), false, 1.0)
			draw_line(Vector2(base.position.x + 3, -h * 0.5), Vector2(base.end.x - 3, -h * 0.5), color.lightened(0.2), 1.0)
		Kind.BANNER:
			draw_rect(Rect2(-w * 0.5, -h, w, h), color)
			draw_rect(Rect2(-w * 0.5 + 2, -h + 3, w - 4, 2), accent)
			draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.5, 0), Vector2(0, -4), Vector2(w * 0.5, 0)]), Color(0, 0, 0, 0))
		Kind.PLANTER:
			draw_rect(Rect2(-w * 0.5, -h * 0.4, w, h * 0.4), color)
			for i in 4:
				draw_rect(Rect2(-w * 0.5 + 3 + i * (w - 6) / 4.0, -h + (i % 2) * 4, 3, h * 0.6), accent)
		Kind.CABLES:
			var pts := PackedVector2Array()
			for i in 9:
				var t := i / 8.0
				pts.append(Vector2(-w * 0.5 + w * t, -h + sin(t * PI) * h * 0.7))
			draw_polyline(pts, color, 1.0)
