class_name LampGlow
extends Node2D
## A baked lamp or neon halo (assets/vfx/atmos/lamp_glow_*.png, 3 alpha
## steps) drawn additively with one shared CanvasItemMaterial: no Light2D,
## so the 4-light budget stays free for gameplay (ART_DIRECTION section 0).
## Decor LAMPs and NeonSigns attach one at runtime (never in the editor, no
## owner, so no room .tscn byte changes). It sits below characters, enemies
## and pickups (absolute z GLOW_Z) and follows its host's flicker through
## `level`. A neon tube glow is a 3-slice of lamp_glow_tube stretched to the
## sign; with `streak_y` it also draws a 1 px broken reflection line on the
## wet floor below.
##
## A halo the colour of a heal, telegraph, guard or memory cue would read as
## one (REPAIR b, until F2 is decided): colours near the danger reds get no
## glow at all (skip_color); colours near heal green, guard or memory blue
## glow desaturated until they are 48+ away from every reserved colour
## (safe_color), so Lowlight's cyan neon still lights its wall.

const GLOW_Z := -2
const DIR := "res://assets/vfx/atmos"
## Reserved cue colours (Art Bible section 3): heal, danger/telegraph (and
## Redline red), guard, memory.
const RESERVED: Array[Color] = [Color("7dff9a"), Color("ff3b4f"), Color("e8283c"), Color("7fd7ff"), Color("9fd8ff")]
## The ones a halo must never echo, even desaturated.
const DANGER: Array[Color] = [Color("ff3b4f"), Color("e8283c")]
const RESERVED_DISTANCE := 48.0
const TUBE_CAP := 8
const GROUP := &"ambient_glow"

static var _additive: CanvasItemMaterial

var tint: Color = Color.WHITE
## 0..1 host brightness (flicker, broken stutter).
var level: float = 1.0
## Local y of a wet floor to streak on (NAN = none).
var streak_y: float = NAN
var streak_width: float = 0.0
var _tex: Texture2D
var _tube_size: Vector2 = Vector2.ZERO


static func material_shared() -> CanvasItemMaterial:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive


## True when `c` is within RGB distance 48 (0-255 units) of a colour in `set`.
static func near_any(c: Color, colors: Array[Color]) -> bool:
	for r in colors:
		var d := Vector3(c.r - r.r, c.g - r.g, c.b - r.b) * 255.0
		if d.length() < RESERVED_DISTANCE:
			return true
	return false


## No glow at all: the colour is near a danger red.
static func skip_color(c: Color) -> bool:
	return near_any(c, DANGER)


## The halo tint: `c`, desaturated step by step toward its grey until it is
## 48+ away from every reserved colour.
static func safe_color(c: Color) -> Color:
	var grey := Color(c.get_luminance(), c.get_luminance(), c.get_luminance(), c.a)
	var out := c
	var t := 0.0
	while near_any(out, RESERVED) and t < 1.0:
		t += 0.1
		out = c.lerp(grey, t)
	return out


## A round halo (size 8, 16 or 32) centred on the node.
static func round_glow(color: Color, size: int) -> LampGlow:
	var path := "%s/lamp_glow_%d.png" % [DIR, size]
	if skip_color(color) or not ResourceLoader.exists(path):
		return null
	var g := LampGlow.new()
	g._tex = load(path) as Texture2D
	g._init_glow(color)
	return g


## A tube halo around a `tube` sized sign (centred), 8 px wider each side.
static func tube_glow(color: Color, tube: Vector2) -> LampGlow:
	var path := "%s/lamp_glow_tube.png" % DIR
	if skip_color(color) or not ResourceLoader.exists(path):
		return null
	var g := LampGlow.new()
	g._tex = load(path) as Texture2D
	g._tube_size = Vector2(tube.x + TUBE_CAP * 2, maxf(tube.y + 6.0, 12.0))
	g._init_glow(color)
	return g


func _init_glow(color: Color) -> void:
	name = "LampGlow"
	tint = safe_color(color)
	z_as_relative = false
	z_index = GLOW_Z
	material = material_shared()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_to_group(GROUP)


func set_level(v: float) -> void:
	if not is_equal_approx(v, level):
		level = v
		queue_redraw()


## The halo's rect in local space.
func glow_rect() -> Rect2:
	if _tube_size != Vector2.ZERO:
		return Rect2(-_tube_size * 0.5, _tube_size)
	var s := Vector2(_tex.get_size()) if _tex else Vector2.ZERO
	return Rect2(-s * 0.5, s)


func _draw() -> void:
	if _tex == null or level <= 0.0:
		return
	var c := Color(tint, level)
	var r := glow_rect()
	if _tube_size == Vector2.ZERO:
		draw_texture(_tex, r.position.floor(), c)
	else:
		# 3-slice: caps keep their pixels, the middle stretches.
		var tw := float(_tex.get_width())
		var th := float(_tex.get_height())
		var cap := minf(TUBE_CAP, r.size.x * 0.5)
		var p := r.position.floor()
		draw_texture_rect_region(_tex, Rect2(p, Vector2(cap, r.size.y)), Rect2(0, 0, cap, th), c)
		draw_texture_rect_region(_tex, Rect2(p + Vector2(cap, 0), Vector2(r.size.x - cap * 2.0, r.size.y)), Rect2(cap, 0, tw - cap * 2.0, th), c)
		draw_texture_rect_region(_tex, Rect2(p + Vector2(r.size.x - cap, 0), Vector2(cap, r.size.y)), Rect2(tw - cap, 0, cap, th), c)
	if not is_nan(streak_y) and streak_width > 0.0:
		# A broken 1 px reflection on the wet floor: dashes, not a line.
		var x := -floorf(streak_width * 0.5)
		var i := 0
		while x < streak_width * 0.5:
			var w := 3.0 if i % 3 != 2 else 1.0
			draw_rect(Rect2(x, streak_y, w, 1), Color(tint, 0.35 * level))
			x += w + 2.0
			i += 1
