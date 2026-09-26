class_name L10nConfig
extends Resource
## Where the string extractor looks and how the lints and the pseudo-locale
## behave (M9 D5 §8.2). Data, so a new content folder or sink is one line
## here and never a tool change.

const PATH := "res://data/l10n/l10n_config.tres"

## .tres roots walked recursively for LOC_FIELDS text.
@export var resource_dirs: PackedStringArray = ["res://data"]
## .tscn roots walked recursively (scene state only, never instanced).
@export var scene_dirs: PackedStringArray = []
## .gd roots scanned for Loc.* calls and `# l10n` lines, and linted (L-3, L-8).
@export var code_dirs: PackedStringArray = []
## Path prefixes never extracted or linted: dev tooling and the playtest
## facilitator UI stay English (D-163).
@export var code_exempt: PackedStringArray = []
## Calls whose string-literal arguments reach the screen (L-3).
@export var literal_sinks: PackedStringArray = []
@export var pseudo_ratio_short: float = 0.5
@export var pseudo_ratio_long: float = 0.35
## Visible length at or under which pseudo_ratio_short applies.
@export var pseudo_short_len: int = 12
@export var pseudo_min_pad: int = 2
@export var pseudo_prefix: String = "["
@export var pseudo_suffix: String = "]"
@export var pseudo_pad_char: String = "~"
## Letter -> accented stand-in. Only glyphs the default font really has, so
## pseudo layout tests measure real glyphs (test_pseudo_glyphs_in_font).
@export var pseudo_map: Dictionary = {}
## L-7: a translation longer than max_chars times this is a layout risk.
@export var over_length_warn_ratio: float = 1.4
## L-2: exported text-like property names that must be classified.
@export var text_field_pattern: String = ""

static var _shared: L10nConfig


static func shared() -> L10nConfig:
	if _shared == null:
		_shared = load(PATH) as L10nConfig if ResourceLoader.exists(PATH) else null
		if _shared == null:
			_shared = L10nConfig.new()
	return _shared


static func clear_cache() -> void:
	_shared = null


## Whether `path` (res://…) sits under an exempt prefix.
func is_exempt(path: String) -> bool:
	for p in code_exempt:
		if path.begins_with(p):
			return true
	return false


func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	for list: PackedStringArray in [resource_dirs, scene_dirs, code_dirs]:
		for d in list:
			if not DirAccess.dir_exists_absolute(d):
				errs.append("l10n config: directory %s does not exist" % d)
	if pseudo_prefix == "" or pseudo_suffix == "" or pseudo_pad_char.length() != 1:
		errs.append("l10n config: pseudo brackets must be set and the pad one character")
	for k: String in pseudo_map:
		if k.length() != 1 or str(pseudo_map[k]).length() != 1:
			errs.append("l10n config: pseudo_map entries map one character to one character ('%s')" % k)
	if RegEx.create_from_string(text_field_pattern) == null or text_field_pattern == "":
		errs.append("l10n config: text_field_pattern is not a valid regex")
	return errs
