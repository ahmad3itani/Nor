class_name UiKit
extends RefCounted
## The presentation overhaul's UI kit (T07): the baked atlases in assets/ui/
## (X.png + X_fill.png tint mask + X.json regions, 9-slice / 3-slice margins,
## animation frames). Loaded once per atlas, on first use.
##
## Every call answers false / null / {} when an atlas, a region or its texture
## is missing, and callers then draw the M9 flat look (the placeholder stays
## the fallback: tests point base_dir at a missing folder).
##
## Colours are never baked: the fill masks are tinted at draw time with a
## Palette / UiTheme colour the caller passes, so the colour-blind palettes
## and high contrast retint the kit without new art.

const DEFAULT_DIR := "res://assets/ui"
const ATLAS_IDS: PackedStringArray = ["hud_kit", "menu_kit", "dialogue_frame", "boss_bar", "icons", "style_ranks"]
## Title logo pair (assets/title/, T07): white letter mask + crack mask.
const TITLE_DIR := "res://assets/title"
## UI sounds MenuScreen plays (the ids come from the SFX bank, T08).
const SFX_CONFIRM := &"ui_confirm"
const SFX_BACK := &"ui_back"

## Folder the atlases load from (tests point it at a missing folder).
static var base_dir: String = DEFAULT_DIR
## Folder the title logo loads from.
static var title_dir: String = TITLE_DIR
## atlas id -> parsed atlas ({} = missing).
static var _atlases: Dictionary = {}
## "atlas:region" -> StyleBoxTexture.
static var _styleboxes: Dictionary = {}
## Last UI sounds asked for (newest last, at most 16; tests).
static var played: Array[StringName] = []


## Drops every cached atlas and stylebox; the next read loads from `dir`.
static func reset(dir: String = DEFAULT_DIR, logo_dir: String = TITLE_DIR) -> void:
	base_dir = dir
	title_dir = logo_dir
	_atlases.clear()
	_styleboxes.clear()


## The parsed atlas: {texture, fill, regions {id: Rect2}, nine {id: [l, t, r, b]},
## three {id: [l, r]}, frames {anim: [region ids]}, fps {anim: float}, data}.
## {} when the json or the base texture is missing.
static func atlas(id: String) -> Dictionary:
	if _atlases.has(id):
		return _atlases[id]
	var a := _load_atlas(id)
	_atlases[id] = a
	return a


static func has_atlas(id: String) -> bool:
	return not atlas(id).is_empty()


static func _load_atlas(id: String) -> Dictionary:
	var json_path := "%s/%s.json" % [base_dir, id]
	var data := read_json(json_path)
	if data.is_empty():
		return {}
	var tex := _texture("%s/%s.png" % [base_dir, id])
	if tex == null:
		return {}
	var fill := _texture("%s/%s_fill.png" % [base_dir, id]) if data.get("fill_texture") != null else null
	var regions := {}
	var raw: Dictionary = data.get("regions", {})
	for rid: String in raw:
		var r: Array = raw[rid]
		if r.size() == 4:
			regions[rid] = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	var nine := {}
	var nine_raw: Dictionary = data.get("nine_slice", {})
	for rid: String in nine_raw:
		nine[rid] = (nine_raw[rid] as Array).map(func(v: Variant) -> float: return float(v))
	var three := {}
	var three_raw: Dictionary = data.get("three_slice", {})
	for rid: String in three_raw:
		three[rid] = (three_raw[rid] as Array).map(func(v: Variant) -> float: return float(v))
	var fps := {}
	var fps_raw: Dictionary = data.get("fps", {})
	for anim: String in fps_raw:
		fps[anim] = float(fps_raw[anim])
	return {
		"id": id, "texture": tex, "fill": fill, "regions": regions, "nine": nine,
		"three": three, "frames": data.get("frames", {}), "fps": fps, "data": data,
	}


## A json file as a Dictionary ({} when missing or not an object). Plain file
## read first; exported builds keep .json files as JSON resources.
static func read_json(path: String) -> Dictionary:
	var parsed: Variant = null
	if FileAccess.file_exists(path):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	elif ResourceLoader.exists(path):
		var res := load(path) as JSON
		parsed = res.data if res else null
	return parsed if parsed is Dictionary else {}


