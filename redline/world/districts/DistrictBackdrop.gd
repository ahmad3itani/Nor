class_name DistrictBackdrop
extends CanvasLayer
## Screen-space sky + two parallax skyline layers + rain, driven by the room
## camera. Drawn procedurally from a seeded layout: cheap, deterministic, and
## the fallback whenever painted layers are missing.
##
## Painted backdrop (presentation overhaul): the room's backdrop kind
## (PresentationIndex, RoomPresentation.backdrop_kind; the title passes
## &"title") picks data/presentation/backdrops/<kind>.tres, a BackdropSet:
## painted ParallaxPlanes back to front, two drifting FogBands, LightShafts,
## AmbientParticles, a far train, sky lightning and a Vignette, all on this
## layer (-20, behind the world). AmbientLife (moths, rats, gulls, drips,
## steam) goes into the room itself; foreground silhouettes go on their own
## layer in front of the world. No set, or a set none of whose textures
## load, keeps today's procedural sky and skyline exactly.
##
## Grade rule (F11): the district grade is the modulate of `_grade_root`, a
## dedicated parent of the backdrop nodes on this layer only; the world,
## characters and HUD never get it, and `_sky.modulate` stays exactly
## dim_modulate().
##
## Background dim (M9 T12, bible §24, D4 §7.2): Settings.background_dim darkens
## the sky, skyline and every plane, fog, shaft, particle and train node by
## AccessibilityConfig.background_dim[i], so the play layer separates from
## the parallax. Rain stays: it sits in front of the world. Independent of
## high contrast (neither forces the other; high contrast only hides the
## vignette).

const VIEW := Vector2(480, 270)
const PERIOD := 960.0
const FOREGROUND_LAYER := 2
const FG_MOTION := 1.2
const FG_TOP_BAND := 40.0
const FG_FADE_ALPHA := 0.35
## Bottom band of the view that floor pieces never reach: the HUD rows
## (view.y - 30), the prompt (view.y - 46) and the hint caption (view.y - 58).
const FG_HUD_BAND := 62.0
const FG_HAZARD_GROUPS: Array[StringName] = [&"enemies", &"hazard", &"hazards"]
const TRAIN_PATH := "res://assets/lowlight/ll_train_far.png"
const TRAIN_SPEED := 46.0
const FLASH_TINT := Color(1.7, 1.7, 1.9, 1.0)
const FLASH_STATIC_TINT := Color(1.25, 1.25, 1.35, 1.0)

var theme: DistrictTheme
var camera: Camera2D
## The backdrop kind; empty = the owning room's (PresentationIndex), else
## the theme's backdrop_kind_default. Set before add_child to force one.
var backdrop_kind: StringName = &""
## The loaded set (null = procedural only). Assign one before add_child to
## use it instead of the kind's file.
var backdrop_set: BackdropSet
## Camera centre y at the room floor (the anchors' reference); NAN = derived
## from the owning Room's bounds, else the camera's first position.
var ref_camera_y: float = NAN
var _sky: Node2D
var _front: Node2D
var _buildings_far: Array[Rect2] = []
var _buildings_mid: Array[Rect2] = []
var _windows: Array = []  # [Rect2, Color, layer]
var _drops: Array[Vector2] = []
var _rng := RandomNumberGenerator.new()
## Presentation RNG for placements and timers (never the global RNG).
var _fx_rng := RandomNumberGenerator.new()
var _grade_root: Node2D
var _flash_root: Node2D
var _planes: Array[ParallaxPlane] = []
var _fogs: Array[FogBand] = []
var _shafts: Array[LightShaft] = []
var _particles: AmbientParticles
var _vignette: Vignette
var _life: AmbientLife
var _train: Sprite2D
var _train_timer: float = 0.0
var _train_dir: float = 1.0
var _lightning_timer: float = 0.0
var _flash_t: float = -1.0
var _procedural_skyline: bool = true
var _fg_layer: CanvasLayer
## {node: CanvasItem, world_x: float, top: bool, size: Vector2}
var _fg_pieces: Array[Dictionary] = []
## The room's Collector eyes (found once; the fg fades over them).
var _trackers: Array[Node2D] = []
var _room: Node2D


