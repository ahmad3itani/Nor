class_name LocalStore
extends RefCounted
## The machine-wide achievements file (D-141, D-143): <Platform.store_dir>/
## achievements.json, written through AtomicJson (tmp -> .bak -> rename; an
## unreadable primary recovers from .bak). It is global to the machine user,
## like a storefront account: deleting a profile never deletes achievements,
## and only an explicit dev reset clears them.
##
## {"store_version": 1,
##  "unlocked": {id: {"t": unix seconds, "profile": int}},
##  "lifetime": {stat_id: value},
##  "presence": {"key": ..., "text": ...}}
## Challenge records live in T04's RecordStore (records.json), not here.
## Sections this version does not know are kept and written back unchanged.
##
## The store never decides whether it may write: Platform only calls save()
## when Platform.active() (headless runs write nothing unless a test opts in).

var dir: String = ""
var path: String = ""
var store_version: int = 1
var unlocked: Dictionary = {}
var lifetime: Dictionary = {}
var presence: Dictionary = {}
## Changed since the last save().
var dirty: bool = false
var _extra: Dictionary = {}


## Reads <p_dir>/<file> (or its .bak). A missing file is an empty store.
func load_from(p_dir: String, file: String, version: int) -> void:
	dir = p_dir
	path = "%s/%s" % [p_dir, file]
	store_version = version
	unlocked = {}
	lifetime = {}
	presence = {}
	_extra = {}
	dirty = false
	var d := AtomicJson.read(path)
	if d.is_empty():
		return
	var v := int(d.get("store_version", version))
	if v > version:
		push_warning("LocalStore: %s has store_version %d (this build knows %d); keeping unknown keys" % [path, v, version])
		store_version = v
	for k: String in d:
		match k:
			"store_version":
				pass
			"unlocked":
				if d[k] is Dictionary:
					for id: String in d[k]:
						var rec: Variant = d[k][id]
						if rec is Dictionary:
							unlocked[id] = {"t": int(rec.get("t", 0)), "profile": int(rec.get("profile", 1))}
			"lifetime":
				if d[k] is Dictionary:
					for id: String in d[k]:
						lifetime[id] = float(d[k][id])
			"presence":
				if d[k] is Dictionary:
					presence = (d[k] as Dictionary).duplicate(true)
			_:
				_extra[k] = d[k]


func to_dict() -> Dictionary:
	var d := _extra.duplicate(true)
	d["store_version"] = store_version
	d["unlocked"] = unlocked.duplicate(true)
	d["lifetime"] = lifetime.duplicate(true)
	d["presence"] = presence.duplicate(true)
	return d


func save() -> Error:
	if path == "":
		return ERR_UNCONFIGURED
	var err := AtomicJson.write(path, to_dict())
	if err == OK:
		dirty = false
	else:
		push_warning("LocalStore: could not write %s (%s)" % [path, error_string(err)])
	return err


func is_unlocked(id: String) -> bool:
	return unlocked.has(id)


func unlocked_ids() -> PackedStringArray:
	var ids := PackedStringArray(unlocked.keys())
	ids.sort()
	return ids


## False when already unlocked (the first unlock's time and profile stay).
func unlock(id: String, profile: int, unix_time: int) -> bool:
	if unlocked.has(id):
		return false
	unlocked[id] = {"t": unix_time, "profile": profile}
	dirty = true
	return true


func lock(id: String) -> bool:
	if not unlocked.erase(id):
		return false
	dirty = true
	return true


func lifetime_value(id: StringName) -> float:
	return float(lifetime.get(String(id), 0.0))


func has_lifetime(id: StringName) -> bool:
	return lifetime.has(String(id))


func set_lifetime(id: StringName, value: float) -> void:
	var key := String(id)
	if lifetime.has(key) and float(lifetime[key]) == value:
		return
	lifetime[key] = value
	dirty = true


func clear_all() -> void:
	unlocked = {}
	lifetime = {}
	dirty = true
