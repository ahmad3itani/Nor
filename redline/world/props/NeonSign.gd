@tool
class_name NeonSign
extends Node2D
## Restrained neon accent (bible §25): a lit panel with an occasional
## flicker. Pure decoration; never used to hide gameplay information.

@export var size: Vector2 = Vector2(24, 8):
	set(v):
		size = v
		queue_redraw()
@export var color: Color = Color("e8283c"):
	set(v):
		color = v
		queue_redraw()
@export var flicker: bool = true
## Glyph strokes drawn inside the panel (fake lettering).
@export var strokes: int = 3

var _t: float = 0.0
var _seed: float


func _ready() -> void:
	_seed = fmod(position.x * 0.37 + position.y * 0.11, 10.0)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += delta
	queue_redraw()


func _draw() -> void:
	var on := true
	if flicker and not Settings.flash_reduction:
		var phase := fmod(_t + _seed, 4.0)
		on = not (phase > 3.6 and phase < 3.7) and not (phase > 3.78 and phase < 3.82)
	var c := color if on else color.darkened(0.7)
	draw_rect(Rect2(-size * 0.5 - Vector2(2, 2), size + Vector2(4, 4)), Color(c, 0.12))
	draw_rect(Rect2(-size * 0.5, size), Color(0.05, 0.03, 0.07, 1.0))
	draw_rect(Rect2(-size * 0.5, size), c, false, 1.0)
	for i in strokes:
		var x := -size.x * 0.5 + 3.0 + i * (size.x - 6.0) / maxf(strokes, 1)
		draw_rect(Rect2(x, -size.y * 0.5 + 2.0, 2.0 + (i % 2) * 2.0, size.y - 4.0), c)
