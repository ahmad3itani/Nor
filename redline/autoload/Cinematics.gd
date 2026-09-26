extends Node
## Scripted sequences (M8, D-106): the single "is a scene playing" answer for
## BossArena, SliceEndTrigger, SequenceTrigger, the HUD, MenuHost, Playtest
## and tests, without needing Main.tscn (test world roots have no Main).
##
## One locking sequence at a time. A non-locking bark plays only while
## nothing locking is playing and is aborted when a locking one starts.
## Mode (PLAY/AUTO/INSTANT), auto_speed and theatre live in CinematicMode,
## shared with memory scenes; the properties here just delegate.

## SeqMark (CaptureTour, tests). Local signal, not EventBus: devtool plumbing.
signal marked(mark: String)
## A step began (inspector, tests).
signal step_started(index: int, label: String)

var mode: CinematicMode.Mode:
	get:
		return CinematicMode.current()
	set(v):
		CinematicMode.set_mode(v)
var auto_speed: float:
	get:
		return CinematicMode.auto_speed
	set(v):
		CinematicMode.auto_speed = v
var theatre: bool:
	get:
		return CinematicMode.theatre
	set(v):
		CinematicMode.theatre = v

var overlay: CinematicOverlay
## The play in progress (locking or bark), or null.
var current: SequencePlayer = null


func _ready() -> void:
	overlay = CinematicOverlay.new()
	overlay.name = "CinematicOverlay"
	add_child(overlay)
	CinematicMode.register_teardown(abort)
	EventBus.room_leaving.connect(func(_room: Node) -> void: abort())


## At exit: static caches hold Resources past shutdown, which the engine
## reports as leaks ("resources still in use at exit"). Clear them here, the
## last story-aware node to leave the tree.
func _exit_tree() -> void:
	CinematicMode._teardowns.clear()
	CinematicMode.clear_config()
	MemoryScenePlayer.active_instance = null
	MemoryLibrary.clear_cache()
	FutureFlagSet.clear_cache()
	ActLibrary.clear_cache()
	EndingResolver.clear_cache()
	SpeakerTable.clear_cache()
	SubtitleStyle.clear_cache()
	WorldMapIndex.clear_cache()
	SliceStats.clear_cache()
	# M9 static caches (T01 lands every line once; later tasks never edit
	# this file). Classes that do not exist yet are called by path.
	BuildInfo.clear_cache()
	Loc.clear_cache()
	RemixLibrary.clear_cache()
	MenuHost.clear_cache()
	DebugOverlay.clear_cache()
	UiTheme.clear_cache()
	NewGamePlus.clear_cache()
	for p: String in ["platform/AchievementLibrary", "platform/StatCatalog", "challenges/ChallengeLibrary",
			"challenges/RankLadder", "challenges/ChallengeConfig", "accessibility/Palette",
			"input/InputBindings", "input/RebindCatalog"]:
		var path := "res://%s.gd" % p
		if ResourceLoader.exists(path):
			(load(path) as GDScript).call("clear_cache")


## Plays `seq` and returns when control is back. In INSTANT mode the result is
## already resolved when this returns (no frame passes); callers still `await`
## it, which then resumes at once. Check result.refused / result.aborted()
## before acting on completion.
func play(seq: SequenceData, ctx: SequenceContext = null) -> SequenceResult:
	if seq == null:
		return _refused("no sequence")
	if ctx == null:
		ctx = SequenceContext.for_room(SceneRouter.current_room as Room)
	# Decided once, before step 0: the context wins (boss arenas set their
	# seen flag before the intro starts), else the seen flag.
	var fv := ctx.first_view == 1 if ctx.first_view >= 0 else first_view(seq)
	var locking := seq.locks_for(fv)
	if is_playing():
		if current.locking or not locking:
			return _refused("'%s' refused: '%s' is playing" % [seq.id, current.seq.id])
		current.abort()
	var p := SequencePlayer.new()
	p.setup(seq, ctx, fv)
	current = p
	add_child(p)
	if p.instant:
		return p.run_instant()
	p.run_timed()
	if not p.done:
		await p.completed
	return p.result


func is_playing() -> bool:
	return is_instance_valid(current) and not current.done


func locks_input() -> bool:
	return is_playing() and current.locking


func hides_hud() -> bool:
	return locks_input() and current.seq.hide_hud


## Every locking play is skippable.
func can_skip() -> bool:
	return locks_input()


## Deferred: the player consumes it at the top of its next unpaused _process,
## so play() never resolves while a menu is still open.
func request_skip() -> void:
	if can_skip():
		current.request_skip()


## Stops the current play: restore only, no finish(), no seen flag.
## The player's restore contract clears `current`; a play a finished-signal
## listener starts from inside that abort stays current.
func abort() -> void:
	var p := current
	if is_playing():
		p.abort()
	if current == p:
		current = null


func first_view(seq: SequenceData) -> bool:
	return not Game.has_flag(seq.effective_seen_flag())


func _refused(why: String) -> SequenceResult:
	push_warning("Cinematics: %s" % why)
	var r := SequenceResult.new()
	r.refused = true
	return r
