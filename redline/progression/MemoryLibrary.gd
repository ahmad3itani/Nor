class_name MemoryLibrary
extends RefCounted
## Every memory vignette and the rules that decide which ones are waiting
## (M8, bible §18). Static, lazy, like SliceStats.totals(): scenes are
## scanned once from data/memories through DataDir (so an exported build's
## .tres.remap files are found too).
##
## Design intent: skipping a memory still remembers it. Remembering is never
## a skill test and must never cost an ending (bible §24 "never shame").
## All state is flags (D-116): mem_seen_<id>, mem_detail_<id> and the int
## memories_remembered, so arcs, switches and endings read memories through
## Game.check_condition like any other progress.

const DIR := "res://data/memories"
const CONFIG_PATH := "res://data/memories/memory_config.tres"
const REMEMBERED_FLAG := "memories_remembered"

static var _scenes: Dictionary = {}
static var _sorted: Array[MemorySceneData] = []
static var _config: MemoryConfig = null
static var _scanned: bool = false


static func _scan() -> void:
	if _scanned:
		return
	_scanned = true
	_scenes.clear()
	_sorted.clear()
	for path in DataDir.list(DIR):
		if path == CONFIG_PATH:
			continue
		var s := load(path) as MemorySceneData
		if s and s.id != "":
			_scenes[s.id] = s
			_sorted.append(s)
	_sorted.sort_custom(func(a: MemorySceneData, b: MemorySceneData) -> bool:
		return a.timeline_slot < b.timeline_slot if a.timeline_slot != b.timeline_slot else a.id < b.id)


## Sorted by timeline_slot (then id).
static func all_scenes() -> Array[MemorySceneData]:
	_scan()
	return _sorted.duplicate()


static func scene(id: String) -> MemorySceneData:
	_scan()
	return _scenes.get(id)


static func scene_for_fragment(fragment_id: String) -> MemorySceneData:
	_scan()
	for s in _sorted:
		if s.source == MemorySceneData.Source.FRAGMENT and s.fragment and s.fragment.id == fragment_id:
			return s
	return null


static func config() -> MemoryConfig:
	if _config == null:
		_config = load(CONFIG_PATH) as MemoryConfig
		if _config == null:
			_config = MemoryConfig.new()
	return _config


## FRAGMENT: its fragment was recovered; SURFACED: its condition holds.
static func is_unlocked(s: MemorySceneData) -> bool:
	if s.source == MemorySceneData.Source.FRAGMENT:
		return Game.state.memory_fragments.has(s.id)
	return Game.check_condition(s.unlock_condition)


static func flag_seen(id: String) -> String:
	return "mem_seen_%s" % id


static func flag_detail(id: String) -> String:
	return "mem_detail_%s" % id


static func is_seen(id: String) -> bool:
	return Game.has_flag(flag_seen(id))


static func is_detail_found(id: String) -> bool:
	return Game.has_flag(flag_detail(id))


## Unlocked and not yet remembered, in play order: queue_priority first,
## then SURFACED before FRAGMENT, then fragment pickup order.
static func pending() -> Array[MemorySceneData]:
	var out: Array[MemorySceneData] = []
	for s in all_scenes():
		if is_unlocked(s) and not is_seen(s.id):
			out.append(s)
	var frags := Game.state.memory_fragments
	out.sort_custom(func(a: MemorySceneData, b: MemorySceneData) -> bool:
		if a.queue_priority != b.queue_priority:
			return a.queue_priority > b.queue_priority
		if a.source != b.source:
			return a.source == MemorySceneData.Source.SURFACED
		var ia := frags.find(a.id)
		var ib := frags.find(b.id)
		if ia != ib:
			return ia < ib
		return a.timeline_slot < b.timeline_slot)
	return out


## What one Anchor rest plays (config().max_per_rest).
static func pending_for_rest() -> PackedStringArray:
	var ids := PackedStringArray()
	for s in pending():
		if ids.size() >= config().max_per_rest:
			break
		ids.append(s.id)
	return ids


## Idempotent: the first time sets mem_seen_<id> and increments
## memories_remembered through Game.set_flag, so flag listeners (arcs,
## switches, quests) react once.
static func mark_seen(id: String) -> void:
	if is_seen(id):
		return
	Game.set_flag(flag_seen(id))
	Game.set_flag(REMEMBERED_FLAG, Game.flag_int(REMEMBERED_FLAG) + 1)


static func mark_detail(id: String) -> void:
	Game.set_flag(flag_detail(id))


## Every remembered scene, surfaced ones included (data reads this flag).
static func remembered_count() -> int:
	return Game.flag_int(REMEMBERED_FLAG)


## Remembered FRAGMENT scenes whose fragment was recovered (the journal and
## Act I card line "Fragments remembered N / M", so N never exceeds M).
static func remembered_fragment_count() -> int:
	var n := 0
	for s in all_scenes():
		if s.source == MemorySceneData.Source.FRAGMENT and is_seen(s.id) and Game.state.memory_fragments.has(s.id):
			n += 1
	return n


# --- Dev hooks (wired by devtools; never called by gameplay) ---

## Every fragment recovered without a pickup (the persist id of a placed
## fragment is its fragment id).
static func dev_grant_all_fragments() -> void:
	for s in all_scenes():
		if s.source != MemorySceneData.Source.FRAGMENT:
			continue
		if not Game.state.memory_fragments.has(s.id):
			Game.state.memory_fragments.append(s.id)
		Game.mark_collected(s.id)


## Forget every memory (seen, details, the count); fragments stay recovered.
static func dev_reset() -> void:
	for f: String in Game.state.flags.keys():
		if f.begins_with("mem_seen_") or f.begins_with("mem_detail_") or f == REMEMBERED_FLAG:
			Game.state.flags.erase(f)
			EventBus.flag_changed.emit(f, false)
