class_name SequencePlayer
extends Node
## Runs one SequenceData against a SequenceContext (created by Cinematics).
##
## PROCESS_MODE_PAUSABLE with its own clock: under the PauseMenu or a
## DialogueBox the clock, the tweens (made on this node) and every wait
## freeze. AUTO mode scales the clock by CinematicMode.auto_speed.
##
## End paths (every one runs the restore contract):
## - normal end / skip / INSTANT: every remaining eligible step's finish()
##   runs (skip, INSTANT), the seen flag is set, telemetry reports it;
## - abort (room left, Save & Quit, test teardown): no finish(), no seen
##   flag, step_index -1. The scene replays from its start later.

signal ticked(delta: float)
signal completed

const HUD_OWNER := &"sequence"

var seq: SequenceData
var ctx: SequenceContext
var first_view: bool = true
var locking: bool = true
var instant: bool = false
var result := SequenceResult.new()
var index: int = -1
var gate: SkipGate = null
var skipping: bool = false
var done: bool = false

var _clock: float = 0.0
var _real: float = 0.0
var _aborted: bool = false
var _skip_requested: bool = false
var _tap: bool = false
var _last_frame: int = 0
var _tweens: Array[Tween] = []
## Non-blocking steps whose run() has not completed (finish()ed at the end).
var _parallel: Array[SequenceStep] = []
## Abort restores: [object, property, value] recorded by actor steps before
## they first touch a node, put back in reverse order by abort() only.
var _abort_restores: Array = []
var _memo: Dictionary = {}
var _lock_source := ScriptedInputSource.new()
var _camera_used: bool = false
var _music_used: bool = false
var _hud_pushed: bool = false
var _step_count: int = 0
var _nominal: float = 0.0


func setup(s: SequenceData, c: SequenceContext, is_first_view: bool) -> void:
	seq = s
	ctx = c
	first_view = is_first_view
	locking = s.locks_for(is_first_view)
	instant = CinematicMode.current() == CinematicMode.Mode.INSTANT
	result.instant = instant
	_step_count = s.steps.size()
	_nominal = s.nominal_seconds(is_first_view)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	name = "Seq_%s" % s.id


# --- Clock and helpers for steps --------------------------------------------------

func clock() -> float:
	return _clock


func speed() -> float:
	return CinematicMode.auto_speed if CinematicMode.current() == CinematicMode.Mode.AUTO else 1.0


func is_auto() -> bool:
	return CinematicMode.current() == CinematicMode.Mode.AUTO


func interrupted() -> bool:
	return skipping or _aborted or not is_inside_tree()


## True once abort() ran: steps must not finish() themselves afterwards.
func aborted() -> bool:
	return _aborted


func overlay() -> CinematicOverlay:
	return Cinematics.overlay


func wait(seconds: float) -> void:
	var end := _clock + seconds
	while _clock < end and not interrupted():
		await ticked


## Waits until a tween ends (or the play is interrupted).
func wait_tween(t: Tween) -> void:
	while t != null and t.is_valid() and t.is_running() and not interrupted():
		await ticked


## Tracks a tween so skip/abort/end can kill it, runs it at AUTO speed and
## freezes it while the tree is paused (overlay tweens run ALWAYS otherwise).
func adopt(t: Tween) -> Tween:
	if t:
		t.set_speed_scale(speed())
		t.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
		_tweens.append(t)
	return t


## Paces the line the overlay shows (SeqLine): typed at cfg.type_cps, on
## screen for `hold` seconds. A TAP completes the typing, then advances early;
## on a first view only once the full line has been up for cfg.early_fraction of
## its hold, so a mashing first-timer cannot race through the only telling.
## A hold of the button never advances (the SkipGate reports it as a skip).
func pace_line(length: int, hold: float, wait_for_tap: bool) -> void:
	var ov := overlay()
	var cfg := CinematicMode.config()
	var typed_at := _clock
	var full_at := -1.0
	var start := _clock
	_tap = false
	while not interrupted():
		var shown := mini(length, int((_clock - typed_at) * cfg.type_cps))
		if shown >= length and full_at < 0.0:
			full_at = _clock
		if take_tap():
			if full_at < 0.0:
				typed_at = _clock - length / cfg.type_cps
				full_at = _clock
				shown = length
			elif not first_view or _clock - full_at >= cfg.early_fraction * hold:
				return
		if is_instance_valid(ov):
			ov.set_visible_chars(shown)
		# No SkipGate (a non-locking play) means no tap can arrive: never wait for one.
		if not (wait_for_tap and gate != null and not is_auto()) and _clock - start >= hold:
			return
		await ticked


## Consumes a TAP the SkipGate reported this play (SeqLine advance).
func take_tap() -> bool:
	var t := _tap
	_tap = false
	return t


## Per-play scratch space for shared step Resources.
func memo(step: SequenceStep, key: String, value: Variant = null) -> Variant:
	var k := "%d:%s" % [step.get_instance_id(), key]
	if value != null:
		_memo[k] = value
	return _memo.get(k)


## Records `obj.prop` before an actor step first changes it, so an abort (a
## locking play cutting a bark, or a room abort) leaves no NPC displaced or
## tinted. A skip or a normal end never uses it: finish() owns the end state.
func note_abort_restore(obj: Object, prop: StringName) -> void:
	for r: Array in _abort_restores:
		if r[0] == obj and r[1] == prop:
			return
	_abort_restores.append([obj, prop, obj.get(prop)])


func lock_source() -> ScriptedInputSource:
	return _lock_source


func note_camera() -> void:
	_camera_used = true


