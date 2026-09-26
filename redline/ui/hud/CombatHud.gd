extends CanvasLayer
## Minimal combat HUD (bible §27): health pips, Redline Core bar, ranged
## weapon + ammo, style rank. Critical core pulses the bar and a vignette
## (static when Settings.flash_reduction is on). Native-resolution layer.
##
## M9 (T12, bible §24, D4 §7):
## - colours come from Palette (accent, heal, ammo, currency); the constants
##   below are the default-palette values, so the default look is unchanged;
## - shape cues, always on: an empty injector is a hollow box, never only a
##   dimmer one;
## - high contrast: white 1 px outlines on pips, the Core bar and ammo ticks;
##   every empty pip is hollow; the hint and fragment cards are opaque;
## - flash reduction: the style-rank flash is off (the rank swaps in place);
## - damage assist: the next pip to go is drawn at (1 - damage_carry) height
##   (PlayerCombat.damage_carry, T11), so a partial hit is visible;
## - UI scale: _root.scale = UiTheme.scale() and every right- or centre-
##   anchored element is placed from the scaled view size (layout()), with a
##   compact layout below COMPACT_WIDTH that lifts the boss bar to the top so
##   nothing overlaps at 125 % and 150 %.

const FONT_SIZE := 6
const PIP := Vector2(6, 6)
const RED := Color("e8283c")
const DIM := Color(1, 1, 1, 0.18)
## Empty pips drawn hollow (every empty injector; every empty pip in high contrast).
const HOLLOW := Color(1, 1, 1, 0.35)
const HC_OUTLINE := Color.WHITE
const HC_CARD := Color(0.04, 0.03, 0.07, 1.0)
const INJECTOR_COLOR := Color("7dff9a")
const AMMO_COLOR := Color("ffe28a")
const SCRAP_COLOR := Color("ffd36b")
## Views narrower than this (UI scale above 100 %) use the compact layout.
const COMPACT_WIDTH := 440.0
## Compact boss bar: this much room is kept free on each side (the style rank
## sits in the top-right corner).
const BOSS_SIDE_CLEAR := 78.0
const BOSS_BAR_W := 220.0

var _player: Player
var _root: Control
var _vignette: TextureRect
var _critical: bool = false
var _time: float = 0.0
var _rank_flash: float = 0.0
var _prompt: String = ""
var _hint: String = ""
var _hint_time: float = 0.0
## Hints queue instead of overwriting (bible §42: a lesson line nobody can
## read teaches nothing). A newer hint waits until the current one has been
## up HINT_MIN_SECONDS (or ends); a short backlog keeps only the newest.
const HINT_MIN_SECONDS := 2.0
const HINT_QUEUE_MAX := 2
var _hint_shown: float = 0.0
var _hint_queue: Array[Array] = []
var _banner: String = ""
var _banner_sub: String = ""
var _banner_time: float = 0.0
const BANNER_SECONDS := 2.6
const LORE_SECONDS := 8.0
var _lore_title: String = ""
var _lore_text: String = ""
var _lore_time: float = 0.0
var _boss: Enemy
var _boss_title: String = ""
## Onboarding (bible §42): the Core readout stays hidden until the first Flow
## Zone explains it (flag core_hud_hidden), then fills in and names itself.
const CORE_REVEAL_SECONDS := 1.0
const CORE_ONLINE_SECONDS := 2.0
var _core_hidden: bool = false
var _core_reveal: float = 0.0
var _core_online: float = 0.0


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
	# Sized by hand (view_size()) so the UI scale can shrink the layout space.
	_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.draw.connect(_draw_hud)
	add_child(_root)
	_apply_scale()
	EventBus.player_spawned.connect(func(p: Node2D) -> void:
		_player = p as Player
		_prompt = "")
	EventBus.reactor_changed.connect(func(_c: float, _m: float, critical: bool) -> void: _critical = critical)
	EventBus.style_changed.connect(func(_p: float, _r: int) -> void: _rank_flash = 0.3)
	EventBus.interact_prompt_changed.connect(func(t: String) -> void: _prompt = t)
	EventBus.hint_requested.connect(request_hint)
	EventBus.boss_started.connect(func(b: Node2D, title: String) -> void:
		_boss = b as Enemy
		_boss_title = title)
	EventBus.boss_defeated.connect(func(_id: String) -> void: _boss = null)
	EventBus.memory_fragment_found.connect(func(f: Resource) -> void:
		var frag := f as MemoryFragmentData
		if frag:
			# M8 (D-112): the card names the memory and where it surfaces; the
			# vignette is the reveal, so the full text no longer shows here.
			var cfg := MemoryLibrary.config()
			_lore_title = "MEMORY FRAGMENT  —  " + frag.title
			_lore_text = cfg.card_body_anchor if Settings.memories_at_anchors else cfg.card_body_journal
			_lore_time = LORE_SECONDS)
	EventBus.flag_changed.connect(_on_flag_changed)
	EventBus.game_state_reset.connect(_sync_core_hidden)
	EventBus.game_state_reset.connect(clear_hints)
	_sync_core_hidden()
	EventBus.room_entered.connect(func(district: String, room_name: String) -> void:
		_banner = district.to_upper()
		_banner_sub = room_name
		_banner_time = BANNER_SECONDS if district != "" else 0.0)


