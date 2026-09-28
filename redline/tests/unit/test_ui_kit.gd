extends RedlineTestCase
## Presentation overhaul T07: the UI kit (UiKit) loads every atlas and region
## from its json; a missing kit leaves every caller on the M9 flat look; HUD
## pips break and refill, the Core flow holds still under flash reduction,
## high-contrast panels are opaque, 9-slice margins match the json, dialogue
## portraits resolve per line, and menus ask for ui_confirm / ui_back.

const HUD_PATH := "res://ui/hud/CombatHud.gd"
const MISSING_DIR := "res://assets/ui_missing_for_test"

var _snap: Dictionary = {}
var _nodes: Array[Node] = []


func before_each() -> void:
	_snap = snapshot_settings()
	UiKit.reset()
	get_tree().paused = false


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await get_tree().process_frame
	get_tree().paused = false
	UiKit.reset()
	restore_settings(_snap)


func _json(id: String) -> Dictionary:
	return UiKit.read_json("%s/%s.json" % [UiKit.DEFAULT_DIR, id])


func test_loads_every_atlas_and_region() -> void:
	for id in UiKit.ATLAS_IDS:
		check(UiKit.has_atlas(id), "atlas %s loads" % id)
		var a := UiKit.atlas(id)
		if a.is_empty():
			continue
		var size: Vector2 = (a["texture"] as Texture2D).get_size()
		var regions: Dictionary = _json(id)["regions"]
		check(not regions.is_empty(), "%s lists regions" % id)
		for rid: String in regions:
			var r := UiKit.region(id, rid)
			check(r.has_area(), "%s:%s has an area" % [id, rid])
			check(Rect2(Vector2.ZERO, size).encloses(r), "%s:%s lies inside the texture" % [id, rid])
		var frames: Dictionary = _json(id).get("frames", {})
		for anim: String in frames:
			check(UiKit.frame_count(id, anim) == (frames[anim] as Array).size(), "%s:%s frame count" % [id, anim])
			check(UiKit.region(id, anim, 1).has_area(), "%s:%s frame 1 resolves" % [id, anim])
		if _json(id).get("fill_texture") != null:
			check(a["fill"] != null, "%s has its fill mask" % id)
	check(not UiKit.title_logo().is_empty(), "the title logo and crack mask load")
	check(UiKit.used_rect("style_ranks", "D") == Rect2(8, 2, 7, 12), "a rank glyph's ink box (%s)" % UiKit.used_rect("style_ranks", "D"))


func test_missing_atlas_keeps_the_flat_look() -> void:
	UiKit.reset(MISSING_DIR, MISSING_DIR)
	for id in UiKit.ATLAS_IDS:
		check(not UiKit.has_atlas(id), "no %s from a missing folder" % id)
	check(UiKit.stylebox("menu_kit", "panel_9slice") == null, "no stylebox without the kit")
	check(UiKit.title_logo().is_empty(), "no logo without the files")
	var canvas := Control.new()
	add_child(canvas)
	_nodes.append(canvas)
	check(not UiKit.draw_region(canvas, "hud_kit", "pip_full", Vector2.ZERO), "draw_region answers false")
	check(not UiKit.draw_nine(canvas, "menu_kit", "panel_9slice", Rect2(0, 0, 40, 40)), "draw_nine answers false")
	var hud := load(HUD_PATH) as GDScript
	check(not bool(hud.call("kit_on")), "the HUD falls back to the M9 pips")
	var rects: Dictionary = hud.call("element_rects", Vector2(480, 270), ThemeDB.fallback_font, {"max_health": 5, "core_label": "CORE 10"})
	check((rects["health"] as Rect2).size.y == 6.0, "M9 6 px pips without the kit")
	check((rects["core"] as Rect2).encloses(Rect2(6, 270.0 - 30.0 + 9.0, 92, 4)), "M9 92x4 Core bar without the kit")
	check(MenuScreen.panel_box(false) == null, "menus keep the theme panel")
	# The HUD, a menu and the dialogue box draw without the kit and without errors.
	var h: CanvasLayer = hud.new()
	add_child(h)
	_nodes.append(h)
	var m := MenuScreen.new()
	add_child(m)
	_nodes.append(m)
	m.open_menu()
	m.add_label("HEADING", UiTheme.ACCENT, UiTheme.FONT_SIZE + 2)
	var b := m.add_button("Row", func() -> void: pass)
	b.grab_focus()
	await get_tree().process_frame
	check(not b.has_theme_stylebox_override("focus"), "rows keep the theme focus bar without the kit")
	check(not m._panel.has_theme_stylebox_override("panel"), "no panel override without the kit")
	m.close_menu()
	var box := DialogueBox.new()
	add_child(box)
	_nodes.append(box)
	box.open(_dialogue(["Orr"]), "Orr")
	await get_tree().process_frame
	check(box.is_open(), "the box opens without the frame kit")
	box.abort()


