class_name UiTheme
extends RefCounted
## Shared look for menus: industrial CRT/transit signage (bible §27) in
## placeholder form. Built in code so every menu stays consistent.

const BG := Color(0.04, 0.03, 0.07, 0.94)
const PANEL := Color(0.08, 0.06, 0.12, 1.0)
const ACCENT := Color("e8283c")
const TEXT := Color("e6e2ee")
const MUTED := Color("8a8398")
const FONT_SIZE := 7

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = FONT_SIZE
	var normal := StyleBoxFlat.new()
	normal.bg_color = PANEL
	normal.set_content_margin_all(2)
	normal.content_margin_left = 5
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color(0.18, 0.06, 0.1, 1.0)
	focus.border_color = ACCENT
	focus.set_border_width_all(0)
	focus.border_width_left = 2
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.06, 0.05, 0.08, 1.0)
	for state in ["normal", "hover", "pressed"]:
		t.set_stylebox(state, "Button", normal)
	t.set_stylebox("focus", "Button", focus)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", MUTED)
	t.set_color("font_color", "Label", TEXT)
	t.set_constant("line_spacing", "Label", 0)
	var panel := StyleBoxFlat.new()
	panel.bg_color = BG
	panel.border_color = ACCENT
	panel.border_width_top = 1
	panel.set_content_margin_all(6)
	t.set_stylebox("panel", "PanelContainer", panel)
	_theme = t
	return t
