class_name ClothStrip
extends Node2D
## A 3-segment cloth ripple (ART_DIRECTION 4.6): Warden banners (Decor
## BANNER) and the Relay's hanging cloth strips (relay_fg_set regions). The
## top segment hangs still; the lower two shift sideways by whole pixels on
## a slow sine. Frozen at rest whenever ambient motion is below Full
## (Motion.cloth()). Visual only.

const SEGMENTS := 3
const SPEED := 1.6

## Banner mode (no texture): the old Decor BANNER drawing.
var size: Vector2 = Vector2.ZERO
var color: Color = Color.WHITE
var accent: Color = Color.WHITE
## Texture mode: a region of an atlas, drawn with its top-left at the node.
var texture: Texture2D
var region: Rect2 = Rect2()
var _t: float = 0.0
var _offsets: PackedInt32Array = [0, 0, 0]


## Decor BANNER: origin bottom-centre like Decor.
static func for_banner(p_size: Vector2, p_color: Color, p_accent: Color, seed_value: int) -> ClothStrip:
	var c := ClothStrip.new()
	c.name = "ClothStrip"
	c.size = p_size
	c.color = p_color
	c.accent = p_accent
	c._t = float(absi(seed_value) % 1000) * 0.01
	return c


## An atlas region (the fg set's cloth strips), top-left at the node.
static func for_region(tex: Texture2D, p_region: Rect2, seed_value: int) -> ClothStrip:
	var c := ClothStrip.new()
	c.name = "ClothStrip"
	c.texture = tex
	c.region = p_region
	c.size = p_region.size
	c._t = float(absi(seed_value) % 1000) * 0.01
	c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return c


func segment_offsets() -> PackedInt32Array:
	return _offsets


func _process(delta: float) -> void:
	var next := PackedInt32Array([0, 0, 0])
	if Motion.cloth():
		_t += delta
		for s in range(1, SEGMENTS):
			next[s] = int(round(sin(_t * SPEED + s * 0.9) * s * 0.75))
	if next != _offsets:
		_offsets = next
		queue_redraw()


func _draw() -> void:
	var seg_h := ceilf(size.y / SEGMENTS)
	for s in SEGMENTS:
		var y0 := s * seg_h
		var h := minf(seg_h, size.y - y0)
		if h <= 0.0:
			continue
		var dx := float(_offsets[s])
		if texture:
			draw_texture_rect_region(texture, Rect2(dx, y0, size.x, h), Rect2(region.position + Vector2(0, y0), Vector2(size.x, h)))
		else:
			var top := -size.y + y0
			draw_rect(Rect2(-size.x * 0.5 + dx, top, size.x, h), color)
			if s == 0:
				draw_rect(Rect2(-size.x * 0.5 + 2, -size.y + 3, size.x - 4, 2), accent)
