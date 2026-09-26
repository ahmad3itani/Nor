class_name UiTheme
extends RefCounted
## Shared look for menus: industrial CRT/transit signage (bible §27) in
## placeholder form. Built in code so every menu stays consistent.
##
## M9 (D4 §7.2, §7.4): the theme is cached per (high contrast, UI scale) and
## dropped on settings_changed (invalidate). The default variant is exactly
## the M8 look, so tours and screenshots do not move with the options off.
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

## "hc:scale_index" -> Theme.
static var _themes: Dictionary = {}
static var _font: Font = null


## Drops the cached themes (high contrast or the UI scale changed; the
## locale's font chain in T13). Open menus pick the new one on their next open.
static func invalidate() -> void:
	_themes.clear()


static func clear_cache() -> void:
	invalidate()
	_font = null


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


## Menu font size at the current scale (delta: +2 for headings).
static func font_size(delta: int = 0) -> int:
	return roundi((FONT_SIZE + delta) * scale())


## Any authored pixel size at the current scale.
static func scaled(size: int) -> int:
	return roundi(size * scale())


## The one UI font: a variation over the engine fallback font with an empty
## fallback chain (T13 adds the locale chain here).
static func font() -> Font:
	if _font == null:
		var f := FontVariation.new()
		f.base_font = ThemeDB.fallback_font
		_font = f
	return _font


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
	var key := "%s:%d" % [hc, scale_index()]
	if _themes.has(key):
		return _themes[key]
	var t := Theme.new()
	t.default_font_size = font_size()
	var normal := StyleBoxFlat.new()
	normal.bg_color = PANEL
	normal.set_content_margin_all(2)
	normal.content_margin_left = 5
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color(0.18, 0.06, 0.1, 1.0)
	focus.border_color = ACCENT
	focus.set_border_width_all(0)
	focus.border_width_left = 2
	if hc:
		# Focus is a filled accent bar with borders on both sides, so it
		# reads without colour vision.
		focus.bg_color = ACCENT
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
	panel.border_color = ACCENT
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
