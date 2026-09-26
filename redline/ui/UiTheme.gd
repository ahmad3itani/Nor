class_name UiTheme
extends RefCounted
## Shared look for menus: industrial CRT/transit signage (bible §27) in
## placeholder form. Built in code so every menu stays consistent.
##
## M9 (D4 §7.2, §7.4): the theme is cached per (high contrast, UI scale) and
## dropped on settings_changed (invalidate). The default variant is exactly
## the M8 look, so tours and screenshots do not move with the options off.
##
## Localization (M9 D5 §10, §11): font() is the one font every text renderer
## uses (menus through the theme, HUD, subtitles, world labels), built per
## locale with that LocaleInfo's fallback chain, and every size read here is
## lifted by the locale's min_font_size. English reads exactly as before.
## High contrast never relies on colour alone: the focused row gets borders
## on both sides and disabled rows a text prefix.

const BG := Color(0.04, 0.03, 0.07, 0.94)
const PANEL := Color(0.08, 0.06, 0.12, 1.0)
const ACCENT := Color("e8283c")
const TEXT := Color("e6e2ee")
const MUTED := Color("8a8398")
const FONT_SIZE := 7
## High-contrast variants (MUTED stays >= 7:1 on BG).
const HC_TEXT := Color.WHITE
const HC_MUTED := Color("c8c2d6")
## Disabled rows in high contrast read as struck, not only dimmer.
const DISABLED_PREFIX := "— "

## "hc:scale_index:palette_mode" -> Theme.
static var _themes: Dictionary = {}
static var _font: Font = null
## Locale code _font was built for (rebuilt on a switch).
static var _font_code: String = ""


## Drops the cached themes (high contrast or the UI scale changed; the
## locale's font chain in T13). Open menus pick the new one on their next open.
static func invalidate() -> void:
	_themes.clear()


static func clear_cache() -> void:
	invalidate()
	_font = null
	_font_code = ""


static func high_contrast() -> bool:
	var s := _settings()
	return s != null and bool(s.get("high_contrast"))


static func scale_index() -> int:
	var s := _settings()
	return int(s.get("ui_scale")) if s != null else 0


## The UI scale factor (1.0 / 1.25 / 1.5 from AccessibilityConfig).
static func scale() -> float:
	var s := _settings()
	if s == null:
		return 1.0
	var cfg := s.call("config") as AccessibilityConfig
	return cfg.ui_scale_factor(int(s.get("ui_scale"))) if cfg else 1.0


## Menu font size at the current scale (delta: +2 for headings), lifted by
## the locale's size floor (font_lift).
static func font_size(delta: int = 0) -> int:
	return roundi((FONT_SIZE + delta + font_lift()) * scale())


## How many points the current locale lifts every text size (D5 §10):
## LocaleInfo.min_font_size is the floor of the body size (FONT_SIZE, 7), and
## smaller authored sizes (headers at -1/-2, the HUD's 6) rise by the same
## step, so the hierarchy holds. 0 in English and the pseudo-locale.
static func font_lift() -> int:
	return maxi(0, Loc.info().min_font_size - FONT_SIZE)


## A HUD text size (CombatHud authors 5-7 px) with the locale lift.
static func hud_font_size(base: int) -> int:
	return base + font_lift()


## Any authored pixel size at the current scale.
static func scaled(size: int) -> int:
	return roundi(size * scale())


## The one UI font (D5 §10): a variation over the engine default font whose
## fallbacks are the current locale's chain (font_chain). Built once per
## locale; a switch rebuilds it on the next read. The only place that reads
## ThemeDB.fallback_font (test_no_direct_fallback_font), besides base_font().
static func font() -> Font:
	var code := Loc.locale()
	if _font == null or _font_code != code:
		var f := FontVariation.new()
		f.base_font = base_font()
		f.fallbacks = font_chain(Loc.info())
		_font = f
		_font_code = code
	return _font


## The engine default face (Open Sans in 4.3) under every locale's chain.
static func base_font() -> Font:
	return ThemeDB.fallback_font


## A locale's fallback fonts: its bundled res:// files that exist (none ship
## in M9, D-163), then its SystemFont names (desktop only: the Web build has
## no system fonts, so coverage checks never count them).
static func font_chain(info: LocaleInfo) -> Array[Font]:
	var chain: Array[Font] = []
	if info == null:
		return chain
	for p in info.font_paths:
		if ResourceLoader.exists(p):
			var f := load(p) as Font
			if f:
				chain.append(f)
	if not info.system_fonts.is_empty():
		var sf := SystemFont.new()
		sf.font_names = info.system_fonts
		chain.append(sf)
	return chain


## TEXT / MUTED for the current contrast mode (callers that pass a colour).
static func text_color() -> Color:
	return HC_TEXT if high_contrast() else TEXT


static func muted_color() -> Color:
	return HC_MUTED if high_contrast() else MUTED


## Maps an authored label colour onto the current contrast mode.
static func label_color(c: Color) -> Color:
	if not high_contrast():
		return c
	if c == TEXT:
		return HC_TEXT
	if c == MUTED:
		return HC_MUTED
	return c


static func get_theme() -> Theme:
	var hc := high_contrast()
	# The accent comes from the colour-blind palette (T12, D4 §7.3), so the
	# palette mode is part of the key.
	# The locale is part of the key: its font chain and size floor (D5 §10).
	var key := "%s:%d:%d:%s" % [hc, scale_index(), Palette.mode(), Loc.locale()]
	if _themes.has(key):
		return _themes[key]
	var t := Theme.new()
	var accent := Palette.color(&"accent")
	t.default_font = font()
	t.default_font_size = font_size()
	var normal := StyleBoxFlat.new()
	normal.bg_color = PANEL
	normal.set_content_margin_all(2)
	normal.content_margin_left = 5
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color(0.18, 0.06, 0.1, 1.0)
	focus.border_color = accent
	focus.set_border_width_all(0)
	focus.border_width_left = 2
	if hc:
		# Focus is a filled accent bar with borders on both sides, so it
		# reads without colour vision.
		focus.bg_color = accent
		focus.border_color = HC_TEXT
		focus.border_width_right = 2
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.06, 0.05, 0.08, 1.0)
	for state in ["normal", "hover", "pressed"]:
		t.set_stylebox(state, "Button", normal)
	t.set_stylebox("focus", "Button", focus)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", HC_TEXT if hc else TEXT)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", HC_MUTED if hc else MUTED)
	t.set_color("font_color", "Label", HC_TEXT if hc else TEXT)
	t.set_constant("line_spacing", "Label", 0)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(BG.r, BG.g, BG.b, 1.0) if hc else BG
	panel.border_color = accent
	panel.border_width_top = 1
	panel.set_content_margin_all(6)
	t.set_stylebox("panel", "PanelContainer", panel)
	_themes[key] = t
	return t


## The Settings autoload read through the tree: UiTheme is compiled by
## scripts that load before Settings is ready (and by tools without it).
static func _settings() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Settings") if tree else null
