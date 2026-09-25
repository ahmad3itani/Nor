class_name MemoryTableauView
extends Control
## Draws one memory tableau (M8, placeholder art per D-026 and D-115): a
## near-black ground, shapes in three tones of memory blue, scanlines,
## neutral static crawling in from the edges, and the closing tear.
##
## Red appears only on `redacted` shapes (a face, a signature) as an
## unexplained redaction. Under Settings.flash_reduction the tear is a plain
## fade instead of a shear, flicker shapes hold still and the static is
## frozen; otherwise its noise changes at most every BURN_FRAMES frames, so
## nothing strobes.

const GROUND := Color("07090c")
const TONES: Array[Color] = [Color("2a4050"), Color("5f93b3"), Color("9fd8ff")]
const BURN := Color("c8ccd8")
const REDACT := Color("e8283c")
const BURN_FRAMES := 6
const VIEW_HALF := 240.0

var scene: MemorySceneData
var cfg: MemoryConfig
var beat: int = 0
var view_x: float = VIEW_HALF
var burn: float = 0.0
## 0..1 progress of the closing tear.
var tear: float = 0.0
var t: float = 0.0
## > 0 while the found detail glints.
var glint: float = 0.0


func setup(p_scene: MemorySceneData, p_cfg: MemoryConfig) -> void:
	scene = p_scene
	cfg = p_cfg
	beat = 0
	view_x = p_scene.start_view_x
	burn = 0.0
	tear = 0.0
	glint = 0.0
	queue_redraw()


func set_state(p_beat: int, p_view_x: float, p_burn: float, p_tear: float, p_t: float, p_glint: float = 0.0) -> void:
	beat = p_beat
	view_x = p_view_x
	burn = p_burn
	tear = p_tear
	t = p_t
	glint = p_glint
	queue_redraw()


## The tear shears the image into static unless flash reduction is on.
func uses_shear() -> bool:
	return not Settings.flash_reduction


func _offset_x() -> float:
	return _view_w() * 0.5 - view_x


func _view_w() -> float:
	return size.x if size.x > 0.0 else 480.0


func _view_h() -> float:
	return size.y if size.y > 0.0 else 270.0


## Noise bucket: frozen under flash reduction, else steps every BURN_FRAMES.
func _bucket() -> int:
	return 0 if Settings.flash_reduction else int(Engine.get_process_frames() / BURN_FRAMES)


func _draw() -> void:
	var w := _view_w()
	var h := _view_h()
	draw_rect(Rect2(0, 0, w, h), GROUND)
	if scene == null:
		return
	var ox := _offset_x()
	for i in scene.shapes.size():
		var s := scene.shapes[i]
		if s and s.visible_at(beat):
			_draw_shape(s, ox, i)
	_draw_detail(ox)
	# Every other scanline dimmed.
	for y in range(0, int(h), 2):
		draw_rect(Rect2(0, y, w, 1), Color(0, 0, 0, 0.15))
	_draw_chevrons(w, h)
	_draw_burn(burn + tear * 0.6, w, h)
	_draw_tear(w, h)


func _tone(s: MemoryShape) -> Color:
	var c := TONES[clampi(s.tone, 0, 2)]
	if s.flicker and not Settings.flash_reduction:
		c.a = 0.65 + 0.35 * sin(t * 6.0)
	return c