func setup(p_theme: DistrictTheme, p_camera: Camera2D) -> void:
	theme = p_theme
	camera = p_camera


func _ready() -> void:
	layer = -20
	_rng.seed = 1234
	_room = AmbientLife.room_of(get_parent())
	_build_skyline(_buildings_far, 0, 60.0, 150.0, 30.0, 70.0)
	_build_skyline(_buildings_mid, 1, 30.0, 110.0, 36.0, 90.0)
	_grade_root = Node2D.new()
	_grade_root.name = "Grade"
	add_child(_grade_root)
	_flash_root = Node2D.new()
	_flash_root.name = "SkyFlash"
	_grade_root.add_child(_flash_root)
	_sky = Node2D.new()
	_sky.name = "Sky"
	_sky.draw.connect(_draw_sky)
	_flash_root.add_child(_sky)
	if backdrop_set == null:
		backdrop_set = _resolve_set()
	if backdrop_set:
		_build_set()
	apply_dim()
	EventBus.settings_changed.connect(apply_dim)
	EventBus.settings_changed.connect(_on_settings_changed)
	# Rain sits in front of the world, behind the HUD.
	var front_layer := CanvasLayer.new()
	front_layer.layer = 5
	add_child(front_layer)
	_front = Node2D.new()
	_front.draw.connect(_draw_rain)
	front_layer.add_child(_front)
	for i in _rain_drops():
		_drops.append(Vector2(_rng.randf_range(0, VIEW.x), _rng.randf_range(0, VIEW.y)))
	if backdrop_set:
		_build_foreground()
		_vignette = Vignette.create(backdrop_set.vignette_alpha)
		if _vignette:
			add_child(_vignette)
	_follow_all()


func _exit_tree() -> void:
	for c: Callable in [apply_dim, _on_settings_changed]:
		if EventBus.settings_changed.is_connected(c):
			EventBus.settings_changed.disconnect(c)


## Sets the sky layer's and every backdrop node's modulate from the
## background-dim setting.
func apply_dim() -> void:
	var dim := dim_modulate(Settings.background_dim)
	if _sky:
		_sky.modulate = dim
	for n in dimmed_nodes():
		n.modulate = dim


## Every painted node the dim reaches (planes, fog, shafts, particles, train).
func dimmed_nodes() -> Array[CanvasItem]:
	var out: Array[CanvasItem] = []
	for p in _planes:
		out.append(p)
	for f in _fogs:
		out.append(f)
	for s in _shafts:
		out.append(s)
	if _particles:
		out.append(_particles)
	if _train:
		out.append(_train)
	return out


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


## The node carrying the district grade (backdrop layer only).
func grade_root() -> Node2D:
	return _grade_root


func planes() -> Array[ParallaxPlane]:
	return _planes


func fogs() -> Array[FogBand]:
	return _fogs


func shafts() -> Array[LightShaft]:
	return _shafts


func particles() -> AmbientParticles:
	return _particles


func vignette() -> Vignette:
	return _vignette


func life() -> AmbientLife:
	return _life


func foreground_layer() -> CanvasLayer:
	return _fg_layer


func foreground_pieces() -> Array[Dictionary]:
	return _fg_pieces


## True when the procedural skyline draws (no painted plane loaded).
func procedural_skyline() -> bool:
	return _procedural_skyline


# --- set -----------------------------------------------------------------

func _resolve_set() -> BackdropSet:
	var kind := backdrop_kind
	if kind == &"" and _room:
		var pres := PresentationIndex.for_room_node(_room)
		if pres:
			kind = pres.backdrop_kind
	if kind == &"" and theme:
		kind = theme.backdrop_kind_default
	backdrop_kind = kind
	return BackdropSet.for_kind(kind)


