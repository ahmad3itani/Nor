extends CanvasLayer
## Minimal combat HUD (bible §27): health pips, Redline Core bar, ranged
## weapon + ammo, style rank. Critical core pulses the bar and a vignette
## (static when Settings.flash_reduction is on). Native-resolution layer.

const FONT_SIZE := 6
const PIP := Vector2(6, 6)
const RED := Color("e8283c")
const DIM := Color(1, 1, 1, 0.18)

var _player: Player
var _root: Control
var _vignette: TextureRect
var _critical: bool = false
var _time: float = 0.0
var _rank_flash: float = 0.0
var _prompt: String = ""
var _hint: String = ""
var _hint_time: float = 0.0
var _banner: String = ""
var _banner_sub: String = ""
var _banner_time: float = 0.0
const BANNER_SECONDS := 2.6
const LORE_SECONDS := 8.0
var _lore_title: String = ""
var _lore_text: String = ""
var _lore_time: float = 0.0


func _ready() -> void:
	layer = 50
	_vignette = TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.add_point(0.6, Color(0.9, 0.05, 0.15, 0.0))
	grad.set_color(grad.get_point_count() - 1, Color(0.9, 0.05, 0.15, 0.55))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.05, 1.05)
	tex.width = 128
	tex.height = 72
	_vignette.texture = tex
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	add_child(_vignette)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.draw.connect(_draw_hud)
	add_child(_root)
	EventBus.player_spawned.connect(func(p: Node2D) -> void: _player = p as Player)
	EventBus.reactor_changed.connect(func(_c: float, _m: float, critical: bool) -> void: _critical = critical)
	EventBus.style_changed.connect(func(_p: float, _r: int) -> void: _rank_flash = 0.3)
	EventBus.interact_prompt_changed.connect(func(t: String) -> void: _prompt = t)
	EventBus.hint_requested.connect(func(t: String, s: float) -> void:
		_hint = t
		_hint_time = s)
	EventBus.memory_fragment_found.connect(func(f: Resource) -> void:
		var frag := f as MemoryFragmentData
		if frag:
			_lore_title = "MEMORY FRAGMENT  —  " + frag.title
			_lore_text = frag.text
			_lore_time = LORE_SECONDS)
	EventBus.room_entered.connect(func(district: String, room_name: String) -> void:
		_banner = district.to_upper()
		_banner_sub = room_name
		_banner_time = BANNER_SECONDS if district != "" else 0.0)


func _process(delta: float) -> void:
	_time += delta
	_rank_flash = maxf(_rank_flash - delta, 0.0)
	_hint_time = maxf(_hint_time - delta, 0.0)
	_banner_time = maxf(_banner_time - delta, 0.0)
	_lore_time = maxf(_lore_time - delta, 0.0)
	var target_alpha := 0.0
	if _critical:
		target_alpha = 0.35 if Settings.flash_reduction else 0.25 + 0.3 * (0.5 + 0.5 * sin(_time * 7.0))
	_vignette.modulate.a = lerpf(_vignette.modulate.a, target_alpha, 1.0 - exp(-8.0 * delta))
	_root.queue_redraw()


