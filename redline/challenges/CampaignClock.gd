class_name CampaignClock
extends RefCounted
## Campaign in-game time and speedrun splits (M9 D2 §3.6, §6.6, §7.1).
## Game.state.igt_frames counts one per physics tick while no challenge runs,
## a world room (not a lab, not an off-map challenge room) is loaded, no
## transition runs and the tree is not paused. Scripted scenes DO count:
## they can be skipped (§24), so skipping is part of the route.
##
## Splits come from a SplitList (T08's data/challenges/splits/act1_campaign
## .tres, loaded when present); each fires once per profile, in list order
## (out of order: recorded with no delta). The act1_end split posts the
## campaign best, but only for profiles begun after M9 (igt_complete): older
## saves would undercount.
##
## Neutral tags (D-149, R04.16/R04.29): the assists in use, "hitstop_reduced"
## and "checkpoints" are unioned into Game.state.igt_tags while the clock
## counts. They are recomputed on settings_changed and at session start, not
## per frame.

const SPLITS_FMT := "res://data/challenges/splits/%s.tres"
const DEFAULT_LIST := "act1_campaign"
const TAG_HITSTOP := "hitstop_reduced"
const TAG_CHECKPOINTS := "checkpoints"

## Tests set it; otherwise loaded lazily from data when the file exists.
var split_list: SplitList = null
## () -> PackedStringArray (Challenges.tag_provider).
var tag_provider: Callable = func() -> PackedStringArray: return Settings.active_assists()
## Challenges.records (bests and deltas).
var records: RecordStore = null

var _list_loaded: bool = false
var _tags: PackedStringArray = PackedStringArray()
var _union_pending: bool = true


func splits() -> SplitList:
	if split_list == null and not _list_loaded:
		_list_loaded = true
		var p := SPLITS_FMT % DEFAULT_LIST
		if ResourceLoader.exists(p):
			split_list = load(p) as SplitList
	return split_list


## Whether this physics tick counts toward campaign IGT.
func counts() -> bool:
	if Challenges.active() or SceneRouter.transitioning:
		return false
	if SceneRouter.current_room == null or not is_instance_valid(SceneRouter.current_room):
		return false
	var room := SceneRouter.current_room as Room
	if room == null or not room.world_room:
		return false
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.paused:
		return false
	return not _off_map(SceneRouter.current_room_path)


static func _off_map(path: String) -> bool:
	for d in ContentValidator.OFF_MAP_DIRS:
		if path.begins_with(d + "/"):
			return true
	return false


func tick() -> void:
	if not counts():
		return
	Game.state.igt_frames += 1
	if _union_pending:
		_union_pending = false
		for t in _tags:
			if not Game.state.igt_tags.has(t):
				Game.state.igt_tags.append(t)


## The neutral tags in use now (assists + timing tags). Challenge runs never
## carry "checkpoints" (they own their deaths), only the campaign does.
func current_tags() -> PackedStringArray:
	var out := PackedStringArray()
	if tag_provider.is_valid():
		out.append_array(tag_provider.call())
	if Settings.hitstop_scale < 1.0:
		out.append(TAG_HITSTOP)
	if Settings.generous_checkpoints:
		out.append(TAG_CHECKPOINTS)
	return out


## settings_changed / game_state_reset: re-read the tags; the next counted
## frame unions them into the profile.
func refresh_tags() -> void:
	_tags = current_tags()
	_union_pending = not _tags.is_empty()


## Checks every split condition (flag_changed, room entry).
func check_splits() -> void:
	if not _eligible():
		return
	var list := splits()
	if list == null:
		return
	for s in list.splits:
		if s == null or Game.state.igt_splits.has(s.id):
			continue
		var hit := Game.check_condition(s.when) if s.when != "" else s.room == SceneRouter.current_room_path
		if hit:
			_fire(s.id, _in_order(list, s.id))


## A world room entry: room splits of the list, plus the display-only
## per-room splits when the list asks for them (R04.17).
func note_room(path: String) -> void:
	if not _eligible():
		return
	check_splits()
	var list := splits()
	if list == null or not list.auto_room_splits or not SliceStats.room_paths().has(path):
		return
	var id := "room:" + path.get_file().get_basename()
	if not Game.state.igt_splits.has(id):
		_fire(id, true)


func _eligible() -> bool:
	return not Challenges.active() and not CinematicMode.theatre and Game.held_profile == null


static func _in_order(list: SplitList, id: String) -> bool:
	for s in list.splits:
		if s == null:
			continue
		if s.id == id:
			return true
		if not Game.state.igt_splits.has(s.id):
			return false
	return true


func _fire(id: String, in_order: bool) -> void:
	var igt := Game.state.igt_frames
	Game.state.igt_splits[id] = igt
	var delta := 0
	if in_order and records:
		var best := records.campaign_best_splits(Game.profile_id)
		if best.has(id):
			delta = igt - int(best[id])
	EventBus.speedrun_split.emit(id, igt, delta)
	if id == SplitList.END_SPLIT and Game.state.igt_complete and records:
		records.submit_campaign(Game.profile_id, igt, Game.state.igt_splits, Game.state.igt_tags)