func _room_seed() -> int:
	if _room and _room.scene_file_path != "":
		return hash(_room.scene_file_path)
	return hash(String(backdrop_kind))


func _ref_y() -> float:
	if not is_nan(ref_camera_y):
		return ref_camera_y
	if _room and "bounds" in _room:
		var b: Rect2 = _room.get("bounds")
		ref_camera_y = b.end.y - VIEW.y * 0.5
	else:
		ref_camera_y = _cam().y
	return ref_camera_y


func _build_set() -> void:
	var s := backdrop_set
	_fx_rng.seed = _room_seed()
	_grade_root.modulate = s.grade
	# Back to front; fog band A (and the far train) go in front of the far
	# planes, before the first plane at 0.2+ (or at s.fog_a_index).
	var specs := s.background_planes()
	var fog_at := s.fog_a_index
	if fog_at < 0:
		fog_at = specs.size()
		for i in specs.size():
			if specs[i].motion.x >= 0.2:
				fog_at = i
				break
	var fog_a := FogBand.create(0, s.fog_color, s.fog_alpha_a, s.fog_drift_a, s.fog_anchor_a)
	var far_seen := false
	for i in specs.size() + 1:
		if i == fog_at:
			if s.life.has(&"train") and far_seen and ResourceLoader.exists(TRAIN_PATH):
				_train = Sprite2D.new()
				_train.name = "FarTrain"
				_train.texture = load(TRAIN_PATH) as Texture2D
				_train.centered = false
				_train.visible = false
				_grade_root.add_child(_train)
				_train_timer = _fx_rng.randf_range(s.train_period.x * 0.3, s.train_period.x)
			if fog_a:
				_fogs.append(fog_a)
				_grade_root.add_child(fog_a)
		if i == specs.size():
			break
		var plane := ParallaxPlane.from_spec(specs[i])
		if plane == null:
			continue
		_planes.append(plane)
		if specs[i].motion == Vector2.ZERO:
			_flash_root.add_child(plane)
		else:
			far_seen = far_seen or specs[i].motion.x < 0.2
			_grade_root.add_child(plane)
	_procedural_skyline = _planes.is_empty()
	if _room and "bounds" in _room:
		_build_shafts()
	var wind := Vector2(signf(s.fog_drift_a if s.fog_drift_a != 0.0 else -1.0) * 4.0, 2.0)
	_particles = AmbientParticles.create(s.particle_row(), s.particle_count, s.particle_color, wind, _room_seed())
	if _particles:
		_grade_root.add_child(_particles)
	var fog_b := FogBand.create(1, s.fog_color, s.fog_alpha_b, s.fog_drift_b, s.fog_anchor_b)
	if fog_b:
		_fogs.append(fog_b)
		_grade_root.add_child(fog_b)
	_hide_occluded()
	if s.lightning:
		_lightning_timer = _fx_rng.randf_range(s.lightning_period.x, s.lightning_period.y)
	var kinds: Array[StringName] = []
	for k in s.life:
		if k != &"train":
			kinds.append(k)
	if _room and not kinds.is_empty():
		_life = AmbientLife.create(_room, kinds, _room_seed(), Color.WHITE)
		_room.add_child.call_deferred(_life)


## Fill-rate (REPAIR e): everything behind the frontmost plane that covers
## the view is hidden, the procedural sky included.
func _hide_occluded() -> void:
	var cover: ParallaxPlane = null
	for p in _planes:
		if p.covers_view():
			cover = p
	if cover == null:
		return
	_sky.visible = false
	var order := _grade_root.get_children()
	var sky_order := _flash_root.get_children()
	var cover_in_sky := sky_order.has(cover)
	for n in sky_order:
		if n == cover:
			break
		(n as CanvasItem).visible = false
	if cover_in_sky:
		return
	for n in order:
		if n == cover:
			break
		(n as CanvasItem).visible = false