func _draw_hud() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var font := ThemeDB.fallback_font
	var view := _root.size
	var base := Vector2(6, view.y - 30)

	# Health pips.
	var combat := _player.combat
	for i in combat.config.max_health:
		var r := Rect2(base + Vector2(i * (PIP.x + 2), 0), PIP)
		_root.draw_rect(r, RED if i < combat.health else DIM)

	# Redline Core bar.
	var reactor := _player.reactor
	var bar := Rect2(base + Vector2(0, 9), Vector2(92, 4))
	var frac := reactor.charge / reactor.config.max_charge
	var fill_color := RED
	if reactor.is_critical() and reactor.in_flow() and not Settings.flash_reduction:
		fill_color = RED.lerp(Color.WHITE, 0.5 + 0.5 * sin(_time * 12.0))
	_root.draw_rect(bar, DIM)
	_root.draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), fill_color)
	var core_label := "CORE %d%s" % [int(reactor.charge), "  FLOW" if reactor.in_flow() else ""]
	_root.draw_string(font, bar.position + Vector2(bar.size.x + 4, 5), core_label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color.WHITE)

	# Ranged weapon + ammo.
	var w := combat.ranged_weapon()
	if w:
		var ammo := int(combat.ammo.get(w.id, 0))
		var y := base.y + 21
		_root.draw_string(font, Vector2(base.x, y), w.display_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color("c9c3d6"))
		var ax := base.x + 62
		for i in w.ammo_max:
			_root.draw_rect(Rect2(ax + i * 4, y - 5, 2, 5), Color("ffe28a") if i < ammo else DIM)

	# Injectors (green pips after health).
	var inj_x := base.x + combat.config.max_health * (PIP.x + 2) + 6
	for i in combat.injector_capacity():
		_root.draw_rect(Rect2(Vector2(inj_x + i * 5, base.y + 1), Vector2(3, 5)), Color("7dff9a") if i < combat.injectors else DIM)

	# Scrap (banked + unbanked, unbanked shown dimmer).
	var st := Game.state
	var scrap_text := "SCRAP %d" % st.scrap_banked
	if st.scrap_unbanked > 0:
		scrap_text += " +%d" % st.scrap_unbanked
	_root.draw_string(font, Vector2(base.x + 92 + 50, base.y + 21), scrap_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color("ffd36b"))

	# Contextual prompt and hints (bottom centre).
	if _prompt != "":
		var t := "[%s] %s" % [InputGlyphs.label(&"interact"), _prompt]
		_draw_centered(font, t, view.y - 46, FONT_SIZE + 1, Color.WHITE)
	if _hint_time > 0.0:
		var c := Color(1, 1, 1, clampf(_hint_time * 2.0, 0.0, 1.0))
		_draw_centered(font, _hint, view.y - 58, FONT_SIZE + 1, c)

	# Memory Fragment card: short, readable, never pauses play (bible §2.7 story through play).
	if _lore_time > 0.0:
		var a := clampf(minf(_lore_time, LORE_SECONDS - _lore_time) * 3.0, 0.0, 1.0)
		var card := Rect2(view.x * 0.5 - 150, 90, 300, 58)
		_root.draw_rect(card, Color(0.04, 0.03, 0.07, 0.85 * a))
		_root.draw_rect(Rect2(card.position, Vector2(2, card.size.y)), Color(0.62, 0.85, 1.0, a))
		_root.draw_string(font, card.position + Vector2(8, 11), _lore_title, HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 12, FONT_SIZE, Color(0.62, 0.85, 1.0, a))
		_root.draw_multiline_string(font, card.position + Vector2(8, 22), _lore_text, HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 14, FONT_SIZE, -1, Color(1, 1, 1, a))

	# Room banner on entry.
	if _banner_time > 0.0:
		var a := clampf(minf(_banner_time, BANNER_SECONDS - _banner_time) * 3.0, 0.0, 1.0)
		_draw_centered(font, _banner, 58, 12, Color(RED, a))
		_draw_centered(font, _banner_sub, 72, 7, Color(1, 1, 1, a))

	# Style rank (top right).
	var meter := _player.style.meter
	var rank := meter.rank_name()
	var rank_size := 16 if rank.length() <= 3 else 11
	var pos := Vector2(view.x - 70, 22)
	var col := Color.WHITE.lerp(RED, clampf(meter.rank_index() / 7.0, 0.0, 1.0))
	if meter.points < 1.0:
		col = DIM
	if _rank_flash > 0.0:
		col = Color.WHITE
	_root.draw_string(font, pos, rank, HORIZONTAL_ALIGNMENT_LEFT, -1, rank_size, col)
	var mbar := Rect2(pos + Vector2(0, 4), Vector2(62, 2))
	_root.draw_rect(mbar, DIM)
	_root.draw_rect(Rect2(mbar.position, Vector2(mbar.size.x * meter.rank_progress(), 2)), col)
	_root.draw_string(font, pos + Vector2(0, 12), "STYLE %d" % int(meter.points), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1, Color("c9c3d6"))


func _draw_centered(font: Font, text: String, y: float, size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_root.draw_string(font, Vector2((_root.size.x - w) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

