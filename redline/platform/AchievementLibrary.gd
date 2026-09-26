class_name AchievementLibrary
extends RefCounted
## Every achievement (data/achievements/*.tres), sorted by `sort` then id.
## Static and lazy like MemoryLibrary: scanned once through DataDir (exported
## builds list .remap files). Cinematics._exit_tree calls clear_cache().

const DIR := "res://data/achievements"

static var _all: Array[AchievementData] = []
static var _by_id: Dictionary = {}
static var _scanned: bool = false


static func _scan() -> void:
	if _scanned:
		return
	_scanned = true
	var list: Array[AchievementData] = []
	for path in DataDir.list(DIR):
		var a := load(path) as AchievementData
		if a != null and a.id != "":
			list.append(a)
	_assign(list)


static func _assign(list: Array[AchievementData]) -> void:
	_all = list.duplicate()
	_all.sort_custom(func(a: AchievementData, b: AchievementData) -> bool:
		return a.sort < b.sort if a.sort != b.sort else a.id < b.id)
	_by_id.clear()
	for a in _all:
		_by_id[a.id] = a


static func all() -> Array[AchievementData]:
	_scan()
	return _all.duplicate()


## Never get(): a static get() overrides Object.get (4.3 parse error).
static func by_id(id: String) -> AchievementData:
	_scan()
	return _by_id.get(id) as AchievementData


static func count() -> int:
	_scan()
	return _all.size()


## Test seam: replaces the shipped list until clear_cache().
static func use_for_tests(list: Array[AchievementData]) -> void:
	_scanned = true
	_assign(list)


static func clear_cache() -> void:
	_all.clear()
	_by_id.clear()
	_scanned = false
