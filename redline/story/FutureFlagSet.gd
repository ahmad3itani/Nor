class_name FutureFlagSet
extends Resource
## Flags that later acts will produce (Acts II-V, M9 The Null; D-127).
## Declaring them lets ending data carry its real conditions today while no
## built content can satisfy them: the endings are unreachable by
## construction. Each entry names the act that must produce it; remove the
## entry when that act lands (T10's validator rules then flag any real
## producer or any Act I reader).
##
## planned_* are reachability bounds, not tuning (D-129): an ending may ask
## for at most what the full game plans to build.

const PATH := "res://data/story/future_flags.tres"

@export var entries: Array[FutureFlag] = []
## Memory scenes planned beyond the built ones.
@export var planned_memories: int = 0
## "arc_<npc>_stage" -> final spine index planned for the full game.
@export var planned_arc_stages: Dictionary = {}

static var _shared: FutureFlagSet = null


## The shipped set (loaded once). An empty set when the file is missing.
static func shared() -> FutureFlagSet:
	if _shared == null:
		_shared = load(PATH) as FutureFlagSet if ResourceLoader.exists(PATH) else null
		if _shared == null:
			_shared = FutureFlagSet.new()
	return _shared


func flags() -> PackedStringArray:
	var out := PackedStringArray()
	for e in entries:
		if e != null and e.flag != "":
			out.append(e.flag)
	return out


func has_flag(flag: String) -> bool:
	return flags().has(flag)


## Act that produces `flag`, or 0 when it is not a future flag.
func act_of(flag: String) -> int:
	for e in entries:
		if e != null and e.flag == flag:
			return e.act
	return 0


## True when a Game.check_condition expression reads a future flag.
func is_future_condition(expr: String) -> bool:
	var e := expr.trim_prefix("!")
	if e.begins_with("flag:") or e.begins_with("atleast:"):
		return has_flag(e.get_slice(":", 1))
	return false


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var seen := {}
	for i in entries.size():
		var e := entries[i]
		if e == null:
			errors.append("future flag entry %d is empty" % i)
			continue
		if e.flag == "":
			errors.append("future flag entry %d has no flag" % i)
		elif seen.has(e.flag):
			errors.append("future flag '%s' is declared twice" % e.flag)
		seen[e.flag] = true
		if not FutureFlag.VALID_ACTS.has(e.act):
			errors.append("future flag '%s': act %d is not 2..5 or 9" % [e.flag, e.act])
		if e.note.length() > FutureFlag.NOTE_MAX:
			errors.append("future flag '%s': note is %d chars (max %d)" % [e.flag, e.note.length(), FutureFlag.NOTE_MAX])
	if planned_memories < 0:
		errors.append("planned_memories is negative")
	for k: Variant in planned_arc_stages:
		var key := String(k)
		if not (key.begins_with("arc_") and key.ends_with("_stage")):
			errors.append("planned_arc_stages key '%s' is not arc_<npc>_stage" % key)
		elif typeof(planned_arc_stages[k]) != TYPE_INT or int(planned_arc_stages[k]) < 1:
			errors.append("planned_arc_stages['%s'] must be an int >= 1" % key)
	return errors


## Resource content protocol: every entry counts as produced (by this file),
## so ending conditions that read them have a producer in the flag lint.
func content_flags() -> Dictionary:
	return {"produces": Array(flags()), "consumes": [], "conditions": []}
