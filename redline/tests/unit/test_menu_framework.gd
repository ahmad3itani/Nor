extends RedlineTestCase
## M9 T03 (D4 §3.3, §7.2, §7.4, §8.7): the MenuScreen framework every later
## menu builds on: option rows, the scroll area, pause restore, the theme
## cache and the scaled panel width.

const TMP := "user://test_menu_framework.cfg"

var _snap: Dictionary = {}


## A node that owns a pause (what DialogueBox becomes in T11).
class FakePauseOwner extends Node:
	var owning: bool = true

	func owns_pause() -> bool:
		return owning


func before_each() -> void:
	_snap = snapshot_settings()
	Settings.remove_settings_files(TMP)
	Settings.load_settings(TMP)
	Settings.high_contrast = false
	Settings.ui_scale = 0
	UiTheme.invalidate()


func after_each() -> void:
	get_tree().paused = false
	Settings.remove_settings_files(TMP)
	restore_settings(_snap)
	UiTheme.invalidate()


func _menu() -> MenuScreen:
	var m := MenuScreen.new()
	add_child(m)
	return m


func _settings_menu() -> MenuScreen:
	var m: MenuScreen = load("res://ui/menus/SettingsMenu.gd").new()
	add_child(m)
	return m


func test_close_restores_prior_paused_state() -> void:
	var owner_node := FakePauseOwner.new()
	add_child(owner_node)
	owner_node.add_to_group(MenuScreen.PAUSE_OWNERS)
	get_tree().paused = true
	var m := _menu()
	m.open_menu()
	check(get_tree().paused, "paused while open")
	m.close_menu()
	check(get_tree().paused, "a menu over a paused dialogue leaves it paused (D-159)")
	owner_node.owning = false
	m.open_menu()
	m.close_menu()
	check(not get_tree().paused, "no owner left: the world resumes")
	get_tree().paused = false
	m.open_menu()
	m.close_menu()
	check(not get_tree().paused, "opened unpaused, closes unpaused")
	owner_node.queue_free()
	m.queue_free()


func test_menu_hop_still_unpauses() -> void:
	var pause_menu := _menu()
	var settings := _settings_menu()
	get_tree().paused = false
	pause_menu.open_menu()
	# PauseMenu._open: close first, then the next menu opens.
	pause_menu.close_menu()
	settings.open_menu()
	check(get_tree().paused, "settings pauses")
	settings.close_menu()
	check(not get_tree().paused, "pause -> settings -> close ends unpaused")
	pause_menu.queue_free()
	settings.queue_free()


func test_option_row_left_right_no_focus_jump() -> void:
	var m := _menu()
	m.open_menu()
	var calls: Array = []
	var a := m.add_option_row("A: 1", func() -> void: calls.append("confirm"),
		func() -> void: calls.append("left"), func() -> void: calls.append("right"))
	m.add_option_row("B: 1", func() -> void: pass, func() -> void: pass, func() -> void: pass)
	m.add_button("Back", func() -> void: pass)
	await get_tree().process_frame
	a.grab_focus()
	for action: StringName in [&"ui_right", &"ui_left", &"ui_right"]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = true
		get_viewport().push_input(ev)
		var up := InputEventAction.new()
		up.action = action
		get_viewport().push_input(up)
	check(calls == ["right", "left", "right"], "left/right reach the row (%s)" % str(calls))
	check(a.has_focus(), "focus stayed on the row")
	a.pressed.emit()
	check(calls.back() == "confirm", "confirm cycles")
	check(a.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "rows ellipsize instead of widening the panel")
	m.close_menu()
	m.queue_free()


func test_default_theme_identical_to_m8() -> void:
	var t := UiTheme.get_theme()
	check(t.default_font_size == 7, "font size 7")
	check(t.get_color("font_color", "Button") == Color("e6e2ee"), "button text")
	check(t.get_color("font_focus_color", "Button") == Color.WHITE, "focus text")
	check(t.get_color("font_disabled_color", "Button") == Color("8a8398"), "disabled text")
	check(t.get_color("font_color", "Label") == Color("e6e2ee"), "label text")
	check(t.get_constant("line_spacing", "Label") == 0, "line spacing")
	var normal := t.get_stylebox("normal", "Button") as StyleBoxFlat
	check(normal.bg_color == Color(0.08, 0.06, 0.12, 1.0) and normal.content_margin_left == 5 and normal.content_margin_top == 2, "normal row")
	var focus := t.get_stylebox("focus", "Button") as StyleBoxFlat
	check(focus.bg_color == Color(0.18, 0.06, 0.1, 1.0) and focus.border_color == Color("e8283c"), "focus colours")
	check(focus.border_width_left == 2 and focus.border_width_right == 0, "focus bar on the left only")
	var disabled := t.get_stylebox("disabled", "Button") as StyleBoxFlat
	check(disabled.bg_color == Color(0.06, 0.05, 0.08, 1.0), "disabled row")
	var panel := t.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	check(panel.bg_color == Color(0.04, 0.03, 0.07, 0.94) and panel.border_width_top == 1 and panel.content_margin_top == 6, "panel")
	check(UiTheme.get_theme() == t, "cached")
	UiTheme.invalidate()
	check(UiTheme.get_theme() != t, "invalidate drops the cache")
	check(UiTheme.font_size() == 7 and UiTheme.font_size(2) == 9, "font_size at 100 %")
	Settings.ui_scale = 2
	check(UiTheme.font_size() == 11 and is_equal_approx(UiTheme.scale(), 1.5), "150 %")
	check(UiTheme.font() is FontVariation, "one UI font")