## Snap to the profile without the reveal (new game, load).
func _sync_core_hidden() -> void:
	_core_hidden = Game.has_flag("core_hud_hidden")
	_core_reveal = 0.0
	_core_online = 0.0


func _on_flag_changed(id: String, _value: Variant) -> void:
	if id != "core_hud_hidden":
		return
	var hidden := Game.has_flag(id)
	if _core_hidden and not hidden:
		_core_reveal = CORE_REVEAL_SECONDS
		_core_online = CORE_ONLINE_SECONDS
	elif hidden:
		_core_reveal = 0.0
		_core_online = 0.0
	_core_hidden = hidden


## M8: while a scene hides the HUD, or a bark line sits where hints go, new
## hints queue (same de-dup and backlog rules) and appear with their full
## duration once control returns, never under a sequence.
func _hints_held() -> bool:
	return CinematicMode.hud_hidden or CinematicMode.bark_line


func request_hint(t: String, seconds: float) -> void:
	if _hint_time <= 0.0 and not _hints_held():
		_show_hint(t, seconds)
	elif t == _hint and _hint_time > 0.0:
		_hint_time = maxf(_hint_time, seconds)
	elif not _hint_queue.any(func(q: Array) -> bool: return q[0] == t):
		_hint_queue.append([t, seconds])
		while _hint_queue.size() > HINT_QUEUE_MAX:
			_hint_queue.pop_front()


func _show_hint(t: String, seconds: float) -> void:
	_hint = t
	_hint_time = seconds
	_hint_shown = 0.0


func clear_hints() -> void:
	_hint = ""
	_hint_time = 0.0
	_hint_queue.clear()


## The hint line on screen now, or "" (tests).
func current_hint() -> String:
	return _hint if _hint_time > 0.0 else ""


func _tick_hints(delta: float) -> void:
	_hint_time = maxf(_hint_time - delta, 0.0)
	_hint_shown += delta
	if not _hint_queue.is_empty() and (_hint_time <= 0.0 or _hint_shown >= HINT_MIN_SECONDS):
		var next: Array = _hint_queue.pop_front()
		_show_hint(next[0], next[1])


## Whether the Core bar and its label are drawn (tests, onboarding).
func core_bar_visible() -> bool:
	return not _core_hidden


## The HUD's layout space: the viewport divided by the UI scale.
func view_size() -> Vector2:
	var f := UiTheme.scale()
	return get_viewport().get_visible_rect().size / f if is_inside_tree() else Vector2(480, 270) / f


func _apply_scale() -> void:
	var f := UiTheme.scale()
	_root.scale = Vector2(f, f)
	_root.size = view_size()


