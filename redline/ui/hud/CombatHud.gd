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
##
## Localization (D5 §3.4, §4.2, D-162): the HUD stores SOURCE text (room and
## district names, the boss title, the fragment) and translates in _draw, so a
## language switch shows on the next frame. Hints and the interact prompt
## arrive display-ready from their emitters; the hint queue is dropped on a
## switch (queued lines were composed in the old language). Rank letters are
## exempt (D-163).
##
## Presentation overhaul (T07): with the UI kit (assets/ui/hud_kit, boss_bar,
## style_ranks via UiKit) the pips are 7x9 ampoules that break (5 frames) when
## lost and refill (4 frames) on a heal, injectors are 4x7 syringes (empty
## ones hollow), ammo ticks 2x5, the Core sits in a 72x9 frame with a flowing
## fill (held on frame 0 under flash reduction), the boss bar is a 3-slice
## frame with a name plaque and a 50 % tick that shatters on the phase change,
## and the rank is a chiselled glyph. Fills are masks tinted from Palette at
## draw time. Without the kit (kit_on() false) everything draws the M9 way.

const FONT_SIZE := 6
const PIP := Vector2(6, 6)
## Ammo pips: offset from the weapon slot, and the least gap after its name.
const AMMO_X := 62.0
const AMMO_GAP := 4.0
## The empty-melee outline's offset (the weapon row ends before it).
const MELEE_SLOT_X := 116.0
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
## UI kit geometry (T07), relative to layout()["base"].
const KIT_PIP := Vector2(7, 9)
const KIT_PIP_STEP := 9.0
const KIT_PIP_Y := -4.0
## The ampoule sits at (2, 2) in its 11x15 cell (room for falling shards).
const KIT_PIP_CELL := Vector2(2, 2)
const KIT_INJ := Vector2(4, 7)
const KIT_INJ_STEP := 6.0
const KIT_INJ_GAP := 4.0
const KIT_CORE := Vector2(72, 9)
const KIT_CORE_Y := 5.0
## The Core frame's fill channel (hud_kit.json anchors).
const KIT_CORE_FILL := Rect2(10, 3, 60, 3)
## The boss frame's caps reach this far past the fill on each side.
const KIT_BOSS_CAP := 16.0
const KIT_PLAQUE_H := 9.0
## Rank glyph region offset from the rank anchor (glyph art is centred in its cell).
const KIT_RANK_OFFSET := Vector2(-8, -14)

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
## Source district and room names of the entry banner (translated at draw).
var _banner: String = ""
var _banner_sub: String = ""
var _banner_time: float = 0.0
const BANNER_SECONDS := 2.6
const LORE_SECONDS := 8.0
var _lore_title: String = ""
var _lore_text: String = ""
## The fragment the card shows: _lore_title/_lore_text are recomposed from it
## in the current language (on the event and on a locale switch).
var _lore_frag: MemoryFragmentData
var _lore_time: float = 0.0
var _boss: Enemy
## Source title (the boss_started identity payload); translated at draw.
var _boss_title: String = ""
## Onboarding (bible §42): the Core readout stays hidden until the first Flow
## Zone explains it (flag core_hud_hidden), then fills in and names itself.
const CORE_REVEAL_SECONDS := 1.0
const CORE_ONLINE_SECONDS := 2.0
var _core_hidden: bool = false
var _core_reveal: float = 0.0
var _core_online: float = 0.0
## Pip animations (kit): pip index -> [anim (&"pip_break" / &"pip_refill"), seconds].
var _pip_anims: Dictionary = {}
var _last_health: int = -1
## Boss bar (kit): the 50 % tick shattered (phase 2), and the shatter's clock.
var _phase_broken: bool = false
var _shatter_t: float = -1.0


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
		_prompt = ""
		_pip_anims.clear()
		_last_health = -1)
	EventBus.reactor_changed.connect(func(_c: float, _m: float, critical: bool) -> void: _critical = critical)
	EventBus.style_changed.connect(func(_p: float, _r: int) -> void: _rank_flash = 0.3)
	EventBus.interact_prompt_changed.connect(func(t: String) -> void: _prompt = t)
	EventBus.hint_requested.connect(request_hint)
	EventBus.boss_started.connect(func(b: Node2D, title: String) -> void:
		_boss = b as Enemy
		_boss_title = title
		_phase_broken = false
		_shatter_t = -1.0)
	EventBus.boss_phase_changed.connect(_on_boss_phase_changed)
	EventBus.boss_defeated.connect(func(_id: String) -> void: _boss = null)
	EventBus.memory_fragment_found.connect(func(f: Resource) -> void:
		var frag := f as MemoryFragmentData
		if frag:
			_lore_frag = frag
			_compose_lore()
			_lore_time = LORE_SECONDS)
	EventBus.locale_changed.connect(_on_locale_changed)
	EventBus.flag_changed.connect(_on_flag_changed)
	EventBus.game_state_reset.connect(_sync_core_hidden)
	EventBus.game_state_reset.connect(clear_hints)
	_sync_core_hidden()
	EventBus.room_entered.connect(func(district: String, room_name: String) -> void:
		_banner = district
		_banner_sub = room_name
		_banner_time = BANNER_SECONDS if district != "" else 0.0)


