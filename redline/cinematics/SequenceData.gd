class_name SequenceData
extends Resource
## One scripted sequence (M8, D-106): an ordered list of small steps run by
## the Cinematics autoload. Data lives in data/sequences/<id>.tres.
##
## No validate() on purpose: ContentValidator calls validate() on every
## resource AND content_check() on this protocol, so a rule in both would be
## reported twice. Every rule lives in content_check().

@export var id: String = ""
## Room it is authored for (actor paths and points are room-local); "" =
## room-independent (@ ids only).
@export_file("*.tscn") var room: String = ""
## Spawn DevActions.preview_sequence teleports to.
@export var preview_entry: StringName = &""
@export var steps: Array[SequenceStep] = []
## "" -> "seen_seq_<id>". Boss intros use "<boss_id>_intro_seen".
@export var seen_flag: String = ""
## false = ambient bark: no letterbox, no HUD hide, no lock, no skip.
@export var lock_input: bool = true
## Repeat views lock too. false = repeats play as a non-locking overlay (boss
## intros on a retry: Rook never loses control, §17 "fast restart").
@export var repeat_locks_input: bool = true
@export var hide_hud: bool = true
## Letterbox slides in at the start and out at the end (0.35 s each).
@export var letterbox: bool = true
## Validator: nominal first-view length (subtitle speed x1.0) must fit.
@export var budget_seconds: float = 20.0
## Validator: nominal repeat length for boss intros (seen flag *_intro_seen).
@export var repeat_budget_seconds: float = 1.5
## Endings and test fixtures: no trigger references them (no orphan warning).
@export var theatre_only: bool = false


func effective_seen_flag() -> String:
	return seen_flag if seen_flag != "" else "seen_seq_%s" % id


## Effective locking for one play.
func locks_for(first_view: bool) -> bool:
	return lock_input and (first_view or repeat_locks_input)


## Sum of the blocking steps that play in this view. Steps gated by a
## condition and its negation ("flag:x" / "!flag:x") are alternatives, so
## only the longer side counts; any other gated step counts (worst case).
func nominal_seconds(first_view: bool) -> float:
	var total := 0.0
	var gated := {}  # condition without "!" -> [sum_if_true, sum_if_false]
	for s in steps:
		if s == null or not s.blocking or not s.plays_in_view(first_view):
			continue
		if s.only_when == "":
			total += s.nominal_seconds()
			continue
		var key := s.only_when.trim_prefix("!")
		var side := 1 if s.only_when.begins_with("!") else 0
		if not gated.has(key):
			gated[key] = [0.0, 0.0]
		gated[key][side] += s.nominal_seconds()
	for key: String in gated:
		total += maxf(gated[key][0], gated[key][1])
	return total


func content_flags() -> Dictionary:
	var produces: Array = [effective_seen_flag()]
	var conditions: Array = []
	for s in steps:
		if s == null:
			continue
		var d := s.content_flags()
		produces.append_array(d.get("produces", []))
		conditions.append_array(d.get("conditions", []))
	return {"produces": produces, "consumes": [], "conditions": conditions}


## Every sequence rule (A1 §7.1 + skip safety). Room-bound actor paths are
## checked against the instantiated room, freed here.
func content_check() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == "":
		errors.append("sequence without id")
	if steps.is_empty():
		errors.append("sequence %s has no steps" % id)
	var room_node: Node = null
	if room != "":
		var packed := load(room) as PackedScene if ResourceLoader.exists(room) else null
		if packed == null:
			errors.append("sequence %s: room %s does not load" % [id, room])
		else:
			room_node = packed.instantiate()
	_check_order(errors)
	for view: bool in [true, false]:
		_check_view(errors, view, room_node)
	if room_node:
		room_node.free()
	var unique := PackedStringArray()
	for e in errors:
		if not unique.has(e):
			unique.append(e)
	return unique


func _check_view(errors: PackedStringArray, first_view: bool, room_node: Node) -> void:
	var v := SequenceValidation.new()
	v.seq = self
	v.room = room_node
	v.first_view = first_view
	v.speakers = SpeakerTable.shared()
	var locking := locks_for(first_view)
	var crouched := -1
	for i in steps.size():
		var s := steps[i]
		if s == null or not s.plays_in_view(first_view):
			continue
		v.index = i
		var tag := "step %d (%s)" % [i, s.kind()]
		for e in s.validate(v):
			errors.append("%s: %s" % [tag, e])
		if not locking and s.locking_only():
			if lock_input:
				errors.append("%s: repeat views play without a lock (repeat_locks_input = false) and cannot use camera, pose, letterbox or fade" % tag)
			else:
				errors.append("%s: a non-locking sequence cannot use camera, pose, letterbox or fade" % tag)
		if s is SeqRookPose:
			crouched = i if (s as SeqRookPose).pose == SeqRookPose.Pose.CROUCH else -1
	if crouched >= 0:
		errors.append("step %d (SeqRookPose): CROUCH needs a later STAND" % crouched)
	# Budgets hold for locking and non-locking views alike (a repeat boss
	# intro plays unlocked but must stay short).
	var nominal := nominal_seconds(first_view)
	if first_view and nominal > budget_seconds + 0.001:
		errors.append("first view runs %.1f s, over its %.1f s budget" % [nominal, budget_seconds])
	elif not first_view and effective_seen_flag().ends_with("_intro_seen") and nominal > repeat_budget_seconds + 0.001:
		errors.append("repeat view runs %.1f s, over its %.1f s repeat budget" % [nominal, repeat_budget_seconds])


## Only SeqFlag produces flags, and a step's condition never reads a flag the
## same sequence sets later (a skip would finish() them in order, a watch
## would not see it yet: the two paths must agree).
func _check_order(errors: PackedStringArray) -> void:
	var set_at := {}
	for i in steps.size():
		var s := steps[i]
		if s == null:
			errors.append("step %d is empty" % i)
			continue
		var produces: Array = s.content_flags().get("produces", [])
		if not produces.is_empty() and not (s is SeqFlag):
			errors.append("step %d (%s): only SeqFlag may set flags" % [i, s.kind()])
		for f in produces:
			if not set_at.has(f):
				set_at[f] = i
	for i in steps.size():
		var s := steps[i]
		if s == null or s.only_when == "":
			continue
		var e := s.only_when.trim_prefix("!")
		if e.begins_with("flag:") or e.begins_with("atleast:"):
			var f := e.get_slice(":", 1)
			if set_at.has(f) and int(set_at[f]) >= i:
				errors.append("step %d (%s): only_when reads '%s', set later by step %d" % [i, s.kind(), f, set_at[f]])