func _process(delta: float) -> void:
	_apply_scale()
	_time += delta
	_core_reveal = maxf(_core_reveal - delta, 0.0)
	_core_online = maxf(_core_online - delta, 0.0)
	_rank_flash = maxf(_rank_flash - delta, 0.0)
	if not _hints_held():
		_tick_hints(delta)
	# A hidden HUD freezes its banner and fragment card, so they are still
	# readable when the scene hands control back.
	if not CinematicMode.hud_hidden:
		_banner_time = maxf(_banner_time - delta, 0.0)
		_lore_time = maxf(_lore_time - delta, 0.0)
	var target_alpha := 0.0
	if _critical:
		target_alpha = 0.35 if Settings.flash_reduction else 0.25 + 0.3 * (0.5 + 0.5 * sin(_time * 7.0))
	_vignette.modulate.a = lerpf(_vignette.modulate.a, target_alpha, 1.0 - exp(-8.0 * delta))
	_root.queue_redraw()


func _draw_hud() -> void:
	if CinematicMode.hud_hidden:
		return
	if _player == null or not is_instance_valid(_player):
		return
	var font := ThemeDB.fallback_font
	var view := _root.size
	var lay := layout(view)
	var base: Vector2 = lay["base"]
	var hc := UiTheme.high_contrast()
	var red := Palette.color(&"accent")

	# Health pips; the next pip to go shows the damage-assist carry.
	var combat := _player.combat
	for i in combat.config.max_health:
		var r := Rect2(base + Vector2(i * (PIP.x + 2), 0), PIP)
		var fill := pip_fill(i, combat.health, combat.damage_carry)
		if fill >= 1.0:
			_draw_pip(r, true, false, hc, red)
		else:
			_draw_pip(r, false, false, hc, red)
			if fill > 0.0:
				var h := PIP.y * fill
				_draw_pip(Rect2(r.position.x, r.end.y - h, r.size.x, h), true, false, hc, red)

	# Redline Core bar (hidden until the campaign introduces the Core).
	if core_bar_visible():
		_draw_core(font, base)

	# Ranged weapon + ammo; an empty slot (unarmed start) is a dim outline.
	var w := combat.ranged_weapon()
	var y := base.y + 21
	if w:
		var ammo := int(combat.ammo.get(w.id, 0))
		_root.draw_string(font, Vector2(base.x, y), w.display_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color("c9c3d6"))
		var ax := base.x + 62
		var ammo_col := Palette.color(&"ammo")
		for i in w.ammo_max:
			_draw_pip(Rect2(ax + i * 4, y - 5, 2, 5), i < ammo, false, hc, ammo_col)
	else:
		_root.draw_rect(Rect2(base.x, y - 6, 56, 7), HOLLOW if hc else DIM, false, 1.0)
	# The melee slot has no readout of its own; when empty, a small outline
	# after the ranged slot shows there is a second slot to fill.
	if combat.melee_weapon == null:
		_root.draw_rect(Rect2(base.x + 116, y - 6, 18, 7), HOLLOW if hc else DIM, false, 1.0)

	# Injectors (green pips after health): full = filled, empty = hollow.
	var inj_x := base.x + combat.config.max_health * (PIP.x + 2) + 6
	var heal := Palette.color(&"heal")
	for i in combat.injector_capacity():
		_draw_pip(Rect2(Vector2(inj_x + i * 5, base.y + 1), Vector2(3, 5)), i < combat.injectors, true, hc, heal)

	# Scrap (banked + unbanked, unbanked shown dimmer).
	var st := Game.state
	var scrap_text := "SCRAP %d" % st.scrap_banked
	if st.scrap_unbanked > 0:
		scrap_text += " +%d" % st.scrap_unbanked
	_root.draw_string(font, Vector2(base.x + 92 + 50, base.y + 21), scrap_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Palette.color(&"currency"))

	# Contextual prompt and hints (bottom centre).
	if _prompt != "":
		var t := "[%s] %s" % [InputGlyphs.label(&"interact"), _prompt]
		_draw_centered(font, t, lay["prompt_y"], FONT_SIZE + 1, Color.WHITE)
	if _hint_time > 0.0:
		var c := Color(1, 1, 1, clampf(_hint_time * 2.0, 0.0, 1.0))
		if hc:
			# High contrast: the hint sits on an opaque card.
			_root.draw_rect(text_rect(font, _hint, lay["hint_y"], FONT_SIZE + 1, view).grow(2.0), Color(HC_CARD, c.a))
		_draw_centered(font, _hint, lay["hint_y"], FONT_SIZE + 1, c)

	# Memory Fragment card: short, readable, never pauses play (bible §2.7 story through play).
	if _lore_time > 0.0:
		var a := clampf(minf(_lore_time, LORE_SECONDS - _lore_time) * 3.0, 0.0, 1.0)
		var card: Rect2 = lay["lore_card"]
		_root.draw_rect(card, Color(0.04, 0.03, 0.07, (1.0 if hc else 0.85) * a))
		_root.draw_rect(Rect2(card.position, Vector2(2, card.size.y)), Color(0.62, 0.85, 1.0, a))
		_root.draw_string(font, card.position + Vector2(8, 11), _lore_title, HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 12, FONT_SIZE, Color(0.62, 0.85, 1.0, a))
		_root.draw_multiline_string(font, card.position + Vector2(8, 22), _lore_text, HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 14, FONT_SIZE, -1, Color(1, 1, 1, a))

	# Boss bar (bottom centre; top centre in the compact layout), with the
	# phase-2 threshold marked.
	if _boss and is_instance_valid(_boss) and not _boss.is_dead():
		var bar_r: Rect2 = lay["boss_bar"]
		var bw := bar_r.size.x
		_draw_centered(font, _boss_title, bar_r.position.y - 3, FONT_SIZE, Color.WHITE)
		_root.draw_rect(bar_r, DIM)
		var f := clampf(_boss.health / _boss.data.max_health, 0.0, 1.0)
		_root.draw_rect(Rect2(bar_r.position, Vector2(bw * f, 4)), red)
		if hc:
			_root.draw_rect(bar_r, HC_OUTLINE, false, 1.0)
		_root.draw_rect(Rect2(bar_r.position + Vector2(bw * 0.5, -1), Vector2(1, 6)), Color.WHITE)
		if _boss.ai == Enemy.AI.STAGGER:
			_draw_centered(font, "STAGGERED", bar_r.end.y + 8, FONT_SIZE - 1, Color("ffcf5a"))
	elif _boss and (not is_instance_valid(_boss) or _boss.is_dead()):
		_boss = null

	# Room banner on entry.
	if _banner_time > 0.0:
		var a := clampf(minf(_banner_time, BANNER_SECONDS - _banner_time) * 3.0, 0.0, 1.0)
		_draw_centered(font, _banner, lay["banner_y"], 12, Color(red, a))
		_draw_centered(font, _banner_sub, lay["banner_y"] + 14, 7, Color(1, 1, 1, a))

	# Style rank (top right).
	var meter := _player.style.meter
	var rank := meter.rank_name()
	var rank_size := 16 if rank.length() <= 3 else 11
	var pos: Vector2 = lay["rank"]
	var col := Color.WHITE.lerp(red, clampf(meter.rank_index() / 7.0, 0.0, 1.0))
	if meter.points < 1.0:
		col = DIM
	col = rank_color(col, _rank_flash > 0.0, Settings.flash_reduction)
	_root.draw_string(font, pos, rank, HORIZONTAL_ALIGNMENT_LEFT, -1, rank_size, col)
	var mbar := Rect2(pos + Vector2(0, 4), Vector2(62, 2))
	_root.draw_rect(mbar, DIM)
	_root.draw_rect(Rect2(mbar.position, Vector2(mbar.size.x * meter.rank_progress(), 2)), col)
	_root.draw_string(font, pos + Vector2(0, 12), "STYLE %d" % int(meter.points), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1, Color("c9c3d6"))


