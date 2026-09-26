class_name AchievementTracker
extends Node
## Decides unlocks (M9 D1 §4.3). Child of the Platform autoload. Any event that
## can change a condition or a stat marks the tracker dirty; one deferred pass
## per frame checks every locked achievement (about 30 cheap checks).
##
## Rules:
## - Evaluation waits while Platform.earning_allowed() is false (headless,
##   theatre, dev-tainted profile, challenge run) and keeps the dirty mark, so
##   the pass runs once earning is allowed again (D-145).
## - game_state_reset (load, new game, the Challenges restore) re-evaluates
##   with retroactive = true: an old save earns what it already did (D-143).
##   Only the first full pass after the reset is retroactive; if that pass is
##   fully blocked, the later one is a live pass. An in-run pass keeps the mark.
## - During a challenge run only lifetime-only achievements are evaluated
##   (R02.3): the lifetime whitelist is all a run can change. Their toasts are
##   held by Platform until the result card closes (R02.9).

var _dirty: bool = false
var _retro: bool = false
var _scheduled: bool = false


func _ready() -> void:
	var dirty := func() -> void: mark_dirty()
	EventBus.flag_changed.connect(func(_id: String, _v: Variant) -> void: dirty.call())
	EventBus.collectible_taken.connect(func(_id: String, _k: int) -> void: dirty.call())
	EventBus.secret_found.connect(func(_id: String) -> void: dirty.call())
	EventBus.boss_defeated.connect(func(_id: String) -> void: dirty.call())
	EventBus.circuit_granted.connect(func(_id: String) -> void: dirty.call())
	EventBus.weapon_granted.connect(func(_id: String) -> void: dirty.call())
	EventBus.arc_stage_entered.connect(func(_n: String, _s: String, _l: bool) -> void: dirty.call())
	EventBus.memory_scene_finished.connect(
		func(_i: String, _s: StringName, _k: bool, _t: float, _b: int, _d: bool, _f: bool) -> void: dirty.call())
	EventBus.game_state_reset.connect(func() -> void: mark_dirty(true))


## Something changed; evaluate once at the end of this frame.
func mark_dirty(retro: bool = false) -> void:
	_dirty = true
	if retro:
		_retro = true
	if not _scheduled:
		_scheduled = true
		_evaluate.call_deferred()


## Drops a pending pass (test teardown): nothing carries into the next test.
func reset() -> void:
	_dirty = false
	_retro = false


func is_dirty() -> bool:
	return _dirty


func _process(_delta: float) -> void:
	# A pass skipped while earning was blocked runs as soon as it is allowed
	# (the theatre ends, a dev override flips, a run's restore lands).
	if _dirty and not _scheduled and Platform.earning_allowed():
		mark_dirty()


func _evaluate() -> void:
	_scheduled = false
	if not _dirty:
		return
	# Retroactive means "earned by the load itself": only the first pass after
	# a reset may be, so a pass that was blocked then never marks later,
	# live unlocks as retroactive.
	# A run pass (lifetime-only achievements) leaves the mark for the full
	# pass after the restore, so catch-up unlocks still toast as retroactive.
	var full := Platform.earning_allowed()
	var run_pass := not full and Platform.run_pass_allowed()
	var retro := _retro and full
	if full or not run_pass:
		_retro = false
	if not full and not run_pass:
		return
	for a in AchievementLibrary.all():
		if Platform.is_unlocked(a.id):
			continue
		if run_pass and not a.lifetime_only():
			continue
		if met(a):
			unlock(a, retro)
	if full:
		_dirty = false


## Every condition holds and the stat rule is met.
func met(a: AchievementData) -> bool:
	for c in a.conditions:
		if not Game.check_condition(c):
			return false
	if a.stat_id == &"":
		return true
	var v := Platform.stat(a.stat_id, a.stat_scope == AchievementData.Scope.LIFETIME)
	var def := Platform.stats.catalog.stat(a.stat_id)
	if def != null and def.kind == StatDef.Kind.MIN:
		return v > 0.0 and v <= a.stat_target
	return v >= a.stat_target


func unlock(a: AchievementData, retroactive: bool) -> void:
	Platform.record_unlock(a, retroactive)
