class_name EndingData
extends Resource
## One of the four endings (bible §18, D-126). Conditions are data
## (Game.check_condition expressions). An ending plays only when its Act V
## choice is made *and* every requirement holds. Until Act V exists, every
## ending needs at least one flag from data/story/future_flags.tres, which
## nothing produces (unreachable by construction, D-127; content_check and
## test_endings enforce it).
##
## requires_memories / requires_arcs are separate fields although they are
## plain conditions too: §18 says Release "requires memories and NPC quest
## states", so the lint can insist Release keeps both, and the theatre groups
## the checklist under Memories and People.

const TITLE_MAX := 16
const TAGLINE_MAX := 60
## Ending sequences may only draw on the overlay (SequenceContext.for_overlay
## resolves no actor) and change nothing play reads.
const FORBIDDEN_STEPS: PackedStringArray = ["SeqCamera", "SeqRookPose", "SeqFlag"]
const FORBIDDEN_PREFIX := "SeqActor"
const MAX_BUDGET := 90.0

## == file basename: sever, crown, release, redline.
@export var id: String = ""
## "SEVER": the title card and the theatre row.
@export var title: String = ""
## Theatre detail only, never shown in play.
@export var tagline: String = ""
## resolve(): the highest passing priority wins (redline 40 > release 30 >
## sever = crown 20).
@export var priority: int = 0
## Never listed as an option before it is offered (the theatre tags it).
@export var hidden: bool = false
## The Act V decision, e.g. "flag:finale_choice_sever" (a future flag).
@export var choice_condition: String = ""
## AND: story/world state ("flag:act5_finale_reached").
@export var requires: PackedStringArray = []
## "" or one "atleast:memories_remembered:N" / "flag:mem_seen_<id>".
@export var requires_memories: String = ""
## AND: "atleast:arc_<npc>_stage:n" / "flag:<npc>_arc_resolved" (people).
@export var requires_arcs: PackedStringArray = []
## Room-independent; last blocking step SeqCredits; seen_flag ending_seen_<id>.
@export var sequence: SequenceData


func seen_flag() -> String:
	return "ending_seen_%s" % id


## [choice] + requires + [requires_memories] + requires_arcs, "" dropped.
func all_conditions() -> PackedStringArray:
	var out := PackedStringArray()
	if choice_condition != "":
		out.append(choice_condition)
	out.append_array(requirements())
	return out


## all_conditions() without the choice (what the finale checks before it
## offers this ending).
func requirements() -> PackedStringArray:
	var out := PackedStringArray()
	for c in requires:
		if c != "":
			out.append(c)
	if requires_memories != "":
		out.append(requires_memories)
	for c in requires_arcs:
		if c != "":
			out.append(c)
	return out


## Context-free rules (A5 §9.4 "per resource").
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == "":
		errors.append("ending without id")
	elif resource_path != "" and resource_path.get_file().get_basename() != id:
		errors.append("ending id '%s' does not match its file name" % id)
	if title.length() < 1 or title.length() > TITLE_MAX:
		errors.append("ending %s: title must be 1..%d chars" % [id, TITLE_MAX])
	elif title != title.to_upper():
		errors.append("ending %s: title must be uppercase" % id)
	if tagline.length() > TAGLINE_MAX:
		errors.append("ending %s: tagline is over %d chars" % [id, TAGLINE_MAX])
	if choice_condition == "":
		errors.append("ending %s: no choice_condition" % id)
	if sequence == null:
		errors.append("ending %s: no sequence" % id)
	if requires_memories != "":
		var m := requires_memories
		var ok := (m.begins_with("atleast:memories_remembered:") and m.get_slice_count(":") == 3 and m.get_slice(":", 2).is_valid_int()) \
			or (m.begins_with("flag:mem_seen_") and m.length() > "flag:mem_seen_".length())
		if not ok:
			errors.append("ending %s: requires_memories must be atleast:memories_remembered:N or flag:mem_seen_<id> (got '%s')" % [id, m])
	for c in requires_arcs:
		var f := c.get_slice(":", 1)
		if not (c.begins_with("atleast:arc_") or c.begins_with("flag:")) or not (f.begins_with("arc_") or f.contains("_arc_")):
			errors.append("ending %s: requires_arcs entry '%s' must read an arc flag" % [id, c])
	for c in all_conditions():
		if not ContentValidator.is_valid_condition(c):
			errors.append("ending %s: invalid condition '%s'" % [id, c])
	return errors