func test_pip_break_and_refill_step() -> void:
	var hud: CanvasLayer = (load(HUD_PATH) as GDScript).new()
	_nodes.append(hud)
	hud.call("track_health", 5)
	check((hud.call("pip_anim", 4) as Array).is_empty(), "the first reading starts nothing")
	hud.call("track_health", 3)
	check(hud.call("pip_anim", 3) == [&"pip_break", 0] and hud.call("pip_anim", 4) == [&"pip_break", 0], "two lost pips break")
	check((hud.call("pip_anim", 2) as Array).is_empty(), "a kept pip does not animate")
	hud.call("_tick_kit", 1.0 / 12.0 + 0.01)
	check(hud.call("pip_anim", 3) == [&"pip_break", 1], "break steps at 12 fps")
	hud.call("_tick_kit", 0.5)
	check((hud.call("pip_anim", 3) as Array).is_empty(), "the break ends after 5 frames")
	hud.call("track_health", 4)
	check(hud.call("pip_anim", 3) == [&"pip_refill", 0], "a healed pip refills")
	hud.call("_tick_kit", 2.0 / 12.0 + 0.01)
	check(hud.call("pip_anim", 3) == [&"pip_refill", 2], "refill steps")
	hud.call("_tick_kit", 0.5)
	check((hud.call("pip_anim", 3) as Array).is_empty(), "the refill ends after 4 frames")
	hud.free()


func test_core_fill_static_under_flash_reduction() -> void:
	var hud := load(HUD_PATH) as GDScript
	var moving := {}
	for i in 24:
		var t := i * 0.05
		check(int(hud.call("core_flow_frame", t, true)) == 0, "flash reduction holds frame 0 at %.2f" % t)
		moving[int(hud.call("core_flow_frame", t, false))] = true
	check(moving.size() == UiKit.frame_count("hud_kit", "core_fill_flow"), "the flow cycles all frames otherwise")
	check(TitleMenu_crack(0.5, true) < 0.0, "the title crack's ember rests under flash reduction")
	check(TitleMenu_crack(1.0, false) >= 0.0, "the ember crawls otherwise")


func TitleMenu_crack(t: float, reduced: bool) -> float:
	var title := load("res://ui/menus/TitleMenu.gd") as GDScript
	return float(title.call("crack_ember_x", t, reduced, 208.0))


func test_high_contrast_panels_opaque() -> void:
	var hc := MenuScreen.panel_box(true)
	var normal := MenuScreen.panel_box(false)
	check(hc != null and normal != null, "the kit panel exists")
	if hc == null or normal == null:
		return
	check(is_equal_approx(hc.modulate_color.a, 1.0), "high contrast: opaque panel")
	check(is_equal_approx(normal.modulate_color.a, UiTheme.BG.a), "default: the theme's see-through panel")
	var img := (hc.texture as Texture2D).get_image()
	var c := hc.region_rect.get_center()
	check(is_equal_approx(img.get_pixel(int(c.x), int(c.y)).a, 1.0), "the panel art's centre is opaque")
	var flat := UiTheme.get_theme().get_stylebox("panel", "PanelContainer")
	check(normal.get_margin(SIDE_LEFT) == flat.get_margin(SIDE_LEFT) and normal.get_margin(SIDE_TOP) == flat.get_margin(SIDE_TOP), "content margins match the theme (M9 geometry)")
	# High contrast keeps the bordered focus bar on rows; the default gets the row bar.
	var m := MenuScreen.new()
	add_child(m)
	_nodes.append(m)
	m.open_menu()
	var row := m.add_button("Row", func() -> void: pass)
	check(row.get_theme_stylebox("focus") is UiKitRowBox, "default rows use the kit row bar")
	Settings.high_contrast = true
	UiTheme.invalidate()
	var row_hc := m.add_button("Row HC", func() -> void: pass)
	check(not (row_hc.get_theme_stylebox("focus") is UiKitRowBox), "high-contrast rows keep the bordered bar")
	m._apply_look()
	check(is_equal_approx((m._panel.get_theme_stylebox("panel") as StyleBoxTexture).modulate_color.a, 1.0), "an open menu's panel turns opaque")
	m.close_menu()
	Settings.high_contrast = false
	UiTheme.invalidate()


