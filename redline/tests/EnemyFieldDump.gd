class_name EnemyFieldDump
extends RefCounted
## T05 (presentation overhaul): a stable dump of every EnemyData in
## data/enemies/, minus the visual-only fields the overhaul may change
## (EnemyData.color, sprite, sprite_modulate). The dump was written to
## tests/fixtures/enemy_data_fields.json BEFORE any T05 edit, so
## test_enemy_sprites can prove every gameplay number stayed the same.
##
## Regenerate only when a gameplay number is meant to change (never in T05):
##   EnemyFieldDump.write_fixture() from a one-off script.

const DIR := "res://data/enemies"
const FIXTURE := "res://tests/fixtures/enemy_data_fields.json"
## Visual-only EnemyData fields (the only ones T05 may change).
const VISUAL_FIELDS: PackedStringArray = ["color", "sprite", "sprite_modulate"]
const MAX_DEPTH := 6


## file name -> {"fields": dump, "validate": [errors]}
static func dump_all() -> Dictionary:
	var out := {}
	for path in DataDir.list(DIR):
		var d := load(path) as EnemyData
		if d == null:
			continue
		out[path.get_file()] = {"fields": dump_resource(d, 0, true), "validate": Array(d.validate())}
	return out


static func dump_resource(r: Resource, depth: int, top: bool = false) -> Variant:
	if r == null:
		return null
	if depth > MAX_DEPTH:
		return "<deep>"
	# Shared resources in their own files are named by path (their numbers are
	# pinned by their own content; a path change is still a change).
	var d := {}
	if not top and r.resource_path != "" and not r.resource_path.contains("::"):
		d["@path"] = r.resource_path
	for p in r.get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_STORAGE):
			continue
		var n := str(p["name"])
		if n == "script" or n.begins_with("resource_") or n.begins_with("metadata/"):
			continue
		if top and VISUAL_FIELDS.has(n):
			continue
		d[n] = _value(r.get(n), depth)
	return d


static func _value(v: Variant, depth: int) -> Variant:
	if v is Resource:
		return dump_resource(v, depth + 1)
	if v is Array:
		var a := []
		for x in v:
			a.append(_value(x, depth))
		return a
	if v is Dictionary:
		var o := {}
		for k in v:
			o[str(k)] = _value(v[k], depth)
		return o
	return var_to_str(v)


static func write_fixture() -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.WRITE)
	f.store_string(JSON.stringify(dump_all(), " ", true) + "\n")
	f.close()


static func read_fixture() -> Dictionary:
	if not FileAccess.file_exists(FIXTURE):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	return v if v is Dictionary else {}
