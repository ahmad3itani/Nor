class_name SettingsCatalog
extends Resource
## Every Settings page in main-list order (D4 §3.1-§3.4). Settings persists
## from it, SettingsMenu renders from it, SettingsRules (SE-1..SE-3) lints it.

const PATH := "res://data/settings/catalog.tres"

## Localization (D5): player-visible text fields -> max source chars.
const LOC_FIELDS := {"assist_header": 120, "reset_all_prompt": 90}
const LOC_EXEMPT := ["forbidden_words"]

@export var pages: Array[SettingsPageData] = []
## §24 "never shame": no label or description may use these (SE-3).
@export var forbidden_words: PackedStringArray = []
## Muted line under the Assists title.
@export var assist_header: String = ""
## Confirm text of "Reset all settings…" (controls and language stay).
@export var reset_all_prompt: String = ""


func page(id: StringName) -> SettingsPageData:
	for p in pages:
		if p != null and p.id == id:
			return p
	return null


## Every owned def of every page, in page order.
func all_defs() -> Array[SettingDef]:
	var out: Array[SettingDef] = []
	for p in pages:
		if p == null:
			continue
		for d in p.rows:
			if d != null:
				out.append(d)
	return out


## Defs the Settings load/save loop stores.
func stored_defs() -> Array[SettingDef]:
	var out: Array[SettingDef] = []
	for d in all_defs():
		if d.is_stored():
			out.append(d)
	return out


func def(key: StringName) -> SettingDef:
	for d in all_defs():
		if d.key == key:
			return d
	return null


## The rows a page shows: its own, then any borrowed by key.
func rows_of(p: SettingsPageData) -> Array[SettingDef]:
	var out: Array[SettingDef] = []
	if p == null:
		return out
	for d in p.rows:
		if d != null:
			out.append(d)
	for k in p.row_keys:
		var d := def(StringName(k))
		if d != null:
			out.append(d)
	return out


## Stored keys a page's reset puts back (its own and borrowed rows).
func page_keys(p: SettingsPageData) -> Array[StringName]:
	var out: Array[StringName] = []
	for d in rows_of(p):
		if d.is_stored():
			out.append(d.key)
	return out


## Lowercase forbidden words found in `text` (whole words or phrases).
func forbidden_in(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var low := " %s " % text.to_lower()
	for c in [".", ",", ":", ";", "!", "?", "(", ")", "…", "\"", "'", "/"]:
		low = low.replace(c, " ")
	for w in forbidden_words:
		if low.contains(" %s " % w.to_lower()):
			out.append(w)
	return out