func test_stylebox_margins_match_json() -> void:
	for id: String in ["menu_kit", "dialogue_frame"]:
		var nine: Dictionary = _json(id).get("nine_slice", {})
		check(not nine.is_empty(), "%s has 9-slice margins" % id)
		for rid: String in nine:
			var sb := UiKit.stylebox(id, rid)
			var m: Array = nine[rid]
			check(sb != null, "%s:%s stylebox" % [id, rid])
			if sb == null:
				continue
			check(sb.texture_margin_left == float(m[0]) and sb.texture_margin_top == float(m[1])
				and sb.texture_margin_right == float(m[2]) and sb.texture_margin_bottom == float(m[3]), "%s:%s margins %s" % [id, rid, m])
			check(sb.region_rect == UiKit.region(id, rid), "%s:%s region" % [id, rid])
			check(UiKit.stylebox(id, rid) == sb, "%s:%s is cached" % [id, rid])


## A one-line-per-speaker dialogue.
func _dialogue(speakers: Array) -> DialogueData:
	var d := DialogueData.new()
	d.id = "test_ui_kit_portraits"
	var lines: Array[DialogueLine] = []
	for s: String in speakers:
		var l := DialogueLine.new()
		l.speaker = s
		l.text = "..."
		lines.append(l)
	d.lines = lines
	return d


func _box() -> DialogueBox:
	var box := DialogueBox.new()
	add_child(box)
	_nodes.append(box)
	return box


func test_dialogue_portrait_for_orr_and_none() -> void:
	var box := _box()
	var orr := NpcProfile.find_by_display_name("Orr")
	check(orr != null and orr.portrait != null, "Orr has a portrait")
	box.open(_dialogue(["Orr"]), "Orr")
	check(box.current_portrait() != null and box.current_portrait() == orr.portrait, "Orr's line shows Orr's portrait")
	check(box.portrait_frame(box.current_portrait()) == 1, "frame 1 while the line types")
	box.shown_chars = float(box.shown_text().length())
	check(box.portrait_frame(box.current_portrait()) == 0, "frame 0 once typed")
	box.abort()
	box.open(_dialogue([""]), "")
	check(box.current_portrait() == null, "no speaker, no NPC: no portrait (subtitle-only box)")
	await get_tree().process_frame
	box.abort()


func test_dialogue_portrait_per_line_speaker() -> void:
	var box := _box()
	box.open(_dialogue(["Rook", "Krail", "", "GUARD", "Radio"]), "Mara")
	var rook := box.current_portrait()
	check(rook != null and rook.resource_path.ends_with("portrait_rook.png"), "a Rook line inside Mara's dialogue shows portrait_rook")
	await get_tree().process_frame
	box.advance()
	var krail := box.current_portrait()
	check(krail != null and krail.resource_path.ends_with("portrait_krail.png"), "Krail lines show portrait_krail")
	box.advance()
	var mara := NpcProfile.find_by_display_name("Mara")
	check(box.current_portrait() == mara.portrait, "a line without a speaker falls back to the NPC's portrait")
	box.advance()
	check(box.current_portrait() == null, "an unknown speaker shows none")
	box.advance()
	check(box.current_portrait() == null, "a profile without a portrait (Radio) shows none")
	await get_tree().process_frame
	box.abort()


func test_ui_confirm_and_back_sounds() -> void:
	var m := MenuScreen.new()
	add_child(m)
	_nodes.append(m)
	m.open_menu()
	var pressed: Array[bool] = []
	var b := m.add_button("Row", func() -> void: pressed.append(true))
	UiKit.played.clear()
	b.pressed.emit()
	check(pressed.size() == 1 and UiKit.played == [UiKit.SFX_CONFIRM], "accept plays ui_confirm then runs the row (%s)" % [UiKit.played])
	UiKit.played.clear()
	await press_action(&"ui_cancel", 1)
	await get_tree().process_frame
	check(UiKit.played.has(UiKit.SFX_BACK), "back plays ui_back (%s)" % [UiKit.played])
	check(not m.is_open(), "back still closes the menu")
