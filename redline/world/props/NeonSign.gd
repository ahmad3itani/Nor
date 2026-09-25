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
## A broken tube (the Undercity secret cue, ART_BIBLE §3): hung askew, only
## its upper half lit, and it stutters in bursts instead of the ambient
## tubes' rare blink. Reserved for cues; ambience never sets it.
@export var broken: bool = false:
	set(v):
		broken = v
		queue_redraw()

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
		if broken:
			# A stutter: three quick dropouts every 1.5 s.
			var b := fmod(_t + _seed, 1.5)
			on = not (b < 0.06 or (b > 0.12 and b < 0.2) or (b > 0.28 and b < 0.32))
		else:
			on = not (phase > 3.6 and phase < 3.7) and not (phase > 3.78 and phase < 3.82)
	var c := color if on else color.darkened(0.7)
	if broken:
		_draw_broken(c)
		return
	draw_rect(Rect2(-size * 0.5 - Vector2(2, 2), size + Vector2(4, 4)), Color(c, 0.12))
	draw_rect(Rect2(-size * 0.5, size), Color(0.05, 0.03, 0.07, 1.0))
	draw_rect(Rect2(-size * 0.5, size), c, false, 1.0)
	for i in strokes:
		var x := -size.x * 0.5 + 3.0 + i * (size.x - 6.0) / maxf(strokes, 1)
		draw_rect(Rect2(x, -size.y * 0.5 + 2.0, 2.0 + (i % 2) * 2.0, size.y - 4.0), c)


## Askew, half lit: the dead half is a dark stub under the live one.
func _draw_broken(c: Color) -> void:
	draw_set_transform(Vector2.ZERO, 0.35 if size.y >= size.x else 0.2)
	var dead := color.darkened(0.75)
	draw_rect(Rect2(-size * 0.5 - Vector2(2, 2), size + Vector2(4, 4)), Color(c, 0.12))
	draw_rect(Rect2(-size * 0.5, size), Color(0.05, 0.03, 0.07, 1.0))
	if size.y >= size.x:
		var half := Vector2(size.x, size.y * 0.5)
		draw_rect(Rect2(-size * 0.5, half), c)
		draw_rect(Rect2(-size * 0.5 + Vector2(0, half.y), half), dead, false, 1.0)
	else:
		var half := Vector2(size.x * 0.5, size.y)
		draw_rect(Rect2(-size * 0.5, half), c)
		draw_rect(Rect2(-size * 0.5 + Vector2(half.x, 0), half), dead, false, 1.0)
	draw_set_transform(Vector2.ZERO)