func _build_shafts() -> void:
	var s := backdrop_set
	var b: Rect2 = _room.get("bounds")
	var floor_y := b.end.y - 96.0
	for i in s.shaft_count:
		var wide := b.size.y > 500.0 and i % 2 == 1
		var x := b.position.x + (i + 0.5) / float(s.shaft_count) * b.size.x + _fx_rng.randf_range(-60.0, 60.0)
		var h := 200.0 if wide else 160.0
		var shaft := LightShaft.create(wide, Vector2(x, floor_y - h - 8.0), s.shaft_color, _fx_rng.randf_range(0.0, 6.0))
		if shaft:
			_shafts.append(shaft)
			_grade_root.add_child(shaft)


func _rain_drops() -> int:
	if theme == null or not theme.rain:
		return 0
	if backdrop_set and backdrop_set.rain_override >= 0:
		return backdrop_set.rain_override
	return theme.rain_drops


func _on_settings_changed() -> void:
	if _vignette:
		_vignette.refresh()
	if _particles:
		_particles.refresh()
	if _fg_layer:
		_fg_layer.visible = Motion.animate_ambient()


# --- foreground --------------------------------------------------------------

## Foreground silhouettes (PlaneSpec.is_foreground): only where the room's
## RoomPresentation.foreground allows them, only in the top 40 px of the
## view and below the floor line, never over the player's collision band.
func _build_foreground() -> void:
	var fg := backdrop_set.foreground_planes()
	if fg.is_empty() or _room == null or not ("bounds" in _room):
		return
	var pres := PresentationIndex.for_room_node(_room)
	if pres == null or not pres.foreground:
		return
	var spec := fg[0]
	var tex := spec.load_texture()
	var data := UiKit.read_json(spec.texture_path.get_basename() + ".json")
	var regions: Array = data.get("regions", [])
	if tex == null or regions.is_empty():
		return
	var tops: Array = regions.filter(func(r: Dictionary) -> bool: return r.get("anchor", "") == "top")
	var bottoms: Array = regions.filter(func(r: Dictionary) -> bool: return r.get("anchor", "") == "bottom")
	for n in _room.find_children("*", "CeilingTracker", true, false):
		_trackers.append(n as Node2D)
	_fg_layer = CanvasLayer.new()
	_fg_layer.name = "Foreground"
	_fg_layer.layer = FOREGROUND_LAYER
	add_child(_fg_layer)
	var b: Rect2 = _room.get("bounds")
	var x := b.position.x + _fx_rng.randf_range(80.0, 200.0)
	var top_turn := true
	while x < b.end.x - 40.0:
		var pool: Array = tops if top_turn and not tops.is_empty() else bottoms
		if pool.is_empty():
			pool = tops
		var r: Dictionary = pool[_fx_rng.randi() % pool.size()]
		_add_fg_piece(tex, r, x)
		top_turn = not top_turn
		x += _fx_rng.randf_range(260.0, 420.0)
	_fg_layer.visible = Motion.animate_ambient()


func _add_fg_piece(tex: Texture2D, r: Dictionary, world_x: float) -> void:
	var rect_a: Array = r.get("rect", [0, 0, 0, 0])
	var origin: Array = r.get("origin", [0, 0])
	var rect := Rect2(rect_a[0], rect_a[1], rect_a[2], rect_a[3])
	var top: bool = r.get("anchor", "") == "top"
	if top and rect.size.y > FG_TOP_BAND:
		# Only the hanging end shows, inside the top band.
		rect = Rect2(rect.position.x, rect.end.y - FG_TOP_BAND, rect.size.x, FG_TOP_BAND)
	var node: Node2D
	var seed_value := hash(Vector2i(int(world_x), int(rect.position.x)))
	if str(r.get("name", "")).begins_with("cloth"):
		node = ClothStrip.for_region(tex, rect, seed_value)
	else:
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.centered = false
		sp.region_enabled = true
		sp.region_rect = rect
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		node = sp
	node.name = "Fg_%s" % str(r.get("name", "piece"))
	_fg_layer.add_child(node)
	var floor_y := NAN
	if not top:
		floor_y = _room_floor_at(world_x)
	_fg_pieces.append({"node": node, "world_x": world_x - float(origin[0]), "top": top, "size": rect.size, "floor": floor_y})