## M8 (D-112): the card names the memory and where it surfaces; the vignette
## is the reveal, so the full text does not show here.
func _compose_lore() -> void:
	if _lore_frag == null:
		return
	var cfg := MemoryLibrary.config()
	_lore_title = Loc.f("MEMORY FRAGMENT  —  {title}", {"title": Loc.t(_lore_frag.title)})
	_lore_text = Loc.t(cfg.card_body_anchor if Settings.memories_at_anchors else cfg.card_body_journal)


## A language switch: the card is recomposed, and queued hints (composed in
## the old language) are dropped; the one on screen runs out.
func _on_locale_changed(_code: String) -> void:
	_compose_lore()
	_hint_queue.clear()


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
	_tick_kit(delta)
	_root.queue_redraw()


## Whether the HUD draws with the UI kit (T07); false = the M9 flat look.
static func kit_on() -> bool:
	return UiKit.has_atlas("hud_kit")


## Pip break / refill animations follow health, and the phase tick's shatter
## runs its frames (process delta: the HUD keeps its clock while paused).
func _tick_kit(delta: float) -> void:
	if _shatter_t >= 0.0:
		_shatter_t += delta
		if UiKit.once_frame("boss_bar", "tick_shatter", _shatter_t) < 0:
			_shatter_t = -1.0
	for i: int in _pip_anims.keys():
		var a: Array = _pip_anims[i]
		a[1] = float(a[1]) + delta
		if UiKit.once_frame("hud_kit", String(a[0]), a[1]) < 0:
			_pip_anims.erase(i)
	if _player == null or not is_instance_valid(_player) or _player.combat == null:
		return
	track_health(_player.combat.health)


## Starts the break animation on every pip lost since the last call and the
## refill animation on every pip gained (the first call only records).
func track_health(health: int) -> void:
	if _last_health >= 0 and health != _last_health:
		var kind := &"pip_break" if health < _last_health else &"pip_refill"
		for i in range(mini(health, _last_health), maxi(health, _last_health)):
			_pip_anims[i] = [kind, 0.0]
	_last_health = health


## [anim, frame] a pip plays now, or [] (tests, drawing).
func pip_anim(i: int) -> Array:
	if not _pip_anims.has(i):
		return []
	var a: Array = _pip_anims[i]
	return [a[0], maxi(UiKit.once_frame("hud_kit", String(a[0]), a[1]), 0)]


func _on_boss_phase_changed(boss: Node2D, _phase: int) -> void:
	if boss == _boss and not _phase_broken:
		_phase_broken = true
		_shatter_t = 0.0


## The Core fill's flow frame at time t (frame 0, still, under flash reduction).
static func core_flow_frame(t: float, reduced: bool) -> int:
	return UiKit.loop_frame("hud_kit", "core_fill_flow", t, reduced)


