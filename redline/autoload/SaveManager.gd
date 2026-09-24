extends Node
## Versioned, atomic JSON save skeleton (bible §29).
##
## Design intent:
## - Every save carries "schema_version". Loading runs migrations in order
##   until the data reaches CURRENT_SCHEMA_VERSION, so old saves never break.
## - Writes are atomic: write to <file>.tmp, keep the previous file as <file>.bak,
##   then rename tmp into place. A crash mid-write never destroys the last good save.
## - If the primary file is corrupt, the backup is tried before giving up.
## M1 stores almost nothing; the structure is what matters now.

const CURRENT_SCHEMA_VERSION := 1
const DEFAULT_SAVE_DIR := "user://saves"

var save_dir: String = DEFAULT_SAVE_DIR


func profile_path(profile_id: int) -> String:
	return "%s/profile_%d.json" % [save_dir, profile_id]


## Fresh data for a brand-new profile at the current schema.
func new_profile_data() -> Dictionary:
	return {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"story_flags": {},
		"abilities": {},
		"currencies": {"scrap": 0},
		"statistics": {"play_time_sec": 0.0, "deaths": 0},
	}


func save_profile(profile_id: int, data: Dictionary) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(save_dir)
	if err != OK and err != ERR_ALREADY_EXISTS:
		return err
	var payload := data.duplicate(true)
	payload["schema_version"] = CURRENT_SCHEMA_VERSION
	var path := profile_path(profile_id)
	var tmp_path := path + ".tmp"
	var bak_path := path + ".bak"

	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()

	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(bak_path)
		err = DirAccess.rename_absolute(path, bak_path)
		if err != OK:
			return err
	return DirAccess.rename_absolute(tmp_path, path)


## Returns an empty Dictionary if neither the save nor its backup is readable.
func load_profile(profile_id: int) -> Dictionary:
	var path := profile_path(profile_id)
	var data := _read_json(path)
	if data.is_empty():
		data = _read_json(path + ".bak")
		if not data.is_empty():
			push_warning("SaveManager: primary save unreadable, recovered from backup")
	if data.is_empty():
		return {}
	return migrate(data)


## Upgrades data one schema version at a time. Add a _migrate_vN_to_vN+1 per bump.
func migrate(data: Dictionary) -> Dictionary:
	var result := data.duplicate(true)
	var version: int = int(result.get("schema_version", 0))
	while version < CURRENT_SCHEMA_VERSION:
		match version:
			0:
				result = _migrate_v0_to_v1(result)
			_:
				push_error("SaveManager: no migration from schema %d" % version)
				return {}
		version = int(result["schema_version"])
	return result


## v0 was the pre-production prototype layout: a flat dict with "scrap" at the root.
func _migrate_v0_to_v1(data: Dictionary) -> Dictionary:
	var out := new_profile_data()
	out["currencies"]["scrap"] = int(data.get("scrap", 0))
	out["story_flags"] = data.get("flags", {})
	out["schema_version"] = 1
	return out


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}
