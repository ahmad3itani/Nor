class_name StoryTestKit
extends RefCounted
## Story helpers for tests and CaptureTour (M8, A5 §6.1). Static, no state of
## its own: every helper delegates to the system that owns the rule
## (FlagSandbox, StoryPresets, Cinematics), so tests exercise the real code.

## Snapshot of the profile's flags and play time; call the returned Callable
## to put them back (it emits game_state_reset so the world re-reads).
static func flag_sandbox() -> Callable:
	return FlagSandbox.begin()


static func apply_preset(id: String) -> void:
	StoryPresets.apply(id)


## The "did everything in Act I" profile. The one definition lives in
## FlagSandbox.apply_act1_max_state (T06); this only names it for tests.
static func act1_max_state() -> void:
	FlagSandbox.apply_act1_max_state()


## Plays `id` in AUTO mode at `speed` where Rook is now (first view), then
## puts the previous mode and speed back. Returns the play's result.
static func play_sequence_auto(id: String, speed: float = 4.0) -> SequenceResult:
	var seq := DevActions.sequence(id)
	if seq == null:
		push_warning("StoryTestKit.play_sequence_auto: no sequence '%s'" % id)
		return null
	var was_mode := CinematicMode.current()
	var was_speed := CinematicMode.auto_speed
	CinematicMode.set_mode(CinematicMode.Mode.AUTO)
	CinematicMode.auto_speed = speed
	var ctx := DevActions._context_for(seq, SceneRouter.current_room as Room)
	ctx.first_view = 1
	var res: SequenceResult = await Cinematics.play(seq, ctx)
	CinematicMode.set_mode(was_mode)
	CinematicMode.auto_speed = was_speed
	return res


## INSTANT: each sequence resolves in its own call, in order, no frame
## passing; the previous mode is put back.
static func play_all_instant(ids: PackedStringArray) -> Array[SequenceResult]:
	var was_mode := CinematicMode.current()
	CinematicMode.set_mode(CinematicMode.Mode.INSTANT)
	var out: Array[SequenceResult] = []
	for id in ids:
		var seq := DevActions.sequence(id)
		if seq == null:
			push_warning("StoryTestKit.play_all_instant: no sequence '%s'" % id)
			continue
		out.append(await Cinematics.play(seq, DevActions._context_for(seq, SceneRouter.current_room as Room)))
	CinematicMode.set_mode(was_mode)
	return out


## Skip what is playing (consumed at the player's next unpaused _process).
static func skip_current() -> void:
	Cinematics.request_skip()


## The sequence restore contract after any end path (A1): nothing playing,
## Rook's input and lock handed back, the camera free, no music override,
## the overlay idle, the HUD shown.
static func assert_restored(t: RedlineTestCase) -> void:
	t.check(not Cinematics.is_playing() and Cinematics.current == null, "restored: nothing playing")
	var room := SceneRouter.current_room as Room
	if room and is_instance_valid(room.player):
		t.check(room.player.input_override == null, "restored: input_override cleared")
		t.check(not room.player.cinematic_lock, "restored: cinematic_lock cleared")
	if room and is_instance_valid(room.camera):
		t.check(not room.camera.is_directed(), "restored: camera released")
	t.check(MusicDirector._override == -1, "restored: music override cleared (%d)" % MusicDirector._override)
	t.check(Cinematics.overlay.is_idle(), "restored: overlay idle")
	t.check(not CinematicMode.hud_hidden, "restored: HUD shown")
	t.check(not CinematicMode.bark_line, "restored: bark_line cleared")
