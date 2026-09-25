class_name EndingDirector
extends RefCounted
## Plays one ending (sequence + credits) and reports it on the EventBus.
##
## theatre = a dev replay (Ending theatre, tests, the story tour): it runs in
## a FlagSandbox and with CinematicMode.theatre on (trigger autoplay and
## sequence telemetry off), and both are restored on every path, so a replay
## never marks the profile (D-128). A real play (the future Act V finale)
## takes no sandbox: the sequence's seen_flag ending_seen_<id> is set on
## finish or skip and stays.
##
## Lifetime (K-M8-23): in 4.3 a RefCounted nobody references is freed at its
## first await and its coroutine never resumes, which would leave theatre on
## and the sandbox open. play() therefore keeps itself in _running until it
## returns, so fire-and-forget callers (`EndingDirector.new().play(e, true)`)
## are safe.

static var _running: Array[EndingDirector] = []


func play(e: EndingData, theatre: bool) -> SequenceResult:
	_running.append(self)
	var restore := Callable()
	var theatre_was := CinematicMode.theatre
	if theatre:
		restore = FlagSandbox.begin()
		CinematicMode.theatre = true
	var room: Room = null
	if is_instance_valid(SceneRouter.current_room) and SceneRouter.current_room is Room:
		room = SceneRouter.current_room as Room
	EventBus.ending_started.emit(e.id, theatre)
	var res: SequenceResult = await Cinematics.play(e.sequence, SequenceContext.for_overlay(room))
	# A refused play never ran; an aborted one ran none of its effects and
	# replays later: neither is a finished ending.
	if not res.refused and not res.aborted():
		EventBus.ending_finished.emit(e.id, theatre, res.skipped)
	if theatre:
		CinematicMode.theatre = theatre_was
		restore.call()
	_running.erase(self)
	return res


## Plays in flight (tests: empty once every play returned).
static func running_count() -> int:
	return _running.size()
