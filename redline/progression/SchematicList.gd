class_name SchematicList
extends Resource
## Schematics (D-184, bible §21 "weapon schematics"): key-item Collectibles
## (Collectible.Kind.SCHEMATIC) that set sch_<id> and unlock upgrade tiers.
## Never spent, never stacked, not secrets. This list is their only name
## table; display always goes through Loc.t(name).

const PATH := "res://data/upgrades/schematics.tres"

## Localization (D5 §4.1): "names" matches the l10n text-field pattern and
## LocFields extracts Dictionary values, so every name is in the catalog.
const LOC_FIELDS := {"names": 28}

## id -> display name (English source).
@export var names: Dictionary = {}
## id -> district id ("undercity" | "lowlight" | "ironworks"), for the menu's
## lock line. An id, never shown as is.
@export var districts: Dictionary = {}

static var _shared: SchematicList = null


## The data file, cached (UpgradeLibrary.clear_cache frees it at exit).
static func shared() -> SchematicList:
	if _shared == null:
		_shared = load(PATH) as SchematicList if ResourceLoader.exists(PATH) else null
		if _shared == null:
			_shared = SchematicList.new()
	return _shared


static func clear_cache() -> void:
	_shared = null


func has_id(id: String) -> bool:
	return names.has(id)


## The source-text name ("" for an unknown id); callers Loc.t it.
func name_of(id: String) -> String:
	return String(names.get(id, ""))


func district_of(id: String) -> String:
	return String(districts.get(id, ""))


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for id: Variant in names:
		if String(id) == "" or String(names[id]).strip_edges() == "":
			errors.append("schematic '%s' needs an id and a name" % id)
		if not districts.has(id):
			errors.append("schematic '%s' has no district" % id)
	for id: Variant in districts:
		if not names.has(id):
			errors.append("schematic '%s' has a district but no name" % id)
	return errors