func test_hc_theme_focus_not_colour_only() -> void:
	Settings.high_contrast = true
	UiTheme.invalidate()
	var t := UiTheme.get_theme()
	var focus := t.get_stylebox("focus", "Button") as StyleBoxFlat
	check(focus.border_width_left == 2 and focus.border_width_right == 2, "borders on both sides")
	check(focus.bg_color == UiTheme.ACCENT, "accent fill")
	check((t.get_stylebox("panel", "PanelContainer") as StyleBoxFlat).bg_color.a == 1.0, "opaque panel")
	check(t.get_color("font_color", "Button") == Color.WHITE and t.get_color("font_disabled_color", "Button") == Color("c8c2d6"), "HC text")
	var m := _menu()
	m.open_menu()
	var b := m.add_button("Locked row", func() -> void: pass, Callable(), false)
	check(b.text.begins_with(UiTheme.DISABLED_PREFIX), "disabled rows are marked in text")
	var l := m.add_label("note", UiTheme.MUTED)
	check(l.get_theme_color("font_color") == UiTheme.HC_MUTED, "muted text brightens")
	m.close_menu()
	m.queue_free()


func test_panel_width_clamped() -> void:
	var m := _menu()
	m.open_menu()
	check(m._panel.custom_minimum_size.x == 360.0, "M8 width at 100 %")
	m.close_menu()
	Settings.ui_scale = 1
	m.open_menu()
	check(m._panel.custom_minimum_size.x == 400.0, "125 % width from data")
	m.close_menu()
	Settings.ui_scale = 2
	m.open_menu()
	check(m._panel.custom_minimum_size.x == 460.0, "150 % width from data")
	m.close_menu()
	var wide := _menu()
	wide._panel.custom_minimum_size = Vector2(456, 0)
	wide.open_menu()
	check(wide._panel.custom_minimum_size.x == 480.0 - 16.0, "a wide screen at 150 %% clamps to the viewport (%.0f)" % wide._panel.custom_minimum_size.x)
	wide.close_menu()
	m.queue_free()
	wide.queue_free()


func test_open_count() -> void:
	var base := MenuScreen.open_count
	var a := _menu()
	var b := _menu()
	a.open_menu()
	check(MenuScreen.open_count == base + 1, "one open")
	a.open_menu()
	check(MenuScreen.open_count == base + 1, "re-opening does not double count")
	b.open_menu()
	check(MenuScreen.open_count == base + 2, "two open")
	b.close_menu()
	a.close_menu()
	a.close_menu()
	check(MenuScreen.open_count == base, "back to the start")
	a.open_menu()
	a.free()
	check(MenuScreen.open_count == base, "a screen freed while open does not leak the count")
	b.queue_free()


func test_content_height_detects_overflow() -> void:
	var m := _menu()
	m.open_menu()
	for i in 40:
		m.add_button("Row %d" % i, func() -> void: pass)
	var menu_h := await menu_height(m)
	var content_h := await content_height(m)
	var panel_h := await panel_height(m)
	check(menu_h > 270.0 and content_h > 270.0, "40 rows overflow (%.0f / %.0f)" % [menu_h, content_h])
	check(panel_h <= Settings.config().menu_max_height + 12.0 and panel_h <= 270.0, "the panel is capped and scrolls (%.0f)" % panel_h)
	m.focus_index(39)
	await get_tree().process_frame
	await get_tree().process_frame
	var last := m._body.get_child(39) as Control
	var view := m._scroll.get_global_rect()
	check(view.grow(1.0).encloses(last.get_global_rect()), "follow_focus scrolled the last row into view")
	m.close_menu()
	m.queue_free()


func test_menu_height_is_content_height_panel_height_is_capped() -> void:
	var m := _menu()
	m.open_menu()
	for i in 5:
		m.add_button("Row %d" % i, func() -> void: pass)
	var menu_h := await menu_height(m)
	var content_h := await content_height(m)
	var panel_h := await panel_height(m)
	check(is_equal_approx(menu_h, content_h), "menu_height is the content height")
	check(absf(panel_h - content_h) <= 1.0, "a short page does not scroll: panel == content (%.1f vs %.1f)" % [panel_h, content_h])
	m.close_menu()
	m.queue_free()


func test_focused_option_row_keeps_label_value_prefix() -> void:
	var s := _settings_menu()
	s.open_menu()
	s._go(&"visual")
	await get_tree().process_frame
	var rows := _buttons(s)
	var shake := _find(rows, "Screen shake")
	var flash := _find(rows, "Flash reduction")
	var cvd := _find(rows, "Colour-blind mode")
	check(shake != null and flash != null and cvd != null, "rows exist")
	if shake == null or flash == null or cvd == null:
		s.close_menu()
		s.queue_free()
		return
	flash.grab_focus()
	check(not shake.text.contains("◂"), "unfocused STEPS row is plain (%s)" % shake.text)
	shake.grab_focus()
	check(shake.text.begins_with("Screen shake: 100%") and shake.text.ends_with("◂ ▸"), "STEPS: suffix only (%s)" % shake.text)
	flash.grab_focus()
	check(shake.text == "Screen shake: 100%", "decoration leaves with focus")
	check(flash.text == "Flash reduction: Off", "TOGGLE never decorated (%s)" % flash.text)
	cvd.grab_focus()
	check(cvd.text == "Colour-blind mode: Off", "CHOICE never decorated (%s)" % cvd.text)
	s.close_menu()
	s.queue_free()


func _buttons(m: MenuScreen) -> Array:
	return m._body.get_children().filter(func(n: Node) -> bool: return n is Button and not n.is_queued_for_deletion())


func _find(rows: Array, prefix: String) -> Button:
	for b: Button in rows:
		if b.text.begins_with(prefix):
			return b
	return null
