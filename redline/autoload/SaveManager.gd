extends Node
## Versioned, atomic JSON save skeleton (bible §29).
##
## Design intent:
## - Every save carries "schema_version". Loading runs migrations in order
##   until the data reaches CURRENT_SCHEMA_VERSION, so old saves never break.
## - Writes are atomic: write to <file>.tmp, keep the previous file as <file>.bak,
##   then rename tmp into place. A crash mid-write never destroys the last good save.
## - If the primary file is corrupt, the backup is tried before giving up.
## Since M3 the payload is GameState.to_dict() plus "schema_version".

const CURRENT_SCHEMA_VERSION := 3
const DEFAULT_SAVE_DIR := "user://saves"

var save_dir: String = DEFAULT_SAVE_DIR


func profile_path(profile_id: int) -> String:
	return "%s/profile_%d.json" % [save_dir, profile_id]


## Fresh data for a brand-new profile at the current schema.
func new_profile_data() -> Dictionary:
	var d := GameState.new().to_dict()
	d["schema_version"] = CURRENT_SCHEMA_VERSION
	return d


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
			1:
				result = _migrate_v1_to_v2(result)
			2:
				result = _migrate_v2_to_v3(result)
			_:
				push_error("SaveManager: no migration from schema %d" % version)
				return {}
		version = int(result["schema_version"])
	return result


## v0 was the pre-production prototype layout: a flat dict with "scrap" at the root.
func _migrate_v0_to_v1(data: Dictionary) -> Dictionary:
	return {
		"schema_version": 1,
		"story_flags": data.get("flags", {}),
		"abilities": {},
		"currencies": {"scrap": int(data.get("scrap", 0))},
		"statistics": {"play_time_sec": 0.0, "deaths": 0},
	}


## v1 (M0-M2 skeleton) -> v2 (M3 GameState): flags, banked scrap and stats carry over.
func _migrate_v1_to_v2(data: Dictionary) -> Dictionary:
	var out := GameState.new().to_dict()
	out["flags"] = data.get("story_flags", {})
	out["abilities"] = data.get("abilities", {})
	out["scrap_banked"] = int(data.get("currencies", {}).get("scrap", 0))
	var stats: Dictionary = data.get("statistics", {})
	out["play_time_sec"] = float(stats.get("play_time_sec", 0.0))
	out["deaths"] = int(stats.get("deaths", 0))
	out["schema_version"] = 2
	return out


## v3 (M5) adds the map: explored cells, pins and the Anchors rested at.
## Old saves keep every room they visited (outlines stay known through
## visited_rooms) and their respawn Anchor joins the transit network.
func _migrate_v2_to_v3(data: Dictionary) -> Dictionary:
	var out := data.duplicate(true)
	out["map_explored"] = out.get("map_explored", {})
	out["map_pins"] = out.get("map_pins", [])
	var rested: Array = out.get("anchors_rested", [])
	var room := str(out.get("last_anchor_room", ""))
	if room != "" and not rested.has("%s|%s" % [room, out.get("last_anchor_id", "")]):
		rested.append("%s|%s" % [room, out.get("last_anchor_id", "")])
	out["anchors_rested"] = rested
	out["schema_version"] = 3
	return out


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}