func _draw_shape(s: MemoryShape, ox: float, index: int) -> void:
	var c := _tone(s)
	var x := s.pos.x + ox
	var y := s.pos.y
	var box := Rect2(x - s.size.x * 0.5, y - s.size.y, s.size.x, s.size.y)
	if s.redacted:
		_draw_redacted(box, index)
		return
	match s.kind:
		MemoryShape.Kind.RECT:
			draw_rect(box, c)
		MemoryShape.Kind.POLY:
			var pts := PackedVector2Array()
			for p in s.points:
				pts.append(p + Vector2(x, y))
			if pts.size() >= 3:
				draw_colored_polygon(pts, c)
		MemoryShape.Kind.FIGURE:
			_draw_figure(s, box, c)
		MemoryShape.Kind.HAND:
			draw_rect(Rect2(box.position.x, box.position.y + box.size.y * 0.4, box.size.x, box.size.y * 0.6), c)
			for f in 3:
				draw_rect(Rect2(box.position.x + f * box.size.x / 3.0, box.position.y, maxf(1.0, box.size.x / 4.0), box.size.y * 0.45), c)
		MemoryShape.Kind.LAMP:
			var sway := 0.0 if Settings.flash_reduction else sin(t * 1.3) * 2.0
			var tip := Vector2(x + sway, y)
			draw_line(Vector2(x, y - s.size.y), tip, TONES[0], 1.0)
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-s.size.x, 0), tip + Vector2(s.size.x, 0), tip + Vector2(0, -4)]), c)
			var glow := Color(c, 0.12)
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-s.size.x, 0), tip + Vector2(s.size.x, 0), tip + Vector2(s.size.x * 5, 60), tip + Vector2(-s.size.x * 5, 60)]), glow)
		MemoryShape.Kind.RAIN:
			var n := maxi(1, int(s.size.x / 6.0))
			var c2 := Color(c, 0.45)
			for i in n:
				var rx := box.position.x + fposmod(i * 37.0, maxf(s.size.x, 1.0))
				var ry := box.position.y + fposmod(t * 140.0 + i * 23.0, maxf(s.size.y, 1.0))
				draw_rect(Rect2(rx, ry, 1, 4), c2)
		MemoryShape.Kind.BARS:
			draw_rect(Rect2(box.position.x, box.position.y, box.size.x, 2), c)
			draw_rect(Rect2(box.position.x, box.end.y - 2, box.size.x, 2), c)
			var bx := box.position.x
			while bx <= box.end.x:
				draw_rect(Rect2(bx, box.position.y, 2, box.size.y), c)
				bx += 8.0
		MemoryShape.Kind.SCRIBBLE:
			var rng := RandomNumberGenerator.new()
			rng.seed = scene.burn_seed * 131 + index
			var px := box.position.x
			var prev := Vector2(px, box.get_center().y)
			while px < box.end.x:
				px += 2.0
				var next := Vector2(px, box.position.y + rng.randf() * box.size.y)
				draw_line(prev, next, c, 1.0)
				prev = next
		MemoryShape.Kind.RAILING:
			draw_rect(Rect2(box.position.x, box.position.y, box.size.x, 2), c)
			draw_rect(Rect2(box.position.x, box.position.y + box.size.y * 0.5, box.size.x, 1), c)
			var rx2 := box.position.x
			while rx2 <= box.end.x:
				draw_rect(Rect2(rx2, box.position.y, 2, box.size.y), c)
				rx2 += 16.0


## Blocky silhouettes (no portraits until final art, bible §39).
func _draw_figure(s: MemoryShape, box: Rect2, c: Color) -> void:
	match s.pose:
		MemoryShape.Pose.LIE:
			var head := box.size.y
			var body := Rect2(box.position.x, box.position.y + box.size.y * 0.3, box.size.x - head, box.size.y * 0.7)
			if s.facing < 0:
				body.position.x += head
			draw_rect(body, c)
			var hx := box.end.x - head if s.facing >= 0 else box.position.x
			draw_rect(Rect2(hx, box.position.y, head, head), c)
		MemoryShape.Pose.SIT:
			var hs := box.size.x * 0.7
			draw_rect(Rect2(box.position.x, box.position.y + hs, box.size.x, box.size.y - hs - 3), c)
			draw_rect(Rect2(box.get_center().x - hs * 0.5, box.position.y, hs, hs), c)
			draw_rect(Rect2(box.position.x + (box.size.x if s.facing > 0 else -4.0), box.end.y - 4, 4, 4), c)
		_:
			var hs2 := box.size.x * 0.75
			draw_rect(Rect2(box.get_center().x - hs2 * 0.5, box.position.y, hs2, hs2), c)
			draw_rect(Rect2(box.position.x, box.position.y + hs2 + 1, box.size.x, box.size.y - hs2 - 1), c)
			if s.pose == MemoryShape.Pose.REACH:
				var ax := box.end.x if s.facing > 0 else box.position.x - 8.0
				draw_rect(Rect2(ax, box.position.y + hs2 + 3, 8, 2), c)