func _draw_hud() -> void:
	if CinematicMode.hud_hidden:
		return
	if _player == null or not is_instance_valid(_player):
		return
	var font := UiTheme.font()
	var view := _root.size
	var lay := layout(view)
	var base: Vector2 = lay["base"]
	var hc := UiTheme.high_contrast()
	var red := Palette.color(&"accent")

	# Health pips; the next pip to go shows the damage-assist carry.
	var combat := _player.combat
	var kit := kit_on()
	if kit:
		_draw_kit_pips(base, hc, red)
	for i in (0 if kit else combat.config.max_health):
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
		var wname := Loc.upper(w.display_name)
		_root.draw_string(font, Vector2(base.x, y), wname, HORIZONTAL_ALIGNMENT_LEFT, -1, fs(), Color("c9c3d6"))
		var ax := ammo_x(font, wname, base.x)
		var ammo_col := Palette.color(&"ammo")
		for i in w.ammo_max:
			if kit:
				_draw_kit_tick(Vector2(ax + i * 4, y - 5), i < ammo, hc, ammo_col)
				continue
			_draw_pip(Rect2(ax + i * 4, y - 5, 2, 5), i < ammo, false, hc, ammo_col)
	else:
		_root.draw_rect(Rect2(base.x, y - 6, 56, 7), HOLLOW if hc else DIM, false, 1.0)
	# The melee slot has no readout of its own; when empty, a small outline
	# after the ranged slot shows there is a second slot to fill.
	if combat.melee_weapon == null:
		_root.draw_rect(Rect2(base.x + MELEE_SLOT_X, y - 6, 18, 7), HOLLOW if hc else DIM, false, 1.0)

	# Injectors (green pips after health): full = filled, empty = hollow.
	var inj_x := base.x + combat.config.max_health * (PIP.x + 2) + 6
	var heal := Palette.color(&"heal")
	if kit:
		inj_x = base.x + combat.config.max_health * KIT_PIP_STEP + KIT_INJ_GAP
	for i in combat.injector_capacity():
		if kit:
			_draw_kit_injector(Vector2(inj_x + i * KIT_INJ_STEP, base.y + KIT_PIP_Y + 1), i < combat.injectors, hc, heal)
			continue
		_draw_pip(Rect2(Vector2(inj_x + i * 5, base.y + 1), Vector2(3, 5)), i < combat.injectors, true, hc, heal)

	# Scrap (banked + unbanked, unbanked shown dimmer).
	var st := Game.state
	var scrap_text := scrap_label(st.scrap_banked, st.scrap_unbanked)
	_root.draw_string(font, Vector2(base.x + 92 + 50, base.y + 21), scrap_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs(), Palette.color(&"currency"))

	# Contextual prompt and hints (bottom centre).
	if _prompt != "":
		var t := Loc.f("[{key}] {prompt}", {"key": InputGlyphs.label(&"interact"), "prompt": _prompt})
		_draw_centered(font, t, lay["prompt_y"], fs() + 1, Color.WHITE)
	if _hint_time > 0.0:
		var c := Color(1, 1, 1, clampf(_hint_time * 2.0, 0.0, 1.0))
		if hc:
			# High contrast: the hint sits on an opaque card.
			_root.draw_rect(text_rect(font, _hint, lay["hint_y"], fs() + 1, view).grow(2.0), Color(HC_CARD, c.a))
		_draw_centered(font, _hint, lay["hint_y"], fs() + 1, c)

	# Memory Fragment card: short, readable, never pauses play (bible §2.7 story through play).
	if _lore_time > 0.0:
		var a := clampf(minf(_lore_time, LORE_SECONDS - _lore_time) * 3.0, 0.0, 1.0)
		var card: Rect2 = lay["lore_card"]
		_root.draw_rect(card, Color(0.04, 0.03, 0.07, (1.0 if hc else 0.85) * a))
		_root.draw_rect(Rect2(card.position, Vector2(2, card.size.y)), Color(0.62, 0.85, 1.0, a))
		_root.draw_string(font, card.position + Vector2(8, 11), _lore_title, HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 12, fs(), Color(0.62, 0.85, 1.0, a))
		_root.draw_multiline_string(font, card.position + Vector2(8, 22), _lore_text, HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 14, fs(), -1, Color(1, 1, 1, a))

	# Boss bar (bottom centre; top centre in the compact layout), with the
	# phase-2 threshold marked.
	if _boss and is_instance_valid(_boss) and not _boss.is_dead():
		var bar_r: Rect2 = lay["boss_bar"]
		var bw := bar_r.size.x
		if kit and UiKit.has_atlas("boss_bar"):
			_draw_kit_boss(font, bar_r, hc, red)
		else:
			_draw_flat_boss(font, bar_r, bw, hc, red)
		if _boss.ai == Enemy.AI.STAGGER:
			_draw_centered(font, Loc.t("STAGGERED"), bar_r.end.y + 8, fs() - 1, Color("ffcf5a"))
	elif _boss and (not is_instance_valid(_boss) or _boss.is_dead()):
		_boss = null
	_draw_banner_and_rank(font, lay, red)


