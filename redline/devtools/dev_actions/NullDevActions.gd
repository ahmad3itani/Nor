class_name NullDevActions
extends RefCounted
## Dev helpers for the Deep Rig strata (M9 D3 §3.12; 'null' is an internal
## id). Debug builds only (DevActions.available()). Anything that fabricates
## progress (null_open, the depth flag) taints the profile (D-145), so it
## never earns achievements or records an unlock.

const DEPTH_FLAG := "null_depth_reached"
const OPEN_FLAG := "null_open"


## Every NULL-group challenge, in menu order (the descent first).
static func challenges() -> Array[ChallengeData]:
	var out: Array[ChallengeData] = []
	for ch in ChallengeLibrary.all():
		if ch.group == ChallengeData.Group.NULL:
			out.append(ch)
	return out


## Starts a stratum or the descent, ignoring its unlock and its Dash
## requirement (a copy without `requires`; the id, and so the records, stay).
## Returns to the current room's last entry on quit.
static func start(id: String) -> bool:
	if not DevActions.available():
		return false
	var ch := ChallengeLibrary.by_id(id)
	if ch == null:
		return false
	var run := ch.duplicate() as ChallengeData
	run.requires = PackedStringArray()
	return Challenges.start(run, return_point())


## Where a dev-started run returns: the room Rook stands in, at its last entry.
static func return_point() -> Dictionary:
	var path := SceneRouter.current_room_path
	if path == "":
		return {}
	var entry := Game.state.last_entry_id if Game.state.last_entry_room == path else ""
	return {"room": path, "entry": StringName(entry)}


static func grant_open() -> void:
	if DevActions.available():
		Game.state.dev_tainted = true
		Game.set_flag(OPEN_FLAG)


## Sets or clears the depth flag (the redline ending reads it; D-154).
static func set_depth(on: bool) -> void:
	if DevActions.available():
		Game.state.dev_tainted = true
		Game.set_flag(DEPTH_FLAG, on)


## Clears every Deep Rig board, stage best and PB ghost.
static func clear_records() -> void:
	if not DevActions.available():
		return
	for ch in challenges():
		Challenges.records.clear(ch.id)


## One line for the page and the log.
static func summary() -> String:
	var parts := PackedStringArray()
	parts.append("null_open %s" % ("yes" if Game.has_flag(OPEN_FLAG) else "no"))
	parts.append("depth %s" % ("yes" if Game.has_flag(DEPTH_FLAG) else "no"))
	parts.append("dash %s" % ("yes" if Game.abilities and Game.abilities.dash else "no"))
	for ch in challenges():
		var best := Challenges.records.best(ch.id, Game.profile_id, ch.revision)
		if not best.is_empty():
			parts.append("%s %s" % [ch.id.trim_prefix("null_"), RankLadder.name(int(best.get("medal", -1)))])
	return " · ".join(parts)
