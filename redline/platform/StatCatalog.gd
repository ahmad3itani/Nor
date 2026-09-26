class_name StatCatalog
extends Resource
## Every stat the platform layer tracks (data/platform/stats.tres). Data, not
## code (§37.3): adding a stat for a later act is a new row here plus a
## listener in StatsTracker only when no existing rule produces it.

const PATH := "res://data/platform/stats.tres"

@export var stats: Array[StatDef] = []

static var _default: StatCatalog = null


## The shipped catalog (cached; clear_cache() drops it).
static func shipped() -> StatCatalog:
	if _default == null:
		_default = load(PATH) as StatCatalog
	return _default


static func clear_cache() -> void:
	_default = null


func stat(id: StringName) -> StatDef:
	for s in stats:
		if s != null and s.id == id:
			return s
	return null


func has_stat(id: StringName) -> bool:
	return stat(id) != null


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for s in stats:
		if s != null:
			out.append(s.id)
	return out


## Per-file checks; cross-file ones (unique api names, derived ids, boss
## suffixes) are PlatformRules PL-11/PL-12.
func validate() -> PackedStringArray:
	var e := PackedStringArray()
	for i in stats.size():
		if stats[i] == null:
			e.append("stat row %d is empty" % i)
		else:
			e.append_array(stats[i].validate())
	return e