func _draw_flat_boss(font: Font, bar_r: Rect2, bw: float, hc: bool, red: Color) -> void:
	_draw_centered(font, Loc.t(_boss_title), bar_r.position.y - 3, fs(), Color.WHITE)
	_root.draw_rect(bar_r, DIM)
	var f := clampf(_boss.health / _boss.data.max_health, 0.0, 1.0)
	_root.draw_rect(Rect2(bar_r.position, Vector2(bw * f, 4)), red)
	if hc:
		_root.draw_rect(bar_r, HC_OUTLINE, false, 1.0)
	_root.draw_rect(Rect2(bar_r.position + Vector2(bw * 0.5, -1), Vector2(1, 6)), Color.WHITE)


func _draw_banner_and_rank(font: Font, lay: Dictionary, red: Color) -> void:
	# Room banner on entry.
	if _banner_time > 0.0:
		var a := clampf(minf(_banner_time, BANNER_SECONDS - _banner_time) * 3.0, 0.0, 1.0)
		_draw_centered(font, Loc.upper(_banner), lay["banner_y"], 12, Color(red, a))
		_draw_centered(font, Loc.t(_banner_sub), lay["banner_y"] + 14, 7, Color(1, 1, 1, a))

	# Style rank (top right).
	var meter := _player.style.meter
	var rank := meter.rank_name()
	var rank_size := 16 if rank.length() <= 3 else 11
	var pos: Vector2 = lay["rank"]
	var col := Color.WHITE.lerp(red, clampf(meter.rank_index() / 7.0, 0.0, 1.0))
	if meter.points < 1.0:
		col = DIM
	col = rank_color(col, _rank_flash > 0.0, Settings.flash_reduction)
	if not (kit_on() and UiKit.draw_fill(_root, "style_ranks", rank, pos + KIT_RANK_OFFSET, col)):
		_root.draw_string(font, pos, rank, HORIZONTAL_ALIGNMENT_LEFT, -1, rank_size, col)
	var mbar := Rect2(pos + Vector2(0, 4), Vector2(62, 2))
	_root.draw_rect(mbar, DIM)
	_root.draw_rect(Rect2(mbar.position, Vector2(mbar.size.x * meter.rank_progress(), 2)), col)
	_root.draw_string(font, pos + Vector2(0, 12), style_label(int(meter.points)), HORIZONTAL_ALIGNMENT_LEFT, -1, fs() - 1, Color("c9c3d6"))


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
## The HUD text size (6) with the locale's size lift (UiTheme.hud_font_size).
static func fs() -> int:
	return UiTheme.hud_font_size(FONT_SIZE)


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
		var cap := KIT_BOSS_CAP if kit_on() else 0.0
		var bw := minf(BOSS_BAR_W, view.x - 2.0 * (BOSS_SIDE_CLEAR + cap))
		out["boss_bar"] = Rect2((view.x - bw) * 0.5, 14, bw, 4)
		var cw := minf(300.0, view.x - 16.0)
		out["lore_card"] = Rect2((view.x - cw) * 0.5, minf(90.0, hint_y - 10.0 - 58.0), cw, 58)
	return out