func set_music(state: int) -> void:
	_music_used = true
	MusicDirector.set_override(state)


func clear_music() -> void:
	MusicDirector.clear_override()


func request_skip() -> void:
	if locking and not done:
		_skip_requested = true


# --- Run ------------------------------------------------------------------------------

## INSTANT: every eligible step's finish() in this call; no frame passes.
func run_instant() -> SequenceResult:
	_begin()
	for i in seq.steps.size():
		var s := seq.steps[i]
		if _eligible(s):
			index = i
			Cinematics.step_started.emit(i, s.label)
			s.finish(self)
	_end(false)
	return result


func run_timed() -> void:
	_begin()
	_last_frame = Engine.get_process_frames()
	if locking:
		gate = SkipGate.new(first_view)
		if seq.letterbox and is_instance_valid(overlay()):
			adopt(overlay().letterbox(true, CinematicMode.config().letterbox_seconds))
	for i in seq.steps.size():
		if interrupted():
			break
		var s := seq.steps[i]
		if not _eligible(s):
			continue
		index = i
		_tap = false
		Cinematics.step_started.emit(i, s.label)
		if s.blocking:
			await s.run(self)
		else:
			_run_parallel(s)
	if _aborted or done:
		return
	if skipping:
		# step_index reports where the skip landed (K-S2), not the last step.
		var skipped_at := index
		_finish_from(index)
		index = skipped_at
	else:
		_kill_tweens()
		for s in _parallel.duplicate():
			s.finish(self)
	_end(skipping)


## A non-blocking step leaves _parallel once its run() completes, so the
## end/skip does not finish() it a second time.
func _run_parallel(s: SequenceStep) -> void:
	_parallel.append(s)
	await s.run(self)
	if not interrupted():
		_parallel.erase(s)


func _eligible(s: SequenceStep) -> bool:
	return s != null and s.plays_in_view(first_view) and Game.check_condition(s.only_when)


func _begin() -> void:
	if locking and ctx and is_instance_valid(ctx.player):
		ctx.player.input_override = _lock_source
		ctx.player.cinematic_lock = true
	if locking and seq.hide_hud:
		CinematicMode.push_hud_hide(HUD_OWNER)
		_hud_pushed = true
		EventBus.interact_prompt_changed.emit("")
	EventBus.sequence_started.emit(seq.id, first_view)


## Skip: every remaining eligible step (the interrupted one included) and
## every parallel step ends in its finish() state, in order.
func _finish_from(from: int) -> void:
	_kill_tweens()
	for s in _parallel.duplicate():
		s.finish(self)
	for i in range(maxi(from, 0), seq.steps.size()):
		var s := seq.steps[i]
		if _eligible(s):
			s.finish(self)


func _process(delta: float) -> void:
	if done:
		return
	var frame := Engine.get_process_frames()
	if gate and frame - _last_frame > 1:
		# The tree was paused (PauseMenu, DialogueBox): the Resume press is
		# never a skip or an advance.
		gate.notify_unpaused()
	_last_frame = frame
	if _skip_requested:
		_skip_requested = false
		skipping = true
	if gate and not skipping:
		match SkipGate.poll(gate, delta):
			SkipGate.Out.SKIP:
				skipping = true
			SkipGate.Out.TAP:
				_tap = true
		var ov := overlay()
		if ov:
			ov.set_skip_prompt(gate.prompt_text(), gate.progress_ratio(), gate.prompt_visible and not skipping)
	_real += delta
	_clock += delta * speed()
	ticked.emit(delta * speed())


## Stops without running any step's finish() and without the seen flag.
func abort() -> void:
	if done:
		return
	_aborted = true
	index = -1
	_kill_tweens()
	for i in range(_abort_restores.size() - 1, -1, -1):
		var r: Array = _abort_restores[i]
		if is_instance_valid(r[0]):
			(r[0] as Object).set(r[1], r[2])
	_abort_restores.clear()
	_end(false)
	# Wake the suspended step so its coroutine returns (it sees interrupted()).
	ticked.emit(0.0)


func _kill_tweens() -> void:
	for t in _tweens:
		if t and t.is_valid():
			t.kill()
	_tweens.clear()


func _end(was_skipped: bool) -> void:
	if done:
		return
	done = true
	result.skipped = was_skipped and not _aborted
	result.seconds = 0.0 if instant else _real
	result.step_index = -1 if _aborted else maxi(index, 0)
	if not _aborted:
		Game.set_flag(seq.effective_seen_flag())
	_restore()
	EventBus.sequence_finished.emit(seq.id, result.skipped, result.seconds, result.step_index, _step_count, _nominal)
	completed.emit()
	if is_inside_tree():
		queue_free()


## The restore contract: runs on every path, each line guarded on its own.
func _restore() -> void:
	if ctx and is_instance_valid(ctx.player) and ctx.player.input_override == _lock_source:
		ctx.player.input_override = null
	if ctx and is_instance_valid(ctx.player) and locking:
		ctx.player.cinematic_lock = false
	if ctx and is_instance_valid(ctx.camera) and (_camera_used or ctx.camera.is_directed()):
		ctx.camera.release(0.0)
		ctx.camera.snap_to_target()
	if _music_used:
		MusicDirector.clear_override()
	var ov := overlay()
	if is_instance_valid(ov):
		ov.clear_all(CinematicMode.config().letterbox_seconds if (locking and seq.letterbox and not instant and not _aborted) else 0.0)
	if _hud_pushed:
		CinematicMode.pop_hud_hide(HUD_OWNER)
		_hud_pushed = false
	CinematicMode.bark_line = false
	if Cinematics.current == self:
		Cinematics.current = null