## One pip or tick: the draw ops from pip_ops().
func _draw_pip(r: Rect2, full: bool, hollow_when_empty: bool, hc: bool, fill: Color) -> void:
	for op: Array in pip_ops(full, hollow_when_empty, hc, fill):
		if op[0] == &"fill":
			_root.draw_rect(r, op[1])
		else:
			_root.draw_rect(r, op[1], false, 1.0)


# --- Pure helpers (tests: test_high_contrast, test_flash_reduction, test_ui_scale_hud) ---

## How a pip draws: [[&"fill" | &"outline", Color], ...]. A full pip is
## filled (plus a white outline in high contrast); an empty one is a hollow
## box when `hollow_when_empty` (injectors) or in high contrast, else the
## faint M8 fill.
static func pip_ops(full: bool, hollow_when_empty: bool, hc: bool, fill: Color) -> Array:
	if full:
		return [[&"fill", fill], [&"outline", HC_OUTLINE]] if hc else [[&"fill", fill]]
	if hollow_when_empty or hc:
		return [[&"outline", HOLLOW]]
	return [[&"fill", DIM]]


## How much of health pip `i` is lit: 1 below the top full pip, (1 - carry)
## for the pip the next hit takes, 0 above health.
static func pip_fill(i: int, health: int, carry: float) -> float:
	if i < health - 1:
		return 1.0
	if i == health - 1:
		return clampf(1.0 - carry, 0.0, 1.0)
	return 0.0


