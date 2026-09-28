class_name ParallaxPlane
extends Node2D
## One painted backdrop plane (PlaneSpec) on the DistrictBackdrop layer.
## Its tiles (A, B, A, B... or A, A...) are drawn once; each frame only the
## node moves, so a plane costs a transform update, not a redraw. Positions
## are computed like DistrictBackdrop._draw_layer: unrounded offsets on the
## nearest-filtered canvas, never rounded for the planes alone.

const VIEW := Vector2(480, 270)

var spec: PlaneSpec
var tex_a: Texture2D
var tex_b: Texture2D
var motion: Vector2 = Vector2.ZERO
var y_anchor: float = 0.0
var tile_y: bool = false
var x_offset: float = 0.0
## Horizontal step between tiles (px).
var step: float = 480.0
## Extra scroll in px added to the camera term (fog drift).
var drift: float = 0.0


## Builds a plane from its spec; null when the texture is missing.
static func from_spec(p: PlaneSpec) -> ParallaxPlane:
	if p == null:
		return null
	var a := p.load_texture()
	if a == null:
		return null
	var plane := ParallaxPlane.new()
	plane.spec = p
	plane.setup(a, p.load_alt(), p.motion, p.y_anchor, p.tile_y, p.spacing, p.x_offset)
	plane.name = "Plane_%s" % p.texture_path.get_file().get_basename()
	return plane


func setup(a: Texture2D, b: Texture2D, p_motion: Vector2, p_anchor: float, p_tile_y: bool, spacing: int = 0, p_x_offset: float = 0.0) -> void:
	tex_a = a
	tex_b = b
	motion = p_motion
	y_anchor = p_anchor
	tile_y = p_tile_y
	x_offset = p_x_offset
	step = float(spacing if spacing > 0 else a.get_width())
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()


## One repeat of the pattern (A+B when there is a B).
func cycle() -> float:
	return step * (2.0 if tex_b else 1.0)


func tex_height() -> float:
	return float(tex_a.get_height()) if tex_a else 0.0


## Places the plane for the camera centre `cam`; `ref_y` is the camera y at
## the room floor (the resting position the anchors are authored for).
func follow(cam: Vector2, ref_y: float) -> void:
	position.x = -fposmod(cam.x * motion.x + drift - x_offset, cycle())
	var h := tex_height()
	if tile_y:
		position.y = -fposmod(cam.y * motion.y, h) if h > 0.0 else 0.0
	else:
		position.y = VIEW.y + y_anchor - h - (cam.y - ref_y) * motion.y


## True when it covers the whole view whatever the camera does.
func covers_view() -> bool:
	if spec == null or not spec.opaque:
		return false
	return tile_y or (tex_height() >= VIEW.y and is_zero_approx(motion.y))


func _draw() -> void:
	if tex_a == null:
		return
	var h := tex_height()
	var rows := 1
	if tile_y and h > 0.0:
		rows = int(ceil(VIEW.y / h)) + 1
	var n := int(ceil((cycle() + VIEW.x) / step)) + 1
	for i in n:
		var tex := tex_b if tex_b and i % 2 == 1 else tex_a
		for r in rows:
			draw_texture(tex, Vector2(i * step, r * h))