## The top of the solid block the room's floor is at `x` (the lowest ground
## that reaches the room's bottom edge), NAN when there is none.
func _room_floor_at(x: float) -> float:
	var b: Rect2 = _room.get("bounds")
	var best := NAN
	for n in _room.find_children("*", "GrayboxBlock", true, false):
		var g := n as GrayboxBlock
		if g.one_way:
			continue
		var r := Rect2(g.global_position - _room.global_position, g.size)
		if x >= r.position.x and x <= r.end.x and r.end.y >= b.end.y - 1.0:
			if is_nan(best) or r.position.y < best:
				best = r.position.y
	return best


func _follow_foreground(cam: Vector2, delta: float) -> void:
	if _fg_layer == null or not _fg_layer.visible:
		return
	var hazards := _hazard_screen_points()
	for p in _fg_pieces:
		var node := p["node"] as Node2D
		var size: Vector2 = p["size"]
		var sx := (float(p["world_x"]) - cam.x) * FG_MOTION + VIEW.x * 0.5
		var y := 0.0
		if not p["top"]:
			var fl: float = p["floor"]
			if is_nan(fl):
				node.visible = false
				continue
			var line := fl - cam.y + VIEW.y * 0.5
			y = maxf((fl - cam.y) * FG_MOTION + VIEW.y * 0.5, line + 2.0)
		node.position = Vector2(sx, y)
		var rect := Rect2(node.position, size)
		node.visible = rect.end.x > 0.0 and rect.position.x < VIEW.x and rect.position.y < VIEW.y
		# A floor piece never sits under the HUD, hint caption or prompt band
		# (dark silhouettes there read as a hole in the floor behind text).
		if not p["top"] and rect.end.y > VIEW.y - FG_HUD_BAND:
			node.visible = false
		var target := 1.0
		for h in hazards:
			if rect.grow(16.0).has_point(h):
				target = FG_FADE_ALPHA
				break
		node.modulate.a = move_toward(node.modulate.a, target, delta * 4.0)


## Screen points of enemies, hazards and the Collector eye (fg fades there).
func _hazard_screen_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	if _room == null:
		return out
	for g in FG_HAZARD_GROUPS:
		for n in get_tree().get_nodes_in_group(g):
			if n is Node2D and _room.is_ancestor_of(n):
				out.append((n as Node2D).get_global_transform_with_canvas().origin)
	for t in _trackers:
		if is_instance_valid(t):
			out.append(t.get_global_transform_with_canvas().origin)
	return out


# --- helpers for props -------------------------------------------------------

## Whether the room around `n` has rain (its theme rains and its backdrop
## set does not switch the rain off).
static func room_is_rainy(n: Node) -> bool:
	var r := AmbientLife.room_of(n)
	if r == null or not ("theme" in r):
		return false
	var t := r.get("theme") as DistrictTheme
	if t == null or not t.rain or t.rain_drops <= 0:
		return false
	var pres := PresentationIndex.for_room_node(r)
	var s := BackdropSet.for_kind(pres.backdrop_kind if pres else t.backdrop_kind_default)
	return s == null or s.rain_override != 0


## The nearest floor top (global y) at or below `global_point` among the
## room's GrayboxBlocks, NAN when none.
static func floor_below(n: Node, global_point: Vector2) -> float:
	var r := AmbientLife.room_of(n)
	if r == null:
		return NAN
	var best := NAN
	for c in r.find_children("*", "GrayboxBlock", true, false):
		var g := c as GrayboxBlock
		var top := g.global_position.y
		if global_point.x >= g.global_position.x and global_point.x <= g.global_position.x + g.size.x and top >= global_point.y:
			if is_nan(best) or top < best:
				best = top
	return best