## The rank colour: flashes white on a rank change, unless flash reduction
## is on (then the rank text just swaps in place).
static func rank_color(base: Color, flashing: bool, reduced: bool) -> Color:
	return Color.WHITE if flashing and not reduced else base


## Anchors for a layout space `view` (the viewport / UI scale). At 480 x 270
## this is exactly the M8 layout; narrower views (125 %, 150 %) are compact.
static func layout(view: Vector2) -> Dictionary:
	var compact := view.x < COMPACT_WIDTH
	var base := Vector2(6, view.y - 30)
	var hint_y := view.y - 58
	var out := {
		"compact": compact,
		"base": base,
		"prompt_y": view.y - 46,
		"hint_y": hint_y,
		"banner_y": 58.0,
		"rank": Vector2(view.x - 70, 22),
		"boss_bar": Rect2((view.x - BOSS_BAR_W) * 0.5, view.y - 22, BOSS_BAR_W, 4),
		"lore_card": Rect2(view.x * 0.5 - 150, 90, 300, 58),
	}
	if compact:
		# The bottom band belongs to the pips, Core, weapon and Scrap; the
		# boss bar moves to the top centre, clear of the style rank.
		var bw := minf(BOSS_BAR_W, view.x - 2.0 * BOSS_SIDE_CLEAR)
		out["boss_bar"] = Rect2((view.x - bw) * 0.5, 14, bw, 4)
		var cw := minf(300.0, view.x - 16.0)
		out["lore_card"] = Rect2((view.x - cw) * 0.5, minf(90.0, hint_y - 10.0 - 58.0), cw, 58)
	return out


## The box a centred line of text covers (baseline y).
static func text_rect(font: Font, text: String, y: float, size: int, view: Vector2) -> Rect2:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	return Rect2((view.x - w) * 0.5, y - font.get_ascent(size), w, font.get_ascent(size) + font.get_descent(size))


static func _left_text_rect(font: Font, text: String, at: Vector2, size: int) -> Rect2:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	return Rect2(at.x, at.y - font.get_ascent(size), w, font.get_ascent(size) + font.get_descent(size))


