class_name AmbientParticles
extends Node2D
## Drifting motes, spores or ash on the backdrop layer (-20), cut from the
## assets/vfx/ambient_particles sheet (8x8 cells, one row per kind). A fixed
## pool drawn by this one node (CPUParticles2D cannot draw AtlasTexture
## regions), capped at 24 and scaled by Motion.count_scale(): none at
## ambient motion Off. Particles wrap around the view and shift with the
## camera at a 0.9 parallax. Own RandomNumberGenerator: never the global one.

const SPEC_PATH := "res://assets/vfx/ambient_particles.tres"
const VIEW := Vector2(480, 270)
const MAX := 24
const PARALLAX := 0.9

var row: StringName = &""
var base_count: int = 0
var tint: Color = Color.WHITE
## px/s; the sign of x follows the district wind.
var wind: Vector2 = Vector2(-4, 2)

var _tex: Texture2D
var _cell: Vector2i = Vector2i(8, 8)
var _frame_row: int = 0
var _frames: int = 1
var _fps: float = 4.0
var _pos: PackedVector2Array = []
var _phase: PackedFloat32Array = []
var _speed: PackedFloat32Array = []
var _rng := RandomNumberGenerator.new()
var _last_cam: Vector2 = Vector2.INF
var _t: float = 0.0


## Null when the sheet or the row is missing (nothing drifts then).
static func create(p_row: StringName, count: int, color: Color, p_wind: Vector2, seed_value: int) -> AmbientParticles:
	if p_row == &"" or count <= 0 or not ResourceLoader.exists(SPEC_PATH):
		return null
	var spec := load(SPEC_PATH) as SpriteSheetSpec
	if spec == null:
		return null
	var anim: SpriteAnim = null
	for a in spec.animations:
		if a and a.name == p_row:
			anim = a
	var tex := spec.load_texture()
	if anim == null or tex == null:
		return null
	var p := AmbientParticles.new()
	p.name = "AmbientParticles"
	p.row = p_row
	p.base_count = mini(count, MAX)
	p.tint = color
	p.wind = p_wind
	p._tex = tex
	p._cell = spec.cell_size
	p._frame_row = anim.row
	p._frames = maxi(anim.frame_count, 1)
	p._fps = anim.fps
	p._rng.seed = seed_value
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.refresh()
	return p


## Live particles for the current motion level.
func target_count() -> int:
	return mini(int(floor(base_count * Motion.count_scale())), MAX)


func live_count() -> int:
	return _pos.size()


## Re-reads the motion level (settings_changed).
func refresh() -> void:
	var n := target_count()
	while _pos.size() > n:
		_pos.remove_at(_pos.size() - 1)
		_phase.remove_at(_phase.size() - 1)
		_speed.remove_at(_speed.size() - 1)
	while _pos.size() < n:
		_pos.append(Vector2(_rng.randf_range(0, VIEW.x), _rng.randf_range(0, VIEW.y)))
		_phase.append(_rng.randf_range(0.0, TAU))
		_speed.append(_rng.randf_range(0.6, 1.2))
	queue_redraw()


func follow(cam: Vector2) -> void:
	if _last_cam != Vector2.INF:
		var d := (cam - _last_cam) * PARALLAX
		if d != Vector2.ZERO:
			for i in _pos.size():
				_pos[i] = _wrap(_pos[i] - d)
	_last_cam = cam


func _process(delta: float) -> void:
	if _pos.is_empty():
		return
	_t += delta
	for i in _pos.size():
		var wobble := Vector2(sin(_t * 0.7 + _phase[i]) * 3.0, cos(_t * 0.5 + _phase[i]) * 2.0)
		_pos[i] = _wrap(_pos[i] + (wind * _speed[i] + wobble) * delta)
	queue_redraw()


func _wrap(p: Vector2) -> Vector2:
	return Vector2(fposmod(p.x, VIEW.x), fposmod(p.y, VIEW.y))


func _draw() -> void:
	if _tex == null:
		return
	for i in _pos.size():
		var f := int(_t * _fps + _phase[i] * 3.0) % _frames
		var src := Rect2(f * _cell.x, _frame_row * _cell.y, _cell.x, _cell.y)
		draw_texture_rect_region(_tex, Rect2(_pos[i] - Vector2(_cell) * 0.5, Vector2(_cell)), src, tint)