## A redaction: red static clusters that never settle into an image.
func _draw_redacted(box: Rect2, index: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = scene.burn_seed * 977 + index * 31 + _bucket()
	var y := box.position.y
	while y < box.end.y:
		var x := box.position.x
		while x < box.end.x:
			if rng.randf() < 0.7:
				draw_rect(Rect2(x, y, 2, 2), Color(REDACT, 0.55 + rng.randf() * 0.45))
			x += 2.0
		y += 2.0


func _draw_detail(ox: float) -> void:
	if not scene.has_detail():
		return
	var gx := scene.detail_x + ox
	var gy := 140.0
	# The glint sits on the first shape authored at the detail's x.
	for s in scene.shapes:
		if s and is_equal_approx(s.pos.x, scene.detail_x):
			gy = s.pos.y - s.size.y - 3.0
			break
	if glint > 0.0:
		var a := clampf(glint, 0.0, 1.0)
		draw_rect(Rect2(gx - 4, gy, 9, 1), Color(TONES[2], a))
		draw_rect(Rect2(gx, gy - 4, 1, 9), Color(TONES[2], a))
	elif beat >= scene.detail_from_beat and gx > 0.0 and gx < _view_w():
		# A faint shimmer once the spot is on screen (never a flash).
		var a2 := 0.18 if Settings.flash_reduction else 0.12 + 0.08 * sin(t * 2.0)
		draw_rect(Rect2(gx, gy, 1, 1), Color(TONES[2], a2))


## "‹" / "›" at an edge with more tableau beyond it.
func _draw_chevrons(w: float, h: float) -> void:
	if scene.tableau_width <= int(VIEW_HALF * 2.0):
		return
	var f := ThemeDB.fallback_font
	var a := 0.4 if Settings.flash_reduction else 0.3 + 0.15 * sin(t * 2.0)
	if view_x > VIEW_HALF + 1.0:
		draw_string(f, Vector2(4, h * 0.5), "‹", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(TONES[2], a))
	if view_x < scene.max_view_x() - 1.0:
		draw_string(f, Vector2(w - 10, h * 0.5), "›", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(TONES[2], a))


## Neutral static from the frame edges at `amount` (0..1), in clusters.
func _draw_burn(amount: float, w: float, h: float) -> void:
	if amount <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = scene.burn_seed + _bucket() * 7919
	var count := int(clampf(amount, 0.0, 1.0) * 260.0)
	var reach := 20.0 + amount * 120.0
	for i in count:
		var depth := rng.randf() * rng.randf() * reach
		var along := rng.randf()
		var p: Vector2
		match rng.randi() % 4:
			0:
				p = Vector2(depth, along * h)
			1:
				p = Vector2(w - depth, along * h)
			2:
				p = Vector2(along * w, depth)
			_:
				p = Vector2(along * w, h - depth)
		var cw := float(1 + rng.randi() % 3)
		draw_rect(Rect2(p, Vector2(cw, 1 + rng.randi() % 2)), Color(BURN, 0.25 + rng.randf() * 0.5))


func _draw_tear(w: float, h: float) -> void:
	if tear <= 0.0:
		return
	if uses_shear():
		var rng := RandomNumberGenerator.new()
		rng.seed = scene.burn_seed * 3 + _bucket()
		var y := 0.0
		while y < h:
			var band := 2.0 + float(rng.randi() % 6)
			var shift := (rng.randf() - 0.5) * tear * 120.0
			draw_rect(Rect2(shift, y, w, band), Color(0, 0, 0, tear * 0.6))
			if rng.randf() < tear:
				draw_rect(Rect2(rng.randf() * w, y, 10 + rng.randf() * 60.0 * tear, 1), Color(BURN, 0.6))
			y += band
	draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, clampf(tear, 0.0, 1.0)))