## "SCRAP 12" / "SCRAP 12 +3" (unbanked) in the current language.
static func scrap_label(banked: int, unbanked: int) -> String:
	if unbanked > 0:
		return Loc.f("SCRAP {banked} +{unbanked}", {"banked": banked, "unbanked": unbanked})
	return Loc.f("SCRAP {banked}", {"banked": banked})


static func style_label(points: int) -> String:
	return Loc.f("STYLE {n}", {"n": points})


## "CORE 64", "CORE 64  FLOW" or "CORE ONLINE" (the first reveal).
static func core_label(charge: int, in_flow: bool, online: bool) -> String:
	if online:
		return Loc.t("CORE ONLINE")
	if in_flow:
		return Loc.f("CORE {n}  FLOW", {"n": charge})
	return Loc.f("CORE {n}", {"n": charge})


## The box a centred line of text covers (baseline y).
static func text_rect(font: Font, text: String, y: float, size: int, view: Vector2) -> Rect2:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	return Rect2((view.x - w) * 0.5, y - font.get_ascent(size), w, font.get_ascent(size) + font.get_descent(size))


## Where the ammo pips start: 62 px after the slot, or after a longer
## weapon name (a translated or pseudo-locale name never runs into the pips).
static func ammo_x(font: Font, weapon_label: String, base_x: float) -> float:
	var w := font.get_string_size(weapon_label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs()).x
	return maxf(base_x + AMMO_X, ceilf(base_x + w + AMMO_GAP))


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
	var kit := kit_on()
	if hp > 0 and kit:
		var right := base.x + hp * KIT_PIP_STEP - 2
		if inj > 0:
			right = base.x + hp * KIT_PIP_STEP + KIT_INJ_GAP + (inj - 1) * KIT_INJ_STEP + KIT_INJ.x
		out["health"] = Rect2(base + Vector2(0, KIT_PIP_Y), Vector2(right - base.x, KIT_PIP.y))
	elif hp > 0:
		var right := base.x + hp * (PIP.x + 2) - 2
		if inj > 0:
			right = base.x + hp * (PIP.x + 2) + 6 + (inj - 1) * 5 + 3
		out["health"] = Rect2(base, Vector2(right - base.x, PIP.y))
	if content.has("core_label"):
		var bar := kit_core_rect(base) if kit else Rect2(base + Vector2(0, 9), Vector2(92, 4))
		out["core"] = bar.merge(_left_text_rect(font, content["core_label"], core_label_pos(bar, kit), fs()))
	var y := base.y + 21
	if content.has("weapon"):
		var wname := Loc.upper(String(content["weapon"]))
		var r := _left_text_rect(font, wname, Vector2(base.x, y), fs())
		r = r.merge(Rect2(ammo_x(font, wname, base.x), y - 5, int(content.get("ammo_max", 0)) * 4, 5))
		out["weapon"] = r.merge(Rect2(base.x + MELEE_SLOT_X, y - 6, 18, 7))
	if content.has("scrap"):
		out["scrap"] = _left_text_rect(font, content["scrap"], Vector2(base.x + 142, y), fs())
	if content.has("prompt"):
		out["prompt"] = text_rect(font, content["prompt"], lay["prompt_y"], fs() + 1, view)
	if content.has("hint"):
		out["hint"] = text_rect(font, content["hint"], lay["hint_y"], fs() + 1, view)
	if content.has("boss_title"):
		var bar_r: Rect2 = lay["boss_bar"]
		var r := bar_r.merge(text_rect(font, content["boss_title"], bar_r.position.y - 3, fs(), view))
		r = r.merge(Rect2(bar_r.position + Vector2(bar_r.size.x * 0.5, -1), Vector2(1, 6)))
		if kit and UiKit.has_atlas("boss_bar"):
			r = r.merge(kit_boss_frame(bar_r)).merge(kit_plaque_rect(font, content["boss_title"], bar_r))
		if content.get("staggered", false):
			r = r.merge(text_rect(font, Loc.t("STAGGERED"), bar_r.end.y + 8, fs() - 1, view))
		out["boss"] = r
	if content.has("rank"):
		var pos: Vector2 = lay["rank"]
		var rank: String = content["rank"]
		var size := 16 if rank.length() <= 3 else 11
		var r := _left_text_rect(font, rank, pos, size).merge(Rect2(pos + Vector2(0, 4), Vector2(62, 2)))
		if kit and UiKit.has_region("style_ranks", rank):
			r = r.merge(Rect2(pos + KIT_RANK_OFFSET, UiKit.region("style_ranks", rank).size))
		out["rank"] = r.merge(_left_text_rect(font, style_label(9999), pos + Vector2(0, 12), fs() - 1))
	if content.has("banner"):
		var r := text_rect(font, content["banner"], lay["banner_y"], 12, view)
		out["banner"] = r.merge(text_rect(font, content.get("banner_sub", ""), lay["banner_y"] + 14, 7, view))
	if content.has("lore"):
		out["lore"] = lay["lore_card"]
	return out


