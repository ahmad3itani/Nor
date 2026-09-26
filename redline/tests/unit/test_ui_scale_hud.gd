extends RedlineTestCase
## M9 T12 (bible §24 scalable UI, D4 §7.4 HUD part): CombatHud scales its root
## by UiTheme.scale() and lays out from the scaled view, so at 100 / 125 /
## 150 % every element (boss bar and a hint included) stays on screen, and at
## 150 % nothing overlaps.

const HUD_PATH := "res://ui/hud/CombatHud.gd"
const VIEWPORT := Vector2(480, 270)

var _snap: Dictionary = {}


func before_each() -> void:
	_snap = snapshot_settings()


func after_each() -> void:
	restore_settings(_snap)


## The busiest HUD the Act I slice can show at once.
func _content() -> Dictionary:
	return {
		"max_health": 8, "injectors": 4,
		"core_label": "CORE 100  FLOW",
		"weapon": "Heavy Revolver", "ammo_max": 6,
		"scrap": "SCRAP 9999 +999",
		"prompt": "[E] Rest at the Anchor",
		"hint": "Hold jump longer to jump higher",
		"boss_title": "WARDEN KRAIL", "staggered": true,
		"rank": "REDLINE",
		"banner": "LOWLIGHT", "banner_sub": "Relay Concourse",
		"lore": true,
	}


func _rects_at(index: int) -> Dictionary:
	var f := Settings.config().ui_scale_factor(index)
	var hud := load(HUD_PATH) as GDScript
	return hud.call("element_rects", VIEWPORT / f, ThemeDB.fallback_font, _content())


func test_hud_rects_inside_viewport() -> void:
	var screen := Rect2(Vector2.ZERO, VIEWPORT)
	for index in 3:
		var f := Settings.config().ui_scale_factor(index)
		var rects := _rects_at(index)
		check(rects.has("boss") and rects.has("hint"), "boss bar and hint measured at %d" % index)
		for name: String in rects:
			var r: Rect2 = rects[name]
			var scaled := Rect2(r.position * f, r.size * f)
			check(screen.encloses(scaled), "%s inside the viewport at %.0f %% (%s)" % [name, f * 100.0, scaled])
	# The default layout is the M8 one: bottom-centre boss bar.
	var hud := load(HUD_PATH) as GDScript
	var m8: Dictionary = hud.call("layout", VIEWPORT)
	check(not m8["compact"] and (m8["boss_bar"] as Rect2).position.y == VIEWPORT.y - 22, "100 %% keeps the M8 boss bar")
	check((m8["rank"] as Vector2) == Vector2(VIEWPORT.x - 70, 22), "100 %% keeps the M8 rank corner")


func test_hud_elements_do_not_overlap_at_150() -> void:
	var rects := _rects_at(2)
	var names: Array = rects.keys()
	# The fragment card and the room banner are both short announcements
	# that never share a moment (entry vs pickup), so that pair may touch.
	var allowed := [["banner", "lore"], ["lore", "banner"]]
	for i in names.size():
		for j in range(i + 1, names.size()):
			if allowed.has([names[i], names[j]]):
				continue
			# Text boxes use the font's full line box (ascent + descent): the
			# M8 bottom rows (Core label over the weapon row) share 1 px of
			# empty descender space, which is not a visible overlap.
			var a: Rect2 = (rects[names[i]] as Rect2).grow(-1.0)
			var b: Rect2 = (rects[names[j]] as Rect2).grow(-1.0)
			check(not a.intersects(b), "%s %s overlaps %s %s at 150 %%" % [names[i], a, names[j], b])


func test_hud_root_follows_ui_scale() -> void:
	var hud: CanvasLayer = (load(HUD_PATH) as GDScript).new()
	add_child(hud)
	for index in 3:
		Settings.ui_scale = index
		var f := Settings.config().ui_scale_factor(index)
		await get_tree().process_frame
		var root: Control = hud.get("_root")
		check(root.scale.is_equal_approx(Vector2(f, f)), "HUD root scale %.2f at index %d" % [f, index])
		var view: Vector2 = hud.call("view_size")
		check(view.is_equal_approx(hud.get_viewport().get_visible_rect().size / f), "layout space is the view / scale")
		check(root.size.is_equal_approx(view), "HUD root spans the scaled view")
	hud.queue_free()
