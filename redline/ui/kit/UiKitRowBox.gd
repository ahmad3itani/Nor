class_name UiKitRowBox
extends StyleBox
## The focused menu row with the UI kit (T07): the tapered row bar (menu_kit
## row_bar_3slice, a mask tinted with the Palette accent at draw time, so the
## colour-blind palettes retint it) replaces the flat red highlight, and the
## 4-frame ember cursor sits just left of the row text (frame 0 held still
## under flash reduction). MenuScreen sets it as each button's focus box when
## the kit is present and high contrast is off (high contrast keeps its
## bordered accent bar, which reads without colour vision).

## Row bar opacity over the panel (the text stays readable on it).
const BAR_ALPHA := 0.55
## Cursor x from the row's left edge (it sits in the panel's inner margin).
const CURSOR_X := -4.0


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var a := UiKit.atlas("menu_kit")
	if a.is_empty() or a["fill"] == null:
		return
	var accent := Palette.color(&"accent")
	var bar_src := UiKit.region("menu_kit", "row_bar_3slice")
	if bar_src.has_area():
		var h := bar_src.size.y
		var bar := Rect2(rect.position.x, rect.position.y + roundf((rect.size.y - h) * 0.5), rect.size.x, h)
		var m: Array = a["three"].get("row_bar_3slice", [8.0, 8.0])
		UiKit.nine_on_rid(to_canvas_item, a["fill"], bar_src, bar, [m[0], 0.0, m[1], 0.0], Color(accent, BAR_ALPHA))
	var frame := UiKit.loop_frame("menu_kit", "cursor", Time.get_ticks_msec() / 1000.0, UiKit.flash_reduced())
	var cur := UiKit.region("menu_kit", "cursor", frame)
	if cur.has_area():
		var at := Vector2(rect.position.x + CURSOR_X, rect.position.y + roundf((rect.size.y - cur.size.y) * 0.5))
		RenderingServer.canvas_item_add_texture_rect_region(to_canvas_item, Rect2(at, cur.size), (a["fill"] as Texture2D).get_rid(), cur, accent.lerp(Color.WHITE, 0.25))