## The Core frame's box (kit layout).
static func kit_core_rect(base: Vector2) -> Rect2:
	return Rect2(base + Vector2(0, KIT_CORE_Y), KIT_CORE)


## Where the Core label's baseline starts, right of the bar or frame.
static func core_label_pos(bar: Rect2, kit: bool) -> Vector2:
	return bar.position + Vector2(bar.size.x + 4, 7 if kit else 5)


## The boss bar's 3-slice frame around the fill rect.
static func kit_boss_frame(bar_r: Rect2) -> Rect2:
	return Rect2(bar_r.position + Vector2(-KIT_BOSS_CAP, -6), Vector2(bar_r.size.x + 2.0 * KIT_BOSS_CAP, 16))


## The name plaque centred above the bar, wide enough for the title.
static func kit_plaque_rect(font: Font, title: String, bar_r: Rect2) -> Rect2:
	var w := maxf(UiKit.region("boss_bar", "name_plaque").size.x, ceilf(font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs()).x) + 12.0)
	return Rect2(roundf(bar_r.get_center().x - w * 0.5), bar_r.position.y - 11, w, KIT_PLAQUE_H)


func _draw_kit_pips(base: Vector2, hc: bool, red: Color) -> void:
	var combat := _player.combat
	for i in combat.config.max_health:
		var at := base + Vector2(i * KIT_PIP_STEP, KIT_PIP_Y)
		var cell := at - KIT_PIP_CELL
		var anim := pip_anim(i)
		if not anim.is_empty():
			UiKit.draw_layered(_root, "hud_kit", String(anim[0]), cell, red, int(anim[1]))
			continue
		var fill := pip_fill(i, combat.health, combat.damage_carry)
		if fill >= 1.0:
			UiKit.draw_layered(_root, "hud_kit", "pip_full", cell, red)
			if hc:
				_root.draw_rect(Rect2(at, KIT_PIP), HC_OUTLINE, false, 1.0)
			continue
		# Empty ampoules are hollow glass (the M9 shape cue); the damage-
		# assist carry fills the next one from the bottom.
		UiKit.draw_region(_root, "hud_kit", "pip_empty", cell, 0, HC_OUTLINE if hc else Color.WHITE)
		if fill > 0.0:
			var h := ceilf(KIT_PIP.y * fill)
			var bottom := KIT_PIP_CELL.y + KIT_PIP.y
			UiKit.draw_fill(_root, "hud_kit", "pip_full", cell, red, 0, Rect2(0, bottom - h, 11, h))


func _draw_kit_injector(at: Vector2, full: bool, hc: bool, tint: Color) -> void:
	UiKit.draw_layered(_root, "hud_kit", "injector_full" if full else "injector_empty", at - Vector2.ONE, tint, 0, HC_OUTLINE if hc and not full else Color.WHITE)
	if hc and full:
		_root.draw_rect(Rect2(at, KIT_INJ), HC_OUTLINE, false, 1.0)