static func _texture(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## The source rect of `region_id` (a region, or an animation name with
## `frame`, which wraps). Rect2() when missing.
static func region(atlas_id: String, region_id: String, frame: int = 0) -> Rect2:
	var a := atlas(atlas_id)
	if a.is_empty():
		return Rect2()
	var frames: Dictionary = a["frames"]
	var rid := region_id
	if frames.has(region_id):
		var list: Array = frames[region_id]
		if list.is_empty():
			return Rect2()
		rid = String(list[posmod(frame, list.size())])
	return a["regions"].get(rid, Rect2())


## The painted part of a region (region-local, from the fill mask when the
## atlas has one): glyphs centred in wider cells align by their ink. Cached.
static func used_rect(atlas_id: String, region_id: String) -> Rect2:
	var a := atlas(atlas_id)
	var src := region(atlas_id, region_id)
	if a.is_empty() or not src.has_area():
		return Rect2()
	var cache: Dictionary = a.get("used", {})
	if cache.has(region_id):
		return cache[region_id]
	var tex: Texture2D = a["fill"] if a["fill"] != null else a["texture"]
	var img := tex.get_image()
	var used := Rect2(Vector2.ZERO, src.size)
	if img != null:
		if img.is_compressed():
			img.decompress()
		used = Rect2(img.get_region(Rect2i(src)).get_used_rect())
	cache[region_id] = used
	a["used"] = cache
	return used


static func has_region(atlas_id: String, region_id: String) -> bool:
	return region(atlas_id, region_id).has_area()


## Frames in an animation (0 when it is not one).
static func frame_count(atlas_id: String, anim: String) -> int:
	var a := atlas(atlas_id)
	return (a["frames"].get(anim, []) as Array).size() if not a.is_empty() else 0


static func fps(atlas_id: String, anim: String, fallback: float = 12.0) -> float:
	var a := atlas(atlas_id)
	return float(a["fps"].get(anim, fallback)) if not a.is_empty() else fallback


## The looping frame of `anim` at time `t` (seconds); frame 0 when `hold`
## (flash reduction holds every looping UI animation still).
static func loop_frame(atlas_id: String, anim: String, t: float, hold: bool = false) -> int:
	var n := frame_count(atlas_id, anim)
	if n <= 0 or hold:
		return 0
	return int(floorf(t * fps(atlas_id, anim))) % n


## The frame of a one-shot `anim` `t` seconds after it started; -1 once done.
static func once_frame(atlas_id: String, anim: String, t: float) -> int:
	var n := frame_count(atlas_id, anim)
	var f := int(floorf(t * fps(atlas_id, anim)))
	return f if f < n else -1


## Draws the base (frame) texture of a region at `pos`, modulated by `tint`.
static func draw_region(canvas: CanvasItem, atlas_id: String, region_id: String, pos: Vector2, frame: int = 0, tint: Color = Color.WHITE) -> bool:
	var a := atlas(atlas_id)
	var src := region(atlas_id, region_id, frame)
	if a.is_empty() or not src.has_area():
		return false
	canvas.draw_texture_rect_region(a["texture"], Rect2(pos, src.size), src, tint)
	return true


## Draws the tint mask of a region at `pos` in `tint`. `part` (region-local,
## empty = all) crops it: a pip's partial height, the Core ratio. Atlases
## without a fill mask (icons, rank glyphs) are masks themselves.
static func draw_fill(canvas: CanvasItem, atlas_id: String, region_id: String, pos: Vector2, tint: Color, frame: int = 0, part: Rect2 = Rect2()) -> bool:
	var a := atlas(atlas_id)
	var src := region(atlas_id, region_id, frame)
	if a.is_empty() or not src.has_area():
		return false
	var tex: Texture2D = a["fill"] if a["fill"] != null else a["texture"]
	var sub := src
	var at := pos
	if part.has_area():
		sub = Rect2(src.position + part.position, part.size).intersection(src)
		at = pos + (sub.position - src.position)
		if not sub.has_area():
			return true
	canvas.draw_texture_rect_region(tex, Rect2(at, sub.size), sub, tint)
	return true


## Frame texture, then the tinted fill mask on top (the usual kit element).
static func draw_layered(canvas: CanvasItem, atlas_id: String, region_id: String, pos: Vector2, fill_tint: Color, frame: int = 0, frame_tint: Color = Color.WHITE) -> bool:
	if not draw_region(canvas, atlas_id, region_id, pos, frame, frame_tint):
		return false
	if atlas(atlas_id)["fill"] != null:
		draw_fill(canvas, atlas_id, region_id, pos, fill_tint, frame)
	return true


## A 9-slice region stretched over `rect` (margins from the json; corners
## keep their pixels). `fill_tint` (alpha > 0) also draws the fill mask.
static func draw_nine(canvas: CanvasItem, atlas_id: String, region_id: String, rect: Rect2, tint: Color = Color.WHITE, fill_tint: Color = Color(0, 0, 0, 0)) -> bool:
	var a := atlas(atlas_id)
	var src := region(atlas_id, region_id)
	if a.is_empty() or not src.has_area():
		return false
	var m: Array = a["nine"].get(region_id, [0.0, 0.0, 0.0, 0.0])
	_nine(canvas, a["texture"], src, rect, m, tint)
	if fill_tint.a > 0.0 and a["fill"] != null:
		_nine(canvas, a["fill"], src, rect, m, fill_tint)
	return true


## A horizontal 3-slice region stretched to `rect` (caps keep their width,
## the middle stretches; the height is the rect's).
static func draw_three(canvas: CanvasItem, atlas_id: String, region_id: String, rect: Rect2, tint: Color = Color.WHITE, fill_tint: Color = Color(0, 0, 0, 0)) -> bool:
	var a := atlas(atlas_id)
	var src := region(atlas_id, region_id)
	if a.is_empty() or not src.has_area():
		return false
	var m: Array = a["three"].get(region_id, [0.0, 0.0])
	var nine := [m[0], 0.0, m[1], 0.0]
	_nine(canvas, a["texture"], src, rect, nine, tint)
	if fill_tint.a > 0.0 and a["fill"] != null:
		_nine(canvas, a["fill"], src, rect, nine, fill_tint)
	return true


## A region stretched to `rect` with explicit [left, top, right, bottom]
## caps (regions the json gives no slice margins, like the boss name plaque).
static func draw_stretched(canvas: CanvasItem, atlas_id: String, region_id: String, rect: Rect2, margins: Array, tint: Color = Color.WHITE) -> bool:
	var a := atlas(atlas_id)
	var src := region(atlas_id, region_id)
	if a.is_empty() or not src.has_area() or margins.size() != 4:
		return false
	_nine(canvas, a["texture"], src, rect, margins, tint)
	return true


## margins = [left, top, right, bottom].
static func _nine(canvas: CanvasItem, tex: Texture2D, src: Rect2, rect: Rect2, m: Array, tint: Color) -> void:
	for p: Array in nine_patches(src, rect, m):
		canvas.draw_texture_rect_region(tex, p[1], p[0], tint)


## The same patches on a raw canvas item (a StyleBox's _draw gets an RID).
static func nine_on_rid(item: RID, tex: Texture2D, src: Rect2, rect: Rect2, m: Array, tint: Color) -> void:
	for p: Array in nine_patches(src, rect, m):
		RenderingServer.canvas_item_add_texture_rect_region(item, p[1], tex.get_rid(), p[0], tint)


## [[source, destination], ...] of a 9-slice: caps keep their pixels (clamped
## to half the rect, so a small rect never draws inverted patches), edges and
## centre stretch.
static func nine_patches(src: Rect2, rect: Rect2, m: Array) -> Array:
	var l := minf(m[0], rect.size.x * 0.5)
	var t := minf(m[1], rect.size.y * 0.5)
	var r := minf(m[2], rect.size.x * 0.5)
	var b := minf(m[3], rect.size.y * 0.5)
	var sx := [src.position.x, src.position.x + l, src.end.x - r, src.end.x]
	var sy := [src.position.y, src.position.y + t, src.end.y - b, src.end.y]
	var dx := [rect.position.x, rect.position.x + l, rect.end.x - r, rect.end.x]
	var dy := [rect.position.y, rect.position.y + t, rect.end.y - b, rect.end.y]
	var out := []
	for j in 3:
		for i in 3:
			var s := Rect2(sx[i], sy[j], sx[i + 1] - sx[i], sy[j + 1] - sy[j])
			var d := Rect2(dx[i], dy[j], dx[i + 1] - dx[i], dy[j + 1] - dy[j])
			if s.has_area() and d.has_area():
				out.append([s, d])
	return out


## A cached StyleBoxTexture for a 9-slice region (texture margins from the
## json, content margins 0: callers duplicate it and set their own). null
## when the atlas or region is missing. Shared: never mutate the result.
static func stylebox(atlas_id: String, region_id: String) -> StyleBoxTexture:
	var key := "%s:%s" % [atlas_id, region_id]
	if _styleboxes.has(key):
		return _styleboxes[key]
	var a := atlas(atlas_id)
	var src := region(atlas_id, region_id)
	var sb: StyleBoxTexture = null
	if not a.is_empty() and src.has_area():
		sb = StyleBoxTexture.new()
		sb.texture = a["texture"]
		sb.region_rect = src
		var m: Array = a["nine"].get(region_id, [0.0, 0.0, 0.0, 0.0])
		sb.texture_margin_left = m[0]
		sb.texture_margin_top = m[1]
		sb.texture_margin_right = m[2]
		sb.texture_margin_bottom = m[3]
		sb.set_content_margin_all(0.0)
	_styleboxes[key] = sb
	return sb


## Title logo textures: {logo, crack} or {} when either is missing.
static func title_logo() -> Dictionary:
	var logo := _texture("%s/title_logo.png" % title_dir)
	var crack := _texture("%s/title_logo_crack.png" % title_dir)
	if logo == null or crack == null:
		return {}
	return {"logo": logo, "crack": crack}


## Settings.flash_reduction read through the tree (UiKit loads without it).
static func flash_reduced() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var s: Node = tree.root.get_node_or_null("Settings") if tree and tree.root else null
	return s != null and bool(s.get("flash_reduction"))


## Plays a UI sound through AudioManager when the bank has it (ui_confirm
## and ui_back arrive with T08's bank; before that the call is silent, never
## the "unknown sfx" warning). Every request is recorded in `played`.
static func play_ui(id: StringName) -> void:
	played.append(id)
	while played.size() > 16:
		played.pop_front()
	var tree := Engine.get_main_loop() as SceneTree
	var am: Node = tree.root.get_node_or_null("AudioManager") if tree and tree.root else null
	if am != null and bool(am.call("has_sfx", id)):
		am.call("play_sfx", id)