## Every HUD element's box in layout space for `view`, from content like the
## HUD draws it: {max_health, injectors, core_label, weapon, ammo_max, scrap,
## prompt, hint, boss_title, staggered, rank, banner, banner_sub, lore}.
## Missing keys leave that element out. Multiply by the UI scale for screen px.
static func element_rects(view: Vector2, font: Font, content: Dictionary) -> Dictionary:
	var lay := layout(view)
	var base: Vector2 = lay["base"]
	var out := {}
	var hp := int(content.get("max_health", 0))
	var inj := int(content.get("injectors", 0))
	if hp > 0:
		var right := base.x + hp * (PIP.x + 2) - 2
		if inj > 0:
			right = base.x + hp * (PIP.x + 2) + 6 + (inj - 1) * 5 + 3
		out["health"] = Rect2(base, Vector2(right - base.x, PIP.y))
	if content.has("core_label"):
		var bar := Rect2(base + Vector2(0, 9), Vector2(92, 4))
		out["core"] = bar.merge(_left_text_rect(font, content["core_label"], bar.position + Vector2(bar.size.x + 4, 5), FONT_SIZE))
	var y := base.y + 21
	if content.has("weapon"):
		var r := _left_text_rect(font, String(content["weapon"]).to_upper(), Vector2(base.x, y), FONT_SIZE)
		r = r.merge(Rect2(base.x + 62, y - 5, int(content.get("ammo_max", 0)) * 4, 5))
		out["weapon"] = r.merge(Rect2(base.x + 116, y - 6, 18, 7))
	if content.has("scrap"):
		out["scrap"] = _left_text_rect(font, content["scrap"], Vector2(base.x + 142, y), FONT_SIZE)
	if content.has("prompt"):
		out["prompt"] = text_rect(font, content["prompt"], lay["prompt_y"], FONT_SIZE + 1, view)
	if content.has("hint"):
		out["hint"] = text_rect(font, content["hint"], lay["hint_y"], FONT_SIZE + 1, view)
	if content.has("boss_title"):
		var bar_r: Rect2 = lay["boss_bar"]
		var r := bar_r.merge(text_rect(font, content["boss_title"], bar_r.position.y - 3, FONT_SIZE, view))
		r = r.merge(Rect2(bar_r.position + Vector2(bar_r.size.x * 0.5, -1), Vector2(1, 6)))
		if content.get("staggered", false):
			r = r.merge(text_rect(font, "STAGGERED", bar_r.end.y + 8, FONT_SIZE - 1, view))
		out["boss"] = r
	if content.has("rank"):
		var pos: Vector2 = lay["rank"]
		var rank: String = content["rank"]
		var size := 16 if rank.length() <= 3 else 11
		var r := _left_text_rect(font, rank, pos, size).merge(Rect2(pos + Vector2(0, 4), Vector2(62, 2)))
		out["rank"] = r.merge(_left_text_rect(font, "STYLE 9999", pos + Vector2(0, 12), FONT_SIZE - 1))
	if content.has("banner"):
		var r := text_rect(font, content["banner"], lay["banner_y"], 12, view)
		out["banner"] = r.merge(text_rect(font, content.get("banner_sub", ""), lay["banner_y"] + 14, 7, view))
	if content.has("lore"):
		out["lore"] = lay["lore_card"]
	return out


func _draw_core(font: Font, base: Vector2) -> void:
	var reactor := _player.reactor
	var bar := Rect2(base + Vector2(0, 9), Vector2(92, 4))
	var frac := reactor.charge / reactor.config.max_charge
	# First reveal: the bar visibly fills from empty over CORE_REVEAL_SECONDS.
	if _core_reveal > 0.0:
		frac *= 1.0 - _core_reveal / CORE_REVEAL_SECONDS
	var red := Palette.color(&"accent")
	var fill_color := red
	if reactor.is_critical() and reactor.in_flow() and not Settings.flash_reduction:
		fill_color = red.lerp(Color.WHITE, 0.5 + 0.5 * sin(_time * 12.0))
	_root.draw_rect(bar, DIM)
	_root.draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), fill_color)
	if UiTheme.high_contrast():
		_root.draw_rect(bar, HC_OUTLINE, false, 1.0)
	var core_label := "CORE %d%s" % [int(reactor.charge), "  FLOW" if reactor.in_flow() else ""]
	if _core_online > 0.0:
		core_label = "CORE ONLINE"
	_root.draw_string(font, bar.position + Vector2(bar.size.x + 4, 5), core_label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color.WHITE)


func _draw_centered(font: Font, text: String, y: float, size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_root.draw_string(font, Vector2((_root.size.x - w) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