func _draw_kit_tick(at: Vector2, full: bool, hc: bool, tint: Color) -> void:
	UiKit.draw_layered(_root, "hud_kit", "ammo_tick_full" if full else "ammo_tick_empty", at - Vector2.ONE, tint, 0, HC_OUTLINE if hc and not full else Color.WHITE)
	if hc and full:
		_root.draw_rect(Rect2(at, Vector2(2, 5)), HC_OUTLINE, false, 1.0)


func _draw_kit_boss(font: Font, bar_r: Rect2, hc: bool, red: Color) -> void:
	var frame_tint := HC_OUTLINE if hc else Color.WHITE
	UiKit.draw_three(_root, "boss_bar", "bar_3slice", kit_boss_frame(bar_r), frame_tint)
	var f := clampf(_boss.health / _boss.data.max_health, 0.0, 1.0)
	var src := UiKit.region("boss_bar", "fill")
	var tex: Texture2D = UiKit.atlas("boss_bar")["fill"]
	if tex != null and f > 0.0:
		_root.draw_texture_rect_region(tex, Rect2(bar_r.position, Vector2(bar_r.size.x * f, src.size.y)), Rect2(src.position, Vector2(src.size.x * f, src.size.y)), red)
	# The 50 % tick (3x8) straddles the fill; its shatter (9x12) is centred on it.
	var tick := bar_r.position + Vector2(roundf(bar_r.size.x * 0.5) - 1, -2)
	if _shatter_t >= 0.0:
		var fr := UiKit.once_frame("boss_bar", "tick_shatter", _shatter_t)
		if fr >= 0:
			UiKit.draw_region(_root, "boss_bar", "tick_shatter", tick - Vector2(3, 2), fr)
	elif not _phase_broken:
		UiKit.draw_region(_root, "boss_bar", "phase_tick", tick)
	var title := Loc.t(_boss_title)
	UiKit.draw_stretched(_root, "boss_bar", "name_plaque", kit_plaque_rect(font, title, bar_r), [6.0, 0.0, 6.0, 0.0], frame_tint)
	_draw_centered(font, title, bar_r.position.y - 3, fs(), Color.WHITE)


func _draw_core(font: Font, base: Vector2) -> void:
	var reactor := _player.reactor
	var kit := kit_on()
	var bar := kit_core_rect(base) if kit else Rect2(base + Vector2(0, 9), Vector2(92, 4))
	var frac := reactor.charge / reactor.config.max_charge
	# First reveal: the bar visibly fills from empty over CORE_REVEAL_SECONDS.
	if _core_reveal > 0.0:
		frac *= 1.0 - _core_reveal / CORE_REVEAL_SECONDS
	var red := Palette.color(&"accent")
	var fill_color := red
	if reactor.is_critical() and reactor.in_flow() and not Settings.flash_reduction:
		fill_color = red.lerp(Color.WHITE, 0.5 + 0.5 * sin(_time * 12.0))
	if kit:
		var hc := UiTheme.high_contrast()
		UiKit.draw_region(_root, "hud_kit", "core_frame", bar.position, 0, HC_OUTLINE if hc else Color.WHITE)
		UiKit.draw_fill(_root, "hud_kit", "core_socket_fill", bar.position + Vector2(3, 3), fill_color)
		var flow := core_flow_frame(_time, Settings.flash_reduction)
		var w := roundf(KIT_CORE_FILL.size.x * frac)
		if w > 0.0:
			UiKit.draw_fill(_root, "hud_kit", "core_fill_flow", bar.position + KIT_CORE_FILL.position, fill_color, flow, Rect2(0, 0, w, KIT_CORE_FILL.size.y))
	else:
		_root.draw_rect(bar, DIM)
		_root.draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), fill_color)
		if UiTheme.high_contrast():
			_root.draw_rect(bar, HC_OUTLINE, false, 1.0)
	var label := core_label(int(reactor.charge), reactor.in_flow(), _core_online > 0.0)
	_root.draw_string(font, core_label_pos(bar, kit), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs(), Color.WHITE)


func _draw_centered(font: Font, text: String, y: float, size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_root.draw_string(font, Vector2((_root.size.x - w) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

