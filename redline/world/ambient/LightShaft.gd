class_name LightShaft
extends Sprite2D
## A baked god-ray (assets/vfx/atmos/light_shaft_a/b.png, 3 alpha steps,
## additive, no Light2D) on the backdrop layer, anchored to a world x from
## the room seed and moving at the backwall ladder (0.9). Its alpha breathes
## between 0.9 and 1.0 at 0.15 Hz; it holds still at ambient motion Off and
## under flash reduction. Tint and alpha live in self_modulate (the
## background dim owns modulate).

const PATH_A := "res://assets/vfx/atmos/light_shaft_a.png"
const PATH_B := "res://assets/vfx/atmos/light_shaft_b.png"
const VIEW := Vector2(480, 270)
const MOTION := 0.9
const BREATH_HZ := 0.15

static var _additive: CanvasItemMaterial

## World x and y of the shaft's top-left (px).
var world_pos: Vector2 = Vector2.ZERO
var tint: Color = Color.WHITE
var _t: float = 0.0


static func additive_material() -> CanvasItemMaterial:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive


static func create(wide: bool, at: Vector2, color: Color, phase: float) -> LightShaft:
	var path := PATH_B if wide else PATH_A
	if not ResourceLoader.exists(path):
		return null
	var s := LightShaft.new()
	s.name = "LightShaft"
	s.texture = load(path) as Texture2D
	s.centered = false
	s.material = additive_material()
	s.world_pos = at
	s.tint = color
	s._t = phase
	s.self_modulate = color
	return s


func follow(cam: Vector2) -> void:
	position = (world_pos - cam) * MOTION + VIEW * 0.5


func breathing() -> bool:
	return Motion.animate_ambient() and not Settings.flash_reduction


func _process(delta: float) -> void:
	var a := 1.0
	if breathing():
		_t += delta
		a = 0.95 + 0.05 * sin(_t * TAU * BREATH_HZ)
	self_modulate = Color(tint, a)
