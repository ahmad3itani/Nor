class_name VfxLibrary
extends Resource
## The VFX sheets VfxOneShot can spawn, by id (data/vfx/vfx_library.tres).
## Each entry: spec (res:// SpriteSheetSpec path), a default tint (palette_key,
## an AccessPalette semantic or role key, or a plain color when the key is
## empty), additive (blend mode) and cap (live instances of that id at once).
## The sheets are grey masks (tones 96/176/255) tinted in code.
##
## Loaded lazily and cached; SpriteFrames are built once per id and shared.

const PATH := "res://data/vfx/vfx_library.tres"
const ENTRY_KEYS: PackedStringArray = ["spec", "palette_key", "color", "additive", "cap"]

## id (StringName) -> {spec: String, palette_key: StringName, color: Color,
## additive: bool, cap: int}
@export var entries: Dictionary = {}

static var _library: VfxLibrary
static var _specs: Dictionary = {}
static var _frames: Dictionary = {}


static func get_library() -> VfxLibrary:
	if _library == null:
		_library = load(PATH) as VfxLibrary if ResourceLoader.exists(PATH) else VfxLibrary.new()
	return _library


## Drops the cached library, specs and frames (tests that swap entries).
static func clear_cache() -> void:
	_library = null
	_specs.clear()
	_frames.clear()


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in get_library().entries:
		out.append(StringName(k))
	return out


## The entry for `id`, or {} when unknown.
static func entry(id: StringName) -> Dictionary:
	var e: Variant = get_library().entries.get(id, get_library().entries.get(String(id), {}))
	return e if e is Dictionary else {}


## The id's SpriteSheetSpec, or null (unknown id, missing file).
static func spec(id: StringName) -> SpriteSheetSpec:
	if _specs.has(id):
		return _specs[id]
	var e := entry(id)
	var s: SpriteSheetSpec = null
	var path := str(e.get("spec", ""))
	if path != "" and ResourceLoader.exists(path):
		s = load(path) as SpriteSheetSpec
	_specs[id] = s
	return s


## Shared SpriteFrames of the id's sheet, or null when the sheet is missing
## (callers keep their placeholder).
static func frames(id: StringName) -> SpriteFrames:
	if _frames.has(id):
		return _frames[id]
	var s := spec(id)
	var f: SpriteFrames = s.build_frames() if s else null
	_frames[id] = f
	return f


## The default tint: the palette key's colour in the player's palette, else
## the entry colour, else white.
static func default_color(id: StringName) -> Color:
	var e := entry(id)
	var key := StringName(e.get("palette_key", &""))
	if key != &"" and is_palette_key(key):
		return Palette.color(key)
	var c: Variant = e.get("color", Color.WHITE)
	return c if c is Color else Color.WHITE


static func is_palette_key(key: StringName) -> bool:
	return AccessPalette.SEMANTIC_KEYS.has(key) or AccessPalette.ROLES.has(key)


## ContentValidator resource protocol: every entry names a loadable sheet,
## a known palette key or a colour, and a positive cap.
func validate() -> PackedStringArray:
	var out := PackedStringArray()
	for k in entries:
		var e: Variant = entries[k]
		if not (e is Dictionary):
			out.append("vfx '%s': entry is not a Dictionary" % k)
			continue
		var d: Dictionary = e
		for key in d:
			if not ENTRY_KEYS.has(str(key)):
				out.append("vfx '%s': unknown field '%s'" % [k, key])
		var path := str(d.get("spec", ""))
		if not path.begins_with("res://") or not ResourceLoader.exists(path):
			out.append("vfx '%s': spec %s missing" % [k, path])
		elif not (load(path) is SpriteSheetSpec):
			out.append("vfx '%s': %s is not a SpriteSheetSpec" % [k, path])
		var key := StringName(d.get("palette_key", &""))
		if key != &"" and not is_palette_key(key):
			out.append("vfx '%s': unknown palette key '%s'" % [k, key])
		if key == &"" and not (d.get("color") is Color):
			out.append("vfx '%s': needs a palette_key or a color" % k)
		if int(d.get("cap", 0)) < 1:
			out.append("vfx '%s': cap must be at least 1" % k)
	return out
