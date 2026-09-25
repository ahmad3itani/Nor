class_name ArcTracker
extends Node
## Enters character-arc stages (D-117) as their conditions pass, once each,
## and keeps them: later flag changes never un-enter a stage (a boss restart
## that erases <boss>_defeated keeps Mara's Krail stage). Sibling of
## QuestTracker under the Game autoload. Writes flags only (arc_<npc>_<id>,
## arc_<npc>_stage); beats, bonds and threads are set by the dialogues when
## heard. Never emits hints: people show progress (bible §19).

const ARC_DIR := "res://data/arcs"
## Re-entrancy bound: entering a stage sets flags, which emit flag_changed,
## which asks for another pass (spine chains are short; 16 is generous).
const MAX_PASSES := 16
## Families dev_reset erases (every flag an arc produces or a choice sets).
const RESET_PREFIXES: PackedStringArray = ["arc_", "arcbeat_", "bond_", "thread_", "orr_air_"]

var arcs: Array[NpcArc] = []
## How many evaluate() calls arrived, and how many of them were on_load
## (tests prove every signal reaches evaluate).
var evaluate_count: int = 0
var load_evaluate_count: int = 0

var _evaluating: bool = false
var _dirty: bool = false
var _suspended: bool = false


func _ready() -> void:
	for path in DataDir.list(ARC_DIR):
		var a := load(path) as NpcArc
		if a:
			arcs.append(a)
	# Every connection ends in evaluate(false) through a lambda matching the
	# signal's arity: a direct connect would bind the signal's first argument
	# (a String or Node) into the bool on_load parameter.
	EventBus.flag_changed.connect(func(_id: String, _v: Variant) -> void: evaluate(false))
	EventBus.secret_found.connect(func(_id: String) -> void: evaluate(false))
	EventBus.memory_fragment_found.connect(func(_f: Resource) -> void: evaluate(false))
	EventBus.circuit_granted.connect(func(_id: String) -> void: evaluate(false))
	EventBus.room_entered.connect(func(_d: String, _r: String) -> void: evaluate(false))
	EventBus.anchor_rested.connect(func(_a: Node) -> void: evaluate(false))
	# Core Shards and other pickups change counts without a flag, so count:
	# reactions enter on the pickup frame, not at the next room change.
	EventBus.collectible_taken.connect(func(_id: String, _kind: int) -> void: evaluate(false))
	# New game / load: an older save catches up quietly (on_load = true;
	# telemetry ignores those entries).
	EventBus.game_state_reset.connect(evaluate.bind(true))


func arc(npc_id: String) -> NpcArc:
	for a in arcs:
		if a.npc_id == npc_id:
			return a
	return null


## Re-entrant-safe: flags set while entering stages emit flag_changed, which
## lands here again; those calls only mark the pass dirty and the outer loop
## re-runs (at most MAX_PASSES).
func evaluate(on_load: bool = false) -> void:
	evaluate_count += 1
	if on_load:
		load_evaluate_count += 1
	if _suspended:
		return
	if _evaluating:
		_dirty = true
		return
	_evaluating = true
	_dirty = true
	var passes := 0
	while _dirty and passes < MAX_PASSES:
		_dirty = false
		passes += 1
		for a in arcs:
			_advance(a, on_load)
	_evaluating = false


## Spine: enter stages in order while the next one's conditions pass.
## Reactions: any unreached one whose spine minimum is met and conditions pass.
func _advance(a: NpcArc, on_load: bool) -> void:
	var i := a.current_index()
	while i < a.stages.size() and a.stages[i].conditions_pass():
		_enter(a, a.stages[i], on_load)
		i += 1
		Game.set_flag(a.index_flag(), i)
	for s in a.reactions:
		if not a.is_reached(s) and a.current_index() >= s.min_stage and s.conditions_pass():
			_enter(a, s, on_load)


## Stage flag FIRST (same reason as QuestTracker._complete: the flags set
## next re-enter evaluate), then the stage's own flags, then the signal.
func _enter(a: NpcArc, s: NpcArcStage, on_load: bool) -> void:
	if a.is_reached(s):
		return
	Game.set_flag(a.stage_flag(s.id))
	for f in s.set_flags:
		Game.set_flag(f)
	EventBus.arc_stage_entered.emit(a.npc_id, s.id, on_load)


# --- Dev hooks (DevActions wires them; gameplay never calls these) ---

## Enters a stage regardless of its conditions. A spine stage also enters
## every earlier spine stage and raises the index to it.
func force_stage(npc_id: String, stage_id: String) -> void:
	var a := arc(npc_id)
	if a == null:
		push_warning("ArcTracker.force_stage: no arc '%s'" % npc_id)
		return
	var i := -1
	for k in a.stages.size():
		if a.stages[k].id == stage_id:
			i = k
	if i >= 0:
		for k in i + 1:
			_enter(a, a.stages[k], false)
		if a.current_index() < i + 1:
			Game.set_flag(a.index_flag(), i + 1)
		return
	for s in a.reactions:
		if s.id == stage_id:
			_enter(a, s, false)
			return
	push_warning("ArcTracker.force_stage: arc '%s' has no stage '%s'" % [npc_id, stage_id])


## One line per arc: "mara 2/2 +eyes +seen_one [beat pending]".
func summary() -> String:
	var out := PackedStringArray()
	for a in arcs:
		var line := "%s %d/%d" % [a.npc_id, a.current_index(), a.stages.size()]
		for s in a.reactions:
			if a.is_reached(s):
				line += " +%s" % s.id
		if a.has_pending_beat():
			line += " [beat pending]"
		out.append(line)
	return "\n".join(out)


## Forgets every arc flag (stages, beats, bonds, threads, the Orr choice),
## then re-evaluates once, so arcs restart from the current world state.
func dev_reset() -> void:
	_suspended = true
	var erased := PackedStringArray()
	for f: String in Game.state.flags.keys():
		for p in RESET_PREFIXES:
			if f.begins_with(p):
				erased.append(f)
				break
	for f in erased:
		Game.state.flags.erase(f)
	for f in erased:
		EventBus.flag_changed.emit(f, false)
	_suspended = false
	evaluate(false)