## Resource content protocol: every condition is consumed, so each needs a
## producer (real content or a future_flags.tres declaration).
func content_flags() -> Dictionary:
	return {"produces": [], "consumes": [], "conditions": Array(all_conditions())}


## Context rules: the sequence is overlay-only, the ending needs a future
## flag, §18's Release/Redline requirements hold, and no condition asks for
## more than the full game plans to build.
func content_check() -> PackedStringArray:
	var errors := PackedStringArray()
	var future := FutureFlagSet.shared()
	var conds := all_conditions()
	if not Array(conds).any(func(c: String) -> bool: return future.is_future_condition(c)):
		errors.append("ending '%s' is reachable in the built acts: it needs a future flag (data/story/future_flags.tres)" % id)
	if id == "release" and (requires_memories == "" or requires_arcs.is_empty()):
		errors.append("ending release needs requires_memories and requires_arcs (bible §18)")
	if id == "redline":
		if not hidden:
			errors.append("ending redline must be hidden")
		if not Array(conds).any(func(c: String) -> bool: return c.trim_prefix("!").get_slice(":", 1) == "null_depth_reached"):
			errors.append("ending redline must read null_depth_reached (bible §18 The Null)")
	var bounded := Array(conds)
	if sequence:
		for s in sequence.steps:
			if s != null and s.only_when != "":
				bounded.append(s.only_when)
	for c: String in bounded:
		var why := reach_error(c, future)
		if why != "":
			errors.append("ending %s: '%s' can never be met (%s)" % [id, c, why])
	if sequence:
		errors.append_array(_check_sequence(sequence))
	return errors


## "" when `expr` can be met by the full game as planned, else the reason.
static func reach_error(expr: String, future: FutureFlagSet) -> String:
	if expr.begins_with("!"):
		return ""
	if expr.begins_with("atleast:memories_remembered:"):
		var n := expr.get_slice(":", 2).to_int()
		var most := MemoryLibrary.all_scenes().size() + future.planned_memories
		return "" if n <= most else "%d built + %d planned memories" % [MemoryLibrary.all_scenes().size(), future.planned_memories]
	if expr.begins_with("atleast:arc_") and expr.get_slice(":", 1).ends_with("_stage"):
		var f := expr.get_slice(":", 1)
		if not future.planned_arc_stages.has(f):
			return "no planned_arc_stages entry for %s" % f
		return "" if expr.get_slice(":", 2).to_int() <= int(future.planned_arc_stages[f]) else "planned top stage %d" % int(future.planned_arc_stages[f])
	if expr.begins_with("flag:mem_seen_"):
		var scene_id := expr.trim_prefix("flag:mem_seen_")
		return "" if MemoryLibrary.scene(scene_id) != null else "no memory scene '%s'" % scene_id
	return ""


func _check_sequence(s: SequenceData) -> PackedStringArray:
	var errors := PackedStringArray()
	var tag := "ending %s: sequence %s" % [id, s.id]
	if s.room != "":
		errors.append("%s must be room-independent (room \"\")" % tag)
	if not s.theatre_only:
		errors.append("%s must be theatre_only (no trigger plays an ending)" % tag)
	if s.seen_flag != seen_flag():
		errors.append("%s: seen_flag must be %s" % [tag, seen_flag()])
	var last_blocking: SequenceStep = null
	for i in s.steps.size():
		var st := s.steps[i]
		if st == null:
			continue
		var kind := st.kind()
		if FORBIDDEN_STEPS.has(kind) or kind.begins_with(FORBIDDEN_PREFIX):
			errors.append("%s: step %d (%s) is not allowed in an overlay-only ending" % [tag, i, kind])
		if st.blocking:
			last_blocking = st
	var first: SequenceStep = s.steps[0] if not s.steps.is_empty() else null
	if not (first is SeqFade and is_equal_approx((first as SeqFade).to_alpha, 1.0) and first.only_when == ""):
		errors.append("%s must start with a SeqFade to 1.0 (the room stays covered)" % tag)
	if not (last_blocking is SeqCredits):
		errors.append("%s: the last blocking step must be SeqCredits" % tag)
	var budget := minf(s.budget_seconds, MAX_BUDGET)
	if s.nominal_seconds(true) > budget + 0.001:
		errors.append("%s runs %.1f s, over %.0f s" % [tag, s.nominal_seconds(true), budget])
	return errors
