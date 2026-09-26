class_name ChallengeLibrary
extends RefCounted
## Every challenge (M9 D2), read from data_dir through DataDir (exported builds
## list .remap files), cached, sorted by group then sort_order. Challenges a
## build cannot reach (a demo room set, BuildInfo.room_allowed) are dropped
## here, so no menu ever offers one (R05.1).
##
## Unlocks (R04.6/R04.27): a challenge is unlocked once its unlock_when held
## on the profile; the first time is recorded in the global RecordStore
## (ever_unlocked), so NG+ (which clears *_defeated flags) never re-locks it.
## The training rig itself only opens after the Act I close (act1_complete,
## or any NG+ cycle), so the title row and the Relay terminal stay hidden on
## a first playthrough even though a rematch unlocks earlier.

const DEFAULT_DIR := "res://data/challenges"

## Test seam (R04.22): tests point it at res://tests/fixtures/challenges.
static var data_dir: String = DEFAULT_DIR

static var _all: Array[ChallengeData] = []
static var _dir_loaded: String = ""


## Allowed challenges, sorted by group, sort_order, id.
static func all() -> Array[ChallengeData]:
	var out: Array[ChallengeData] = []
	for ch in _load_all():
		if allowed(ch):
			out.append(ch)
	return out


## Whether every room the run loads or ends at exists in this build.
static func allowed(ch: ChallengeData) -> bool:
	for p in ch.room_paths():
		if p != "" and not BuildInfo.room_allowed(p):
			return false
	return true


static func _load_all() -> Array[ChallengeData]:
	if _dir_loaded == data_dir:
		return _all
	_all = []
	_dir_loaded = data_dir
	for path in DataDir.list(data_dir):
		var ch := load(path) as ChallengeData
		if ch:
			_all.append(ch)
	_all.sort_custom(func(a: ChallengeData, b: ChallengeData) -> bool:
		if a.group != b.group:
			return a.group < b.group
		if a.sort_order != b.sort_order:
			return a.sort_order < b.sort_order
		return a.id < b.id)
	return _all


## By id among every loaded challenge (demo-filtered ones included: start()
## refuses those itself). Named by_id: a static get() would shadow Object.get.
static func by_id(id: String) -> ChallengeData:
	for ch in _load_all():
		if ch.id == id:
			return ch
	return null


## Unlocked for the live profile (sticky: RecordStore.ever_unlocked).
static func unlocked(ch: ChallengeData) -> bool:
	return Challenges.records.ever_unlocked(ch.id) or profile_holds(ch.unlock_when)


## The locked row may show its title and hint.
static func revealed(ch: ChallengeData) -> bool:
	return unlocked(ch) or profile_holds(ch.reveal_condition())


static func rig_open() -> bool:
	return profile_holds("flag:act1_complete") or _profile_flag_int("ng_cycle") >= 1


static func rig_open_for(data: Dictionary) -> bool:
	var flags: Dictionary = data.get("flags", {})
	return bool(flags.get("act1_complete", false)) or int(flags.get("ng_cycle", 0)) >= 1


static func any_unlocked() -> bool:
	if not rig_open():
		return false
	return all().any(func(ch: ChallengeData) -> bool: return unlocked(ch))


## The same rule on a peeked save (the title row, before any load).
static func any_unlocked_for(data: Dictionary) -> bool:
	if data.is_empty() or not rig_open_for(data):
		return false
	var list := all()
	if list.any(func(ch: ChallengeData) -> bool: return Challenges.records.ever_unlocked(ch.id)):
		return true
	return _with_state(GameState.from_dict(data), func() -> bool:
		return list.any(func(ch: ChallengeData) -> bool: return Game.check_condition(ch.unlock_when)))


## Unlock conditions read the PROFILE, even mid-run (the sandbox holds kit
## flags such as collector_drone_defeated).
static func profile_holds(expr: String) -> bool:
	if Game.held_profile == null:
		return Game.check_condition(expr)
	return _with_state(Game.held_profile, func() -> bool: return Game.check_condition(expr))


static func _profile_flag_int(id: String) -> int:
	var s := Game.held_profile if Game.held_profile != null else Game.state
	return int(s.flags.get(id, 0))


## Evaluates `fn` against another GameState (and its abilities) without any
## signal: Game.check_condition reads Game.state and Game.abilities.
static func _with_state(s: GameState, fn: Callable) -> bool:
	var saved_state := Game.state
	var saved_abilities := Game.abilities
	Game.state = s
	Game.abilities = ProfileSandbox.kit_abilities(s)
	var r := bool(fn.call())
	Game.state = saved_state
	Game.abilities = saved_abilities
	return r


## Records every challenge whose condition holds on the profile now. Returns
## the newly recorded ids. Never from fabricated states (R04.19): not in
## theatre, not on a dev-tainted profile, not during a run.
static func record_unlocks() -> PackedStringArray:
	var out := PackedStringArray()
	if CinematicMode.theatre or Challenges.active() or Game.held_profile != null or Game.state.dev_tainted:
		return out
	for ch in all():
		if not Challenges.records.ever_unlocked(ch.id) and Game.check_condition(ch.unlock_when):
			Challenges.records.record_unlock(ch.id)
			out.append(ch.id)
	return out


## Groups with at least one unlocked challenge.
static func unlocked_groups() -> Array[int]:
	var out: Array[int] = []
	for ch in all():
		if not out.has(ch.group) and unlocked(ch):
			out.append(ch.group)
	return out


static func group_title(group: int) -> String:
	var titles := ChallengeConfig.shared().group_titles
	return titles[group] if group >= 0 and group < titles.size() else ""


static func clear_cache() -> void:
	_all = []
	_dir_loaded = ""