# --- per frame ----------------------------------------------------------------

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
	if _procedural_skyline and _sky.visible:
		_sky.queue_redraw()
	_front.queue_redraw()
	_follow_all()
	if backdrop_set:
		_tick_train(delta)
		_tick_lightning(delta)
		_follow_foreground(_cam(), delta)


func _follow_all() -> void:
	var cam := _cam()
	var ref := _ref_y()
	for p in _planes:
		p.follow(cam, ref)
	for f in _fogs:
		f.follow(cam, ref)
	for s in _shafts:
		s.follow(cam)
	if _particles:
		_particles.follow(cam)


func _tick_train(delta: float) -> void:
	if _train == null:
		return
	if not Motion.animate_ambient():
		_train.visible = false
		return
	if _train.visible:
		_train.position.x += _train_dir * TRAIN_SPEED * delta
		if _train.position.x > VIEW.x + 8.0 or _train.position.x < -_train.texture.get_width() - 8.0:
			_train.visible = false
		return
	_train_timer -= delta
	if _train_timer > 0.0:
		return
	var s := backdrop_set
	_train_timer = _fx_rng.randf_range(s.train_period.x, s.train_period.y)
	_train_dir = 1.0 if _fx_rng.randf() < 0.5 else -1.0
	_train.flip_h = _train_dir < 0.0
	var far: ParallaxPlane = null
	for p in _planes:
		if p.motion.x > 0.0 and p.motion.x < 0.2:
			far = p
			break
	var y := far.position.y + far.tex_height() * 0.62 if far else VIEW.y * 0.5
	_train.position = Vector2(-_train.texture.get_width() - 4.0 if _train_dir > 0.0 else VIEW.x + 4.0, floorf(y))
	_train.visible = true


## Sky-only lightning: one flash every lightning_period seconds; a static
## brighter sky for 1 s under flash reduction; none at ambient motion Off.
func _tick_lightning(delta: float) -> void:
	if not backdrop_set.lightning:
		return
	if not Motion.animate_ambient():
		_flash_t = -1.0
		_flash_root.modulate = Color.WHITE
		return
	if _flash_t >= 0.0:
		_flash_t += delta
		_flash_root.modulate = lightning_tint(_flash_t, Settings.flash_reduction)
		if _flash_t > 1.0:
			_flash_t = -1.0
			_flash_root.modulate = Color.WHITE
		return
	_lightning_timer -= delta
	if _lightning_timer <= 0.0:
		_lightning_timer = _fx_rng.randf_range(backdrop_set.lightning_period.x, backdrop_set.lightning_period.y)
		_flash_t = 0.0


## The sky tint `t` seconds into a flash: two strobes and a fade, or a
## steady brighter sky under flash reduction (no strobe).
static func lightning_tint(t: float, reduced: bool) -> Color:
	if reduced:
		return FLASH_STATIC_TINT if t <= 1.0 else Color.WHITE
	if t < 0.07 or (t >= 0.14 and t < 0.24):
		return FLASH_TINT
	if t < 0.14:
		return Color.WHITE
	return FLASH_TINT.lerp(Color.WHITE, clampf((t - 0.24) / 0.5, 0.0, 1.0))


## The sky's lightning modulate right now (tests).
func sky_flash() -> Color:
	return _flash_root.modulate


func _cam() -> Vector2:
	return camera.get_screen_center_position() if camera and is_instance_valid(camera) else Vector2.ZERO


func _draw_sky() -> void:
	if theme == null:
		return
	var steps := 12
	for i in steps:
		var t := float(i) / steps
		_sky.draw_rect(Rect2(0, VIEW.y * t, VIEW.x, VIEW.y / steps + 1), theme.sky_top.lerp(theme.sky_bottom, t))
	if not _procedural_skyline:
		return
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
