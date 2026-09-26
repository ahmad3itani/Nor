class_name DistrictBackdrop
extends CanvasLayer
## Screen-space sky + two parallax skyline layers + rain, driven by the room
## camera. Drawn procedurally from a seeded layout: cheap, deterministic, and
## replaceable by painted layers later without touching room scenes.
##
## Background dim (M9 T12, bible §24, D4 §7.2): Settings.background_dim darkens
## the sky and skyline by AccessibilityConfig.background_dim[i], so the play
## layer separates from the parallax. Rain stays: it sits in front of the
## world. Independent of high contrast (neither forces the other).

const VIEW := Vector2(480, 270)
const PERIOD := 960.0

var theme: DistrictTheme
var camera: Camera2D
var _sky: Node2D
var _front: Node2D
var _buildings_far: Array[Rect2] = []
var _buildings_mid: Array[Rect2] = []
var _windows: Array = []  # [Rect2, Color, layer]
var _drops: Array[Vector2] = []
var _rng := RandomNumberGenerator.new()


func setup(p_theme: DistrictTheme, p_camera: Camera2D) -> void:
	theme = p_theme
	camera = p_camera


func _ready() -> void:
	layer = -20
	_rng.seed = 1234
	_build_skyline(_buildings_far, 0, 60.0, 150.0, 30.0, 70.0)
	_build_skyline(_buildings_mid, 1, 30.0, 110.0, 36.0, 90.0)
	_sky = Node2D.new()
	_sky.draw.connect(_draw_sky)
	add_child(_sky)
	apply_dim()
	EventBus.settings_changed.connect(apply_dim)
	# Rain sits in front of the world, behind the HUD.
	var front_layer := CanvasLayer.new()
	front_layer.layer = 5
	add_child(front_layer)
	_front = Node2D.new()
	_front.draw.connect(_draw_rain)
	front_layer.add_child(_front)
	for i in theme.rain_drops if theme and theme.rain else 0:
		_drops.append(Vector2(_rng.randf_range(0, VIEW.x), _rng.randf_range(0, VIEW.y)))


## Sets the sky layer's modulate from the background-dim setting.
func apply_dim() -> void:
	if _sky:
		_sky.modulate = dim_modulate(Settings.background_dim)


## Pure: the modulate for a background_dim index (white at Off).
static func dim_modulate(index: int) -> Color:
	var cfg := Settings.config()
	var d := 0.0
	if cfg and not cfg.background_dim.is_empty():
		d = cfg.background_dim[clampi(index, 0, cfg.background_dim.size() - 1)]
	return Color(1.0 - d, 1.0 - d, 1.0 - d, 1.0)


## The sky layer (tests read its modulate).
func sky_layer() -> Node2D:
	return _sky


func _build_skyline(out: Array[Rect2], layer_idx: int, min_h: float, max_h: float, min_w: float, max_w: float) -> void:
	var x := 0.0
	while x < PERIOD:
		var w := _rng.randf_range(min_w, max_w)
		var h := _rng.randf_range(min_h, max_h)
		var r := Rect2(x, -h, w - 2.0, h)
		out.append(r)
		var wy := r.position.y + 6.0
		while wy < -6.0:
			var wx := r.position.x + 4.0
			while wx < r.end.x - 4.0:
				if theme and _rng.randf() < theme.window_density:
					_windows.append([Rect2(wx, wy, 2, 2), theme.window_colors[_rng.randi() % theme.window_colors.size()], layer_idx])
				wx += 6.0
			wy += 8.0
		x += w


func _process(delta: float) -> void:
	if theme == null:
		return
	if theme.rain:
		var fall := Vector2(sin(deg_to_rad(theme.rain_angle_deg)), 1.0) * 420.0 * delta
		for i in _drops.size():
			var d := _drops[i] + fall
			if d.y > VIEW.y:
				d = Vector2(_rng.randf_range(-20, VIEW.x), -8.0)
			_drops[i] = d
	_sky.queue_redraw()
	_front.queue_redraw()


func _cam() -> Vector2:
	return camera.get_screen_center_position() if camera and is_instance_valid(camera) else Vector2.ZERO


func _draw_sky() -> void:
	if theme == null:
		return
	var steps := 12
	for i in steps:
		var t := float(i) / steps
		_sky.draw_rect(Rect2(0, VIEW.y * t, VIEW.x, VIEW.y / steps + 1), theme.sky_top.lerp(theme.sky_bottom, t))
	var cam := _cam()
	_draw_layer(_buildings_far, 0, cam, 0.12, 0.03, theme.far_color, VIEW.y + 10.0)
	_draw_layer(_buildings_mid, 1, cam, 0.3, 0.07, theme.mid_color, VIEW.y + 30.0)


func _draw_layer(rects: Array[Rect2], layer_idx: int, cam: Vector2, sx: float, sy: float, color: Color, base_y: float) -> void:
	var ox := -fposmod(cam.x * sx, PERIOD)
	var oy := base_y - cam.y * sy
	for rep in [0.0, PERIOD]:
		var off := Vector2(ox + rep, oy)
		for r in rects:
			var rr := Rect2(r.position + off, r.size)
			if rr.end.x < 0 or rr.position.x > VIEW.x:
				continue
			_sky.draw_rect(rr, color)
		for w in _windows:
			if w[2] != layer_idx:
				continue
			var wr: Rect2 = w[0]
			var p := wr.position + off
			if p.x < 0 or p.x > VIEW.x:
				continue
			_sky.draw_rect(Rect2(p, wr.size), Color(w[1], 0.55 if layer_idx == 0 else 0.8))


func _draw_rain() -> void:
	if theme == null or not theme.rain:
		return
	var streak := Vector2(sin(deg_to_rad(theme.rain_angle_deg)), 1.0) * 6.0
	for d in _drops:
		_front.draw_line(d, d + streak, theme.rain_color, 1.0)
