class_name LocaleTable
extends Resource
## Every display language the game knows (M9 D5): rows of LocaleInfo, the
## source language first. Loc reads it to resolve codes, offer choices and
## pick the font floor; the validator checks each enabled row has a catalog.

const PATH := "res://data/l10n/locales.tres"
const CATALOG_DIR := "res://locale"

@export var rows: Array[LocaleInfo] = []

static var _shared: LocaleTable


## The shipped table (cached; an empty table when the file is missing).
static func shared() -> LocaleTable:
	if _shared == null:
		_shared = load(PATH) as LocaleTable if ResourceLoader.exists(PATH) else null
		if _shared == null:
			_shared = LocaleTable.new()
	return _shared


static func clear_cache() -> void:
	_shared = null


func by_code(code: String) -> LocaleInfo:
	for r in rows:
		if r and r.code == code:
			return r
	return null


func codes() -> PackedStringArray:
	var out := PackedStringArray()
	for r in rows:
		if r:
			out.append(r.code)
	return out


## Content check (ContentValidator.check_resource calls it): unique codes,
## the source language first, a catalog behind every enabled translation,
## sane sizes and reading scales, and font files that exist.
func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	var seen := {}
	if rows.is_empty() or rows[0] == null or rows[0].code != "en":
		errs.append("the source locale 'en' must be the first row")
	for r in rows:
		if r == null:
			errs.append("empty locale row")
			continue
		if r.code == "":
			errs.append("a locale row has no code")
			continue
		if seen.has(r.code):
			errs.append("locale '%s' listed twice" % r.code)
		seen[r.code] = true
		if r.enabled and r.code != "en" and not FileAccess.file_exists("%s/%s.po" % [CATALOG_DIR, r.code]):
			errs.append("locale '%s' is enabled but has no catalog %s/%s.po" % [r.code, CATALOG_DIR, r.code])
		if r.min_font_size < 6 or r.min_font_size > 16:
			errs.append("locale '%s': min_font_size %d outside 6..16" % [r.code, r.min_font_size])
		if r.reading_scale < 0.5 or r.reading_scale > 3.0:
			errs.append("locale '%s': reading_scale %.2f outside 0.5..3" % [r.code, r.reading_scale])
		if r.endonym == "":
			errs.append("locale '%s' has no endonym" % r.code)
		for p in r.font_paths:
			if not ResourceLoader.exists(p):
				errs.append("locale '%s': font %s does not exist" % [r.code, p])
	return errs
