class_name ArtValidator
extends RefCounted
## Checks delivered art against Docs/ART_BIBLE.md (bible §40: "every asset
## must be checked against the Art Bible"): naming, crisp alpha, sheet
## sizes vs their SpriteSheetSpec, palette size, reserved gameplay colours
## outside UI/VFX, and the project's nearest-neighbour filtering.

const ASSET_DIR := "res://assets"
const NAME_RULE := "^[a-z0-9]+(_[a-z0-9]+)+\\.png$"
const MAX_COLORS := 64
## Art Bible §3: colours reserved for gameplay meaning.
const RESERVED: Array[Color] = [Color("ff3b4f"), Color("7fd7ff"), Color("7dff9a"), Color("ffd36b"), Color("9fd8ff")]

var errors: PackedStringArray = []
var warnings: PackedStringArray = []


func run(asset_dir: String = ASSET_DIR) -> ArtValidator:
	if int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", 1)) != 0:
		errors.append("project texture filter must be Nearest (Art Bible §1)")
	if DirAccess.dir_exists_absolute(asset_dir):
		for path in ContentValidator._files(asset_dir, ["png"]):
			check_image(path)
	for dir in [asset_dir]:  # specs under data/ are validated by ContentValidator
		if DirAccess.dir_exists_absolute(dir):
			for path in ContentValidator._files(dir, ["tres"]):
				var res := load(path)
				if res is SpriteSheetSpec:
					for e in (res as SpriteSheetSpec).validate():
						errors.append("%s: %s" % [path.get_file(), e])
	return self


func check_image(path: String) -> void:
	var file := path.get_file()
	if not RegEx.create_from_string(NAME_RULE).search(file):
		errors.append("%s: name must be snake_case <subject>_<action>[_variant].png" % file)
	var img := Image.load_from_file(path) if not path.begins_with("res://") or not ResourceLoader.exists(path) else (load(path) as Texture2D).get_image()
	if img == null:
		errors.append("%s: cannot be read" % file)
		return
	if img.is_compressed():
		img.decompress()
	var colors := {}
	var soft_alpha := 0
	var reserved_hits := 0
	var ui_or_vfx := path.contains("/ui/") or path.contains("/vfx/")
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a8 != 0 and c.a8 != 255:
				soft_alpha += 1
			if c.a8 == 0:
				continue
			colors[c.to_rgba32()] = true
			if not ui_or_vfx and RESERVED.any(func(r: Color) -> bool: return r.to_rgba32() == Color(c.r, c.g, c.b, 1.0).to_rgba32()):
				reserved_hits += 1
	if soft_alpha > 0:
		errors.append("%s: %d semi-transparent pixels (pixel art needs alpha 0 or 255; no anti-aliasing)" % [file, soft_alpha])
	if colors.size() > MAX_COLORS:
		warnings.append("%s: %d colours (> %d): check palette discipline" % [file, colors.size(), MAX_COLORS])
	if reserved_hits > 0:
		warnings.append("%s: uses a reserved gameplay colour in %d pixels (telegraph/guard/heal/Scrap/memory)" % [file, reserved_hits])


func ok() -> bool:
	return errors.is_empty()
