extends RedlineTestCase
## M8 Act I sequences in the world (T07): SequenceTrigger, the BossArena
## intro paths, the Act I close in SliceEndTrigger, the five sequences in
## their real rooms, and CaptureTour's session defaults.
## Fixture: tests/fixtures/scaffold_m8_sequence.tscn (tools/roomgen/
## fixtures_scaffold.py) with data/sequences/test_scaffold_trigger.tres.

const WAKE := "res://world/rooms/undercity/Wake.tscn"
const BAY := "res://world/rooms/undercity/CollectorBay.tscn"
const LIFT := "res://world/rooms/undercity/BrokenLift.tscn"
const TOWER := "res://world/rooms/lowlight/WardenTower.tscn"
const RELAY := "res://world/rooms/lowlight/Relay.tscn"
const TITLE := "res://world/rooms/TitleBackdrop.tscn"
const FIXTURE := "res://tests/fixtures/scaffold_m8_sequence.tscn"
const FIXTURE_SEQ := "res://data/sequences/test_scaffold_trigger.tres"
const PARITY := "res://data/sequences/test_seq_parity.tres"
const NEEDLE := "res://enemies/variants/Needle.tscn"
const SEQ_DIR := "res://data/sequences"
const SAVE_DIR := "user://test_act1_sequences"
const CLAMP_HINT := "Breakers live. Drop the clamp on him."
const FRAME := 1.0 / 60.0

## Each Act I sequence in its real room. Entries avoid the autoplay spawns
## (Wake "start", Relay "from_undercity") so the test starts every play.
const CASES := [
	{"seq": "uc_opening", "room": WAKE, "entry": &"from_medical", "flags": [], "arena": false},
	{"seq": "uc_collector_intro", "room": BAY, "entry": &"from_lift", "flags": [], "arena": true},
	{"seq": "ll_krail_intro", "room": TOWER, "entry": &"from_bell", "flags": [], "arena": true},
	{"seq": "relay_arrival", "room": RELAY, "entry": &"start", "flags": ["collector_drone_defeated"], "arena": false},
	{"seq": "act1_close", "room": RELAY, "entry": &"start", "flags": ["warden_krail_defeated", "met_iko"], "arena": false},
]

var root: Node2D
var room: Room
var hud: CanvasLayer
var _mp: MemoryScenePlayer
var _extras: Array[Node] = []
var _snap: Dictionary
## [id, first_view, frame]
var started: Array = []
## [id, skipped, seconds, step_index, step_count, nominal, frame]
var finished: Array = []
## [index, label, frame, sequence id]
var steps_seen: Array = []
## [text, frame]
var hints: Array = []
var slices: Array = []
var boss_starts: Array = []
var memory_done: Array = []


func before_each() -> void:
	_snap = use_default_m8_settings()
	SaveManager.save_dir = SAVE_DIR
	get_tree().paused = false
	CinematicMode.teardown()
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	Game.new_game()
	for a: Array in [started, finished, steps_seen, hints, slices, boss_starts, memory_done]:
		a.clear()
	EventBus.sequence_started.connect(_on_started)
	EventBus.sequence_finished.connect(_on_finished)
	EventBus.hint_requested.connect(_on_hint)
	EventBus.slice_completed.connect(_on_slice)
	EventBus.boss_started.connect(_on_boss_started)
	EventBus.memory_playback_finished.connect(_on_memory_done)
	Cinematics.step_started.connect(_on_step)
	Cinematics.overlay.clear_all()


func after_each() -> void:
	EventBus.sequence_started.disconnect(_on_started)
	EventBus.sequence_finished.disconnect(_on_finished)
	EventBus.hint_requested.disconnect(_on_hint)
	EventBus.slice_completed.disconnect(_on_slice)
	EventBus.boss_started.disconnect(_on_boss_started)
	EventBus.memory_playback_finished.disconnect(_on_memory_done)
	Cinematics.step_started.disconnect(_on_step)
	CinematicMode.teardown()
	if is_instance_valid(_mp):
		_mp.queue_free()
	_mp = null
	if is_instance_valid(hud):
		hud.queue_free()
	hud = null
	for n in _extras:
		if is_instance_valid(n):
			n.queue_free()
	_extras.clear()
	get_tree().paused = false
	Game.onboarding = Game.ONBOARDING
	restore_m8_settings(_snap)
	if DirAccess.dir_exists_absolute(SAVE_DIR):
		for f in DirAccess.get_files_at(SAVE_DIR):
			DirAccess.remove_absolute("%s/%s" % [SAVE_DIR, f])
	SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR
	SceneRouter.current_room = null
	SceneRouter.world_root = null
	root.queue_free()
	Game.new_game()
	await physics_frames(2)


func _on_started(id: String, first_view: bool) -> void:
	started.append([id, first_view, Engine.get_process_frames()])


func _on_finished(id: String, skipped: bool, seconds: float, step_index: int, step_count: int, nominal: float) -> void:
	finished.append([id, skipped, seconds, step_index, step_count, nominal, Engine.get_process_frames()])


func _on_step(index: int, label: String) -> void:
	var id: String = Cinematics.current.seq.id if Cinematics.is_playing() else ""
	steps_seen.append([index, label, Engine.get_process_frames(), id])


func _on_hint(text: String, _seconds: float) -> void:
	hints.append([text, Engine.get_process_frames()])


func _on_slice() -> void:
	slices.append(Engine.get_process_frames())


func _on_boss_started(_boss: Node2D, _title: String) -> void:
	boss_starts.append(1)


func _on_memory_done(source: StringName) -> void:
	memory_done.append(source)


# --- Helpers ------------------------------------------------------------------------

func _enter(path: String, entry: StringName) -> Room:
	SceneRouter.goto_room(path, entry)
	await physics_frames(3)
	return SceneRouter.current_room as Room


func _seq(id: String) -> SequenceData:
	return load("%s/%s.tres" % [SEQ_DIR, id]) as SequenceData


func _auto(speed: float = 4.0) -> void:
	CinematicMode.set_mode(CinematicMode.Mode.AUTO)
	CinematicMode.auto_speed = speed


func _instant() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.INSTANT)


func _start(seq: SequenceData, ctx: SequenceContext, into: Array = []) -> void:
	into.append(await Cinematics.play(seq, ctx))


func _finished_count(id: String) -> int:
	return finished.filter(func(f: Array) -> bool: return f[0] == id).size()


func _started_ids() -> Array:
	return started.map(func(s: Array) -> String: return s[0])


func _until_finished(id: String, max_frames: int = 2400) -> bool:
	var n := _finished_count(id)
	for i in max_frames:
		if _finished_count(id) > n:
			return true
		await get_tree().process_frame
	return false


## True once `id` has finished `n` times in this test.
func _until_count(id: String, n: int, max_frames: int = 600) -> bool:
	for i in max_frames:
		if _finished_count(id) >= n:
			return true
		await get_tree().process_frame
	return false


func _arena() -> BossArena:
	var a := room.find_children("*", "BossArena", true, false)
	return a[0] as BossArena if not a.is_empty() else null


func _ctx(c: Dictionary) -> SequenceContext:
	return SequenceContext.for_arena(_arena(), true) if c["arena"] else SequenceContext.for_room(room)


## Walks Rook right until the arena starts; returns the frame count or -1.
## keep_walking leaves move_x at 1 afterwards (repeat intros never lock).
func _walk_into_arena(arena: BossArena, keep_walking: bool = false) -> ScriptedInputSource:
	var p := room.player
	var walk := ScriptedInputSource.new()
	p.input_source = walk
	walk.move_x = 1
	for i in 240:
		await physics_frames(1)
		p.invulnerable = true
		if arena.started:
			break
	if not keep_walking:
		walk.move_x = 0
	return walk


## Physics frames from arena start to the boss's AI (the M7 measure in
## test_boss_collector._walk_in).
func _intro_frames(arena: BossArena) -> int:
	var p := room.player
	var walk := ScriptedInputSource.new()
	p.input_source = walk
	walk.move_x = 1
	var start := -1
	for i in 60 * 6:
		await physics_frames(1)
		p.invulnerable = true
		if p.global_position.x >= 90.0:
			walk.move_x = 0
		if arena.started and start < 0:
			start = i
		if start >= 0 and is_instance_valid(arena.boss) and arena.boss.ai_enabled:
			return i - start
	return -1


func _hud() -> CanvasLayer:
	hud = load("res://ui/hud/CombatHud.gd").new()
	add_child(hud)
	return hud


func _pause_menu() -> MenuScreen:
	var pm: MenuScreen = load("res://ui/menus/PauseMenu.gd").new()
	add_child(pm)
	_extras.append(pm)
	return pm


func _button(menu: MenuScreen, text: String) -> Button:
	for c in menu._body.get_children():
		if c is Button and (c as Button).text == text:
			return c as Button
	return null


func _slice_end() -> SliceEndTrigger:
	return room.find_child("SliceEnd", true, false) as SliceEndTrigger


# --- Data -----------------------------------------------------------------------------

func test_act1_sequence_data_validates() -> void:
	var nominal := {"uc_opening": [17.0, 18.0], "uc_collector_intro": [8.2, 10.0], "ll_krail_intro": [12.6, 14.0],
		"relay_arrival": [11.7, 13.0], "act1_close": [23.2, 26.0]}
	for c: Dictionary in CASES:
		var id: String = c["seq"]
		var seq := _seq(id)
		check(seq != null and seq.id == id, "%s loads" % id)
		if seq == null:
			continue
		check(seq.content_check().is_empty(), "%s content_check: %s" % [id, seq.content_check()])
		var v := ContentValidator.new()
		v.check_resource(seq, "%s/%s.tres" % [SEQ_DIR, id])
		check(v.errors.is_empty(), "%s validator errors: %s" % [id, v.errors])
		check(seq.room == c["room"] and not seq.theatre_only, "%s is bound to %s" % [id, c["room"]])
		check_near(seq.nominal_seconds(true), nominal[id][0], 0.1, "%s nominal first view" % id)
		check(is_equal_approx(seq.budget_seconds, nominal[id][1]), "%s budget %.1f" % [id, seq.budget_seconds])
		for s in seq.steps:
			if s is SeqLine:
				check(not (s as SeqLine).text.contains("Rook"), "%s: no line names Rook (D-109)" % id)
			check(not (s is SeqActorMove and (s as SeqActorMove).actor == "@rook"), "%s: never moves Rook (R1)" % id)
	for id in ["uc_collector_intro", "ll_krail_intro"]:
		var seq := _seq(id)
		check(not seq.repeat_locks_input and not seq.locks_for(false) and seq.locks_for(true), "%s: repeats never lock" % id)
		check(is_equal_approx(seq.repeat_budget_seconds, 1.0) and is_equal_approx(seq.nominal_seconds(false), 0.8), "%s repeat 0.8 s of 1.0" % id)
	check(_seq("uc_collector_intro").effective_seen_flag() == "collector_drone_intro_seen", "collector intro seen flag")
	check(_seq("ll_krail_intro").effective_seen_flag() == "warden_krail_intro_seen", "krail intro seen flag")
	check(_seq("uc_opening").effective_seen_flag() == "seen_seq_uc_opening", "opening seen flag default")
	var marks := []
	for c: Dictionary in CASES:
		for s in _seq(c["seq"]).steps:
			if s is SeqMark:
				marks.append((s as SeqMark).mark)
	for m in ["opening_eye", "collector_title", "krail_title", "relay_pan", "act1_trophy", "act1_card"]:
		check(marks.has(m), "SeqMark %s authored" % m)
	# The rooms that place them validate (triggers, arenas, the SliceEnd).
	for path in [WAKE, BAY, TOWER, RELAY]:
		# One room alone cannot see the other rooms' producers: flag
		# bookkeeping is ValidateContent's (the gate), not this test's.
		var room_errs := Array(ContentValidator.new().check_room(path).errors).filter(func(e: String) -> bool:
			return not e.begins_with("flag '"))
		check(room_errs.is_empty(), "%s validates: %s" % [path.get_file(), room_errs])
	var fixture := ContentValidator.new().check_room(FIXTURE, false)
	check(fixture.errors.is_empty(), "sequence fixture validates: %s" % [fixture.errors])
	# A trigger whose sequence belongs to another room, or a missing spawn.
	var wrong := SequenceTrigger.new()
	wrong.sequence = _seq("uc_opening")
	wrong.require_spawn = &"nowhere"
	var relay := (load(RELAY) as PackedScene).instantiate()
	var errs := wrong.content_errors(relay)
	check(errs.size() == 2 and errs[0].contains("authored for") and errs[1].contains("nowhere"), "trigger lint: %s" % [errs])
	relay.free()
	wrong.free()


func test_act1_close_band_line() -> void:
	var band := ""
	for s in _seq("act1_close").steps:
		if s is SeqLine and (s as SeqLine).speaker_id == "band":
			band = (s as SeqLine).text
	check(band == "...all Recovery units. Priority unchanged. Signature still active.", "band line: '%s'" % band)
	var frag := load("res://data/lore/mf_lowlight_01.tres") as MemoryFragmentData
	var text := frag.text.replace("\"", "")
	var re := RegEx.new()
	re.compile("[^.!?]+[.!?]")
	var sentences: Array[String] = []
	for m in re.search_all(text):
		var s := m.get_string().strip_edges().to_lower()
		if s.length() > 3:
			sentences.append(s)
	check(sentences.has("recover the core.") and sentences.has("discard the rest."), "fragment sentences parsed: %s" % [sentences])
	for f in DirAccess.get_files_at(SEQ_DIR):
		if not f.ends_with(".tres"):
			continue
		var seq := load("%s/%s" % [SEQ_DIR, f]) as SequenceData
		if seq == null or seq.theatre_only:
			continue
		for s in seq.steps:
			if not s is SeqLine:
				continue
			var line := (s as SeqLine).text.to_lower()
			for sentence in sentences:
				check(not line.contains(sentence), "%s quotes Execution Order 7-R: '%s'" % [f, sentence])


# --- Parity -------------------------------------------------------------------------

func _prepare(c: Dictionary) -> void:
	Game.new_game()
	for f: String in c["flags"]:
		Game.set_flag(f)
	room = await _enter(c["room"], c["entry"])
	await physics_frames(10)


func _parity_state() -> Dictionary:
	var npcs := {}
	for n in room.find_children("NPC_*", "", true, false):
		npcs[String(n.name)] = n.get("facing")
	var visual := Vector2.INF
	var arena := _arena()
	if arena and is_instance_valid(arena.boss):
		visual = (arena.boss.get_node("Visual") as Node2D).position
	return {"flags": Game.state.flags.duplicate(true), "npcs": npcs, "visual": visual,
		"facing": arena.boss.facing if arena and is_instance_valid(arena.boss) else 0, "rook": room.player.global_position}


func _same(a: Dictionary, b: Dictionary, what: String) -> void:
	check(a["flags"] == b["flags"], "%s flags: %s / %s" % [what, a["flags"], b["flags"]])
	check(a["npcs"] == b["npcs"], "%s NPC facing: %s / %s" % [what, a["npcs"], b["npcs"]])
	check(a["visual"] == b["visual"] and a["facing"] == b["facing"], "%s boss visual: %s / %s" % [what, a["visual"], b["visual"]])
	check((a["rook"] as Vector2).distance_to(b["rook"]) <= 0.5, "%s Rook position: %s / %s" % [what, a["rook"], b["rook"]])


func test_skip_parity_all_act1() -> void:
	var directed_at_fade: Array = []
	for c: Dictionary in CASES:
		var id: String = c["seq"]
		var seq := _seq(id)
		# Watched to the end (AUTO x4).
		await _prepare(c)
		_auto(4.0)
		var last := seq.steps.size() - 1
		var probe := func(index: int, _label: String) -> void:
			if id == "act1_close" and index == last and Cinematics.is_playing() and Cinematics.current.seq.id == id:
				directed_at_fade.append(room.camera.is_directed())
		Cinematics.step_started.connect(probe)
		_start(seq, _ctx(c))
		check(await _until_finished(id), "%s: watched run ends" % id)
		Cinematics.step_started.disconnect(probe)
		await physics_frames(2)
		var watched := _parity_state()
		check(not finished[-1][1], "%s: watched run not skipped" % id)
		# INSTANT.
		await _prepare(c)
		_instant()
		await Cinematics.play(seq, _ctx(c))
		var instant := _parity_state()
		# Skipped midway (AUTO).
		await _prepare(c)
		_auto(4.0)
		_start(seq, _ctx(c))
		var half := seq.steps.size() / 2
		for i in 1200:
			if Cinematics.is_playing() and Cinematics.current.index >= half:
				break
			await get_tree().process_frame
		check(Cinematics.is_playing() and Cinematics.current.index >= half, "%s: skip lands midway" % id)
		Cinematics.request_skip()
		check(await _until_finished(id, 10), "%s: skip resolves" % id)
		check(finished[-1][1], "%s: skipped" % id)
		await physics_frames(2)
		var skipped := _parity_state()
		_same(watched, instant, "%s watched/INSTANT" % id)
		_same(watched, skipped, "%s watched/skipped" % id)
		check(Game.has_flag(seq.effective_seen_flag()), "%s: seen flag set" % id)
		if c["arena"]:
			check(watched["visual"] == Vector2.ZERO, "%s: the boss visual ends at rest" % id)
	check(directed_at_fade == [false], "act1_close: the camera is released before the final fade in: %s" % [directed_at_fade])
	check(Game.has_flag("act1_complete"), "act1_close sets act1_complete")


func test_act1_sequences_never_move_rook() -> void:
	for c: Dictionary in CASES:
		await _prepare(c)
		_auto(8.0)
		var before := room.player.global_position
		_start(_seq(c["seq"]), _ctx(c))
		check(await _until_finished(c["seq"]), "%s ends" % c["seq"])
		await physics_frames(3)
		check(room.player.global_position.distance_to(before) <= 0.5,
			"%s moved Rook: %s -> %s" % [c["seq"], before, room.player.global_position])


# --- The opening ----------------------------------------------------------------------

func test_hints_and_banner_wait_for_opening() -> void:
	_hud()
	_auto(4.0)
	SceneRouter.goto_room(WAKE, &"start")
	room = SceneRouter.current_room as Room
	var leaks: Array = []
	for i in 1200:
		await get_tree().process_frame
		if _finished_count("uc_opening") > 0:
			break
		if hud.current_hint() != "":
			leaks.append("hint '%s' at frame %d" % [hud.current_hint(), i])
		if hud._banner_time > 0.0 and not CinematicMode.hud_hidden:
			leaks.append("banner drawn at frame %d" % i)
	check(_started_ids() == ["uc_opening"], "the opening played: %s" % [_started_ids()])
	check(_finished_count("uc_opening") == 1, "the opening ended")
	check(leaks.is_empty(), "nothing showed under the opening: %s" % [leaks])
	var fired := hints.filter(func(h: Array) -> bool: return (h[0] as String).begins_with("Alive."))
	check(fired.size() == 1 and fired[0][1] < finished[0][6], "the uc_wake hint fired during the opening: %s" % [hints])
	var shown_at := -1
	for i in 3:
		if hud.current_hint().begins_with("Alive."):
			shown_at = i
			break
		await get_tree().process_frame
	check(shown_at >= 0 and shown_at <= 2, "uc_wake shows within 2 frames of the end (%d)" % shown_at)
	var frames := 0
	for i in 400:
		if not hud.current_hint().begins_with("Alive."):
			break
		frames += 1
		await get_tree().process_frame
	check(frames >= int(3.5 * 60.0) - 3, "uc_wake lasts its full 3.5 s (%d frames)" % frames)


func test_opening_only_from_start_spawn() -> void:
	_auto(4.0)
	room = await _enter(WAKE, &"from_medical")
	await physics_frames(60)
	check(started.is_empty(), "a walk-in from MedicalRuin never plays the opening: %s" % [_started_ids()])
	check(not Game.has_flag("seen_seq_uc_opening"), "seen flag unset")
	var trigger := room.find_child("SeqOpening", true, false) as SequenceTrigger
	check(trigger != null and not trigger.eligible(), "the trigger is not eligible from from_medical")


func test_relay_start_plays_no_sequence() -> void:
	var off := (Game.ONBOARDING as OnboardingConfig).duplicate() as OnboardingConfig
	off.enforce = false
	Game.onboarding = off
	Game.start_campaign()
	_auto(4.0)
	room = await _enter(Game.campaign_start_room(), Game.campaign_start_entry())
	check(room.scene_file_path == RELAY and room.active_spawn().spawn_id == &"start", "the Relay-start path")
	await physics_frames(60)
	check(started.is_empty(), "no sequence on a Relay start: %s" % [_started_ids()])
	check(not Game.has_flag("seen_seq_relay_arrival"), "arrival not marked")
	room = await _enter(WAKE, &"start")
	check(_started_ids() == ["uc_opening"], "the same profile gets the opening in Wake: %s" % [_started_ids()])


func test_journal_replay_mid_sequence_keeps_hud_hidden() -> void:
	_hud()
	_auto(4.0)
	SceneRouter.goto_room(WAKE, &"start")
	room = SceneRouter.current_room as Room
	await physics_frames(60)
	check(Cinematics.is_playing() and CinematicMode.hud_hidden, "the opening plays")
	check(Game.has_flag("hint_uc_wake") and hud.current_hint() == "", "uc_wake queued under the opening")
	# The PauseMenu pauses; the journal replays a memory over it.
	get_tree().paused = true
	_mp = MemoryScenePlayer.new()
	add_child(_mp)
	MemoryLibrary.mark_seen("mem_first_rest")
	EventBus.memory_playback_requested.emit(PackedStringArray(["mem_first_rest"]), &"journal")
	for i in 3600:
		if not memory_done.is_empty():
			break
		await get_tree().process_frame
	check(memory_done == [&"journal"], "the replay ended: %s" % [memory_done])
	check(get_tree().paused, "the replay leaves the tree paused (it did not pause it)")
	get_tree().paused = false
	await get_tree().process_frame
	check(Cinematics.is_playing(), "the opening is still playing")
	check(CinematicMode.hud_hidden, "the HUD stays hidden under the resumed opening")
	check(hud.current_hint() == "", "uc_wake still queued")
	check(await _until_finished("uc_opening"), "the opening ends")
	var shown := false
	for i in 3:
		if hud.current_hint().begins_with("Alive."):
			shown = true
			break
		await get_tree().process_frame
	check(shown, "uc_wake shows within 2 frames of the end")


# --- Boss intros --------------------------------------------------------------------

func test_boss_intro_instant_keeps_legacy_timing() -> void:
	_instant()
	room = await _enter(BAY, &"from_lift")
	var frames := await _intro_frames(_arena())
	check(absi(frames - 156) <= 1, "unseen: AI after 2.6 s (%d frames)" % frames)
	check(Game.has_flag("collector_drone_intro_seen"), "intro seen")
	room = await _enter(BAY, &"from_lift")
	frames = await _intro_frames(_arena())
	check(absi(frames - 36) <= 1, "seen: AI after 0.6 s (%d frames)" % frames)


func test_collector_intro_holds_boss() -> void:
	_auto(4.0)
	room = await _enter(BAY, &"from_lift")
	var arena := _arena()
	var boss := arena.boss
	await _walk_into_arena(arena)
	check(arena.started and Cinematics.locks_input(), "the first-view intro locks")
	var gate := room.find_child("ArenaGateLeft", true, false) as Gate
	check(gate.closed, "gates close on entry")
	var early: Array = []
	for i in 1200:
		if _finished_count("uc_collector_intro") > 0:
			break
		if boss.ai_enabled:
			early.append(i)
		await physics_frames(1)
	check(_finished_count("uc_collector_intro") == 1, "the intro ended")
	check(early.is_empty(), "the boss slept through the intro")
	var woke := -1
	for i in 90:
		if boss.ai_enabled:
			woke = i
			break
		await physics_frames(1)
	check(woke >= 59 and woke <= 63, "the boss acts post_intro_delay 1.0 s after the intro (%d frames)" % woke)
	check(gate.closed, "gates still closed")
	check(boss_starts.size() == 1, "boss_started once (%d)" % boss_starts.size())
	check(arena.released, "released")


func test_collector_first_attempt_is_first_view() -> void:
	_auto(1.0)
	room = await _enter(BAY, &"from_lift")
	var arena := _arena()
	await _walk_into_arena(arena)
	check(started.size() == 1 and started[0][0] == "uc_collector_intro" and started[0][1], "sequence_started first_view: %s" % [started])
	for i in 400:
		if Cinematics.is_playing() and Cinematics.current.index >= 5:
			break
		await get_tree().process_frame
	var seen := steps_seen.map(func(s: Array) -> int: return s[0])
	check(seen.has(1) and seen.has(5), "the First-view camera (1) and the c00 line (5) played: %s" % [seen])
	var skip_press: Array[StringName] = [&"jump", &"cinematic_skip"]
	await press_actions(skip_press, 30)
	await physics_frames(3)
	check(Cinematics.is_playing() and _finished_count("uc_collector_intro") == 0, "a 0.5 s hold does not skip a first view")
	await press_actions(skip_press, 51)
	await physics_frames(3)
	check(_finished_count("uc_collector_intro") == 1 and finished[-1][1], "a 0.85 s hold skips it")


func test_repeat_intro_never_locks() -> void:
	for pair in [[BAY, &"from_lift", "collector_drone_intro_seen", "uc_collector_intro"],
			[TOWER, &"from_bell", "warden_krail_intro_seen", "ll_krail_intro"]]:
		Game.new_game()
		Game.set_flag(pair[2])
		_auto(4.0)
		room = await _enter(pair[0], pair[1])
		var arena := _arena()
		var boss := arena.boss
		var p := room.player
		var walk := ScriptedInputSource.new()
		p.input_source = walk
		walk.move_x = 1
		var start := -1
		for i in 240:
			await physics_frames(1)
			p.invulnerable = true
			if arena.started:
				start = i
				break
		check(start >= 0, "%s: arena entered" % pair[3])
		var x0 := p.global_position.x
		await physics_frames(2)
		check(p.global_position.x > x0, "%s: Rook keeps moving on a retry (%.1f -> %.1f)" % [pair[3], x0, p.global_position.x])
		check(not Cinematics.locks_input() and not p.cinematic_lock, "%s: no lock" % pair[3])
		check(_started_ids().has(pair[3]) and not started[-1][1], "%s: the repeat overlay plays" % pair[3])
		walk.move_x = 0
		# Two frames already passed since the start frame.
		var woke := -1
		for i in 60:
			if boss.ai_enabled:
				woke = i + 2
				break
			await physics_frames(1)
		check(absi(woke - 36) <= 1, "%s: AI at retry_intro_time 0.6 s +- 1 frame (%d frames)" % [pair[3], woke])
		started.clear()


func test_krail_clamp_hint_not_under_intro() -> void:
	_auto(2.0)
	room = await _enter(TOWER, &"from_bell")
	var arena := _arena()
	await _walk_into_arena(arena)
	check(Cinematics.locks_input(), "the Krail intro locks")
	# Stand under the clamp while the intro plays.
	room.player.global_position = Vector2(208, -2)
	check(await _until_finished("ll_krail_intro"), "the intro ended")
	var end_frame: int = finished[-1][6]
	var clamp := hints.filter(func(h: Array) -> bool: return h[0] == CLAMP_HINT)
	check(clamp.all(func(h: Array) -> bool: return h[1] > end_frame), "no clamp hint before the intro ended: %s (end %d)" % [clamp, end_frame])


func test_arena_refused_still_releases() -> void:
	_auto(1.0)
	room = await _enter(BAY, &"from_lift")
	var arena := _arena()
	var gate := room.find_child("ArenaGateLeft", true, false) as Gate
	# A locking fixture play owns Cinematics (a dev preview stands in here).
	var other: Array = []
	_start(load(PARITY) as SequenceData, SequenceContext.for_overlay(null), other)
	check(Cinematics.locks_input(), "another locking play is running")
	var frames := await _intro_frames(arena)
	check(absi(frames - 156) <= 1, "refused: the legacy 2.6 s intro releases the boss (%d frames)" % frames)
	check(gate.closed and arena.released, "gates closed, boss released: no softlock")
	check(not _started_ids().has("uc_collector_intro"), "the intro was refused")


func test_arena_abort_does_not_release() -> void:
	_auto(1.0)
	room = await _enter(BAY, &"from_lift")
	var arena := _arena()
	await _walk_into_arena(arena)
	await physics_frames(20)
	check(Cinematics.locks_input(), "intro playing")
	EventBus.room_leaving.emit(room)
	await physics_frames(1)
	check(finished.size() == 1 and finished[0][3] == -1, "aborted")
	await physics_frames(200)
	check(not arena.released and not arena.boss.ai_enabled, "an aborted intro never releases the boss")
	# A real room change mid-intro: the arena and the boss are freed.
	room = await _enter(BAY, &"from_lift")
	arena = _arena()
	await _walk_into_arena(arena)
	await physics_frames(20)
	check(Cinematics.locks_input(), "second intro playing")
	room = await _enter(LIFT, &"from_bay")
	await physics_frames(200)
	check(not is_instance_valid(arena), "the old arena is gone")
	check(not Cinematics.is_playing(), "nothing playing")


func test_aborted_first_intro_replays() -> void:
	_auto(1.0)
	room = await _enter(BAY, &"from_lift")
	await _walk_into_arena(_arena())
	await physics_frames(20)
	EventBus.room_leaving.emit(room)
	await physics_frames(1)
	check(not Game.has_flag("collector_drone_intro_seen"), "an aborted first view is not seen")
	started.clear()
	room = await _enter(BAY, &"from_lift")
	await _walk_into_arena(_arena())
	check(started.size() == 1 and started[0][1], "the first view plays again: %s" % [started])
	await physics_frames(20)
	Cinematics.request_skip()
	check(await _until_finished("uc_collector_intro", 10), "skipped")
	check(Game.has_flag("collector_drone_intro_seen"), "a skipped intro is seen")
	started.clear()
	room = await _enter(BAY, &"from_lift")
	await _walk_into_arena(_arena())
	check(started.size() == 1 and not started[0][1], "then a repeat: %s" % [started])


# --- The Relay ------------------------------------------------------------------------

func test_relay_arrival_guards() -> void:
	_auto(4.0)
	Game.set_flag("collector_drone_defeated")
	room = await _enter(RELAY, &"from_undercity")
	check(_started_ids() == ["relay_arrival"], "plays on the campaign arrival: %s" % [_started_ids()])
	check(await _until_finished("relay_arrival"), "arrival ends")
	check(Game.has_flag("seen_seq_relay_arrival"), "arrival seen")
	started.clear()
	Game.new_game()
	Game.set_flag("collector_drone_defeated")
	Game.set_flag("met_orr")
	room = await _enter(RELAY, &"from_undercity")
	await physics_frames(60)
	check(started.is_empty(), "not once Orr was met: %s" % [_started_ids()])
	Game.new_game()
	Game.set_flag("collector_drone_defeated")
	room = await _enter(RELAY, &"start")
	await physics_frames(60)
	check(started.is_empty(), "not from the start spawn: %s" % [_started_ids()])


func test_slice_end_plays_close_then_card() -> void:
	check(not _seq("act1_close").steps.any(func(s: SequenceStep) -> bool: return s is SeqTitleCard), "act1_close has no title card")
	Game.set_flag("warden_krail_defeated")
	_auto(4.0)
	room = await _enter(RELAY, &"start")
	var slice := _slice_end()
	check(slice != null and slice.sequence == _seq("act1_close"), "SliceEnd carries act1_close")
	slice._on_body_entered(room.player)
	await physics_frames(2)
	check(Cinematics.is_playing() and slices.is_empty(), "the close plays before the card")
	check(not Game.has_flag("slice_end_seen"), "not marked while it plays")
	check(await _until_finished("act1_close"), "the close ends")
	await physics_frames(2)
	check(slices.size() == 1 and slices[0] >= finished[-1][6], "slice_completed once, after the close: %s" % [slices])
	check(Game.has_flag("slice_end_seen") and Game.has_flag("act1_complete"), "slice_end_seen and act1_complete")
	slice._on_body_entered(room.player)
	await physics_frames(5)
	check(slices.size() == 1, "never twice")


func test_quit_mid_close_replays() -> void:
	Game.set_flag("warden_krail_defeated")
	_auto(1.0)
	room = await _enter(RELAY, &"start")
	var slice := _slice_end()
	slice._on_body_entered(room.player)
	await physics_frames(30)
	check(Cinematics.is_playing() and Cinematics.current.seq.id == "act1_close", "the close plays")
	var pm := _pause_menu()
	pm.open_menu()
	var quits: Array = []
	pm.quit_to_title.connect(func() -> void:
		quits.append(Cinematics.is_playing())
		SceneRouter.transition_to(TITLE))
	pm._quit()
	check(not Cinematics.is_playing(), "aborted in the same frame")
	check(quits == [false], "aborted before quit_to_title: %s" % [quits])
	check(is_instance_valid(slice) and not slice._busy, "_busy cleared")
	await physics_frames(30)
	check(slices.is_empty(), "slice_completed never emitted")
	check(not Game.has_flag("slice_end_seen") and not Game.has_flag("act1_complete"), "nothing marked: the close replays")
	check(not Game.has_flag("seen_seq_act1_close"), "close not seen")
	check(not SceneRouter.transitioning and not get_tree().paused, "the title transition finished unpaused")
	check(FileAccess.file_exists("%s/profile_1.json" % SAVE_DIR) or not DirAccess.get_files_at(SAVE_DIR).is_empty(), "the quit saved into the test dir")


## Quit after the close's SeqFlag step (act1_complete under the fade) but
## before its end: the abort puts the flags back, including what the flag's
## listeners entered (Orr's on-air arc stage), so the close replays.
func test_quit_late_in_close_reverts_flags() -> void:
	Game.set_flag("warden_krail_defeated")
	Game.set_flag("met_orr")
	_auto(4.0)
	room = await _enter(RELAY, &"start")
	var slice := _slice_end()
	slice._on_body_entered(room.player)
	var seq: SequenceData = Cinematics.current.seq if Cinematics.is_playing() else null
	check(seq != null and seq.id == "act1_close", "the close plays")
	var flag_step := -1
	for i in seq.steps.size():
		if seq.steps[i] is SeqFlag and Array((seq.steps[i] as SeqFlag).flags).has("act1_complete"):
			flag_step = i
	check(flag_step >= 0 and flag_step < seq.steps.size() - 1, "act1_complete is set before the close's last step")
	for i in 3000:
		if not Cinematics.is_playing() or Cinematics.current.index > flag_step:
			break
		await get_tree().process_frame
	check(Cinematics.is_playing() and Cinematics.current.index > flag_step, "reached a step after the flag")
	check(Game.has_flag("act1_complete"), "act1_complete set under the fade")
	check(Game.has_flag("arc_orr_on_air"), "its listener entered Orr's on-air stage")
	var pm := _pause_menu()
	pm.open_menu()
	pm.quit_to_title.connect(func() -> void: SceneRouter.transition_to(TITLE))
	pm._quit()
	check(not Cinematics.is_playing(), "aborted")
	check(not Game.has_flag("act1_complete"), "act1_complete put back")
	check(not Game.has_flag("arc_orr_on_air"), "the flag's arc stage put back")
	check(not Game.has_flag("slice_end_seen") and not Game.has_flag("seen_seq_act1_close"), "nothing marked: the close replays")
	var saved: Dictionary = SaveManager.load_profile(Game.profile_id).get("flags", {})
	check(not saved.has("act1_complete") or not bool(saved["act1_complete"]), "the quit saved the reverted flags")
	await physics_frames(30)
	check(slices.is_empty(), "slice_completed never emitted")


## A close refused because another locking play owns Cinematics plays once
## that play ends, while Rook still stands in the area.
func test_refused_close_retries() -> void:
	Game.set_flag("warden_krail_defeated")
	_auto(4.0)
	room = await _enter(RELAY, &"start")
	var slice := _slice_end()
	room.player.teleport(slice.global_position + slice.size * 0.5)
	var blocker := load(PARITY) as SequenceData
	Cinematics.play(blocker, SequenceContext.for_room(room))
	await physics_frames(3)
	check(Cinematics.is_playing() and Cinematics.current.seq.id == "test_seq_parity", "another locking play runs")
	slice._on_body_entered(room.player)
	await physics_frames(2)
	check(Cinematics.current.seq.id == "test_seq_parity" and not slice._busy, "the close was refused")
	var played := false
	for i in 3000:
		if Cinematics.is_playing() and Cinematics.current.seq.id == "act1_close":
			played = true
			break
		await get_tree().process_frame
	check(played, "the close plays once the other play ends")
	Cinematics.request_skip()
	for i in 600:
		if not slices.is_empty():
			break
		await get_tree().process_frame
	check(slices.size() == 1 and Game.has_flag("slice_end_seen"), "the card follows")


func test_pause_skip_close_opens_card() -> void:
	Game.set_flag("warden_krail_defeated")
	_auto(1.0)
	room = await _enter(RELAY, &"start")
	var pause := _pause_menu()
	var card: MenuScreen = load("res://ui/menus/SliceEndMenu.gd").new()
	add_child(card)
	_extras.append(card)
	var open_card := func() -> void:
		if not pause.is_open():
			card.open_menu()
	EventBus.slice_completed.connect(open_card)
	_slice_end()._on_body_entered(room.player)
	await physics_frames(20)
	pause.open_menu()
	var skip := _button(pause, "Skip scene")
	check(skip != null, "PauseMenu offers Skip scene")
	if skip:
		skip.pressed.emit()
	for i in 10:
		await get_tree().process_frame
	EventBus.slice_completed.disconnect(open_card)
	check(slices.size() == 1, "slice_completed once (%d)" % slices.size())
	check(card.is_open(), "the card opened")
	check(Game.has_flag("slice_end_seen") and Game.has_flag("act1_complete"), "flags set by the skip")
	card.close_menu()


# --- SequenceTrigger ------------------------------------------------------------------

func _code_trigger(seq: SequenceData) -> SequenceTrigger:
	var t := SequenceTrigger.new()
	t.sequence = seq
	t.autoplay = true
	room.get_node("Triggers").add_child(t)
	return t


func _enemy(at: Vector2) -> Enemy:
	var e := (load(NEEDLE) as PackedScene).instantiate() as Enemy
	e.position = at
	room.get_node("Enemies").add_child(e)
	# Frozen in a busy state: only the trigger reads it.
	e.process_mode = Node.PROCESS_MODE_DISABLED
	e.ai_enabled = true
	e.ai = Enemy.AI.ENGAGE
	return e


func test_locking_trigger_waits_for_enemies() -> void:
	_auto(4.0)
	room = await _enter(FIXTURE, &"start")
	check(_started_ids() == ["test_scaffold_trigger"], "the fixture trigger autoplays from 'start': %s" % [_started_ids()])
	check(await _until_finished("test_scaffold_trigger"), "fixture play ends")
	Game.new_game()
	started.clear()
	room = await _enter(FIXTURE, &"side")
	await physics_frames(10)
	check(started.is_empty(), "require_spawn: nothing from 'side'")
	var e := _enemy(Vector2(500, 0))
	var t := _code_trigger(load(FIXTURE_SEQ) as SequenceData)
	await physics_frames(60)
	check(started.is_empty() and t._pending, "a locking play waits while an enemy is active")
	e.ai = Enemy.AI.IDLE
	await physics_frames(33)
	check(_started_ids() == ["test_scaffold_trigger"], "plays within 0.5 s once the enemy idles: %s" % [_started_ids()])
	check(await _until_count("test_scaffold_trigger", 2), "ends")
	# Dead counts as safe too.
	Game.new_game()
	started.clear()
	e.ai = Enemy.AI.ENGAGE
	var t2 := _code_trigger(load(FIXTURE_SEQ) as SequenceData)
	await physics_frames(40)
	check(started.is_empty() and t2._pending, "waits again")
	e.ai = Enemy.AI.DEAD
	await physics_frames(33)
	check(_started_ids() == ["test_scaffold_trigger"], "plays once the enemy is dead")
	check(await _until_count("test_scaffold_trigger", 3), "ends")
	# A bark (non-locking) is not blocked.
	e.ai = Enemy.AI.ENGAGE
	var wait := SeqWait.new()
	wait.seconds = 0.5
	var bark := SequenceData.new()
	bark.id = "test_code_bark_trigger"
	bark.lock_input = false
	bark.letterbox = false
	bark.hide_hud = false
	bark.theatre_only = true
	bark.steps = [wait]
	started.clear()
	_code_trigger(bark)
	await physics_frames(2)
	check(_started_ids() == ["test_code_bark_trigger"], "a bark plays beside an active enemy: %s" % [_started_ids()])
	check(not Cinematics.locks_input(), "and takes no control")


func test_trigger_skips_while_theatre_or_playing() -> void:
	_auto(4.0)
	CinematicMode.theatre = true
	room = await _enter(FIXTURE, &"start")
	await physics_frames(30)
	check(started.is_empty(), "theatre: no autoplay")
	check(not Game.has_flag("seen_seq_test_scaffold_trigger"), "theatre: seen flag unset")
	CinematicMode.theatre = false
	var t := room.find_child("SeqTest", true, false) as SequenceTrigger
	_start(load(PARITY) as SequenceData, SequenceContext.for_overlay(null))
	check(Cinematics.is_playing(), "another play runs")
	t._try_play()
	await physics_frames(2)
	check(not _started_ids().has("test_scaffold_trigger"), "nothing while another play runs")
	Cinematics.abort()
	# An aborted play re-arms the trigger.
	t._try_play()
	await physics_frames(5)
	check(_started_ids().count("test_scaffold_trigger") == 1, "plays once free")
	EventBus.room_leaving.emit(room)
	await physics_frames(1)
	check(not Game.has_flag("seen_seq_test_scaffold_trigger") and not t._done, "an aborted play leaves it armed")
	t._try_play()
	check(await _until_finished("test_scaffold_trigger"), "replays and ends")
	check(Game.has_flag("seen_seq_test_scaffold_trigger") and t._done, "done once watched")
	t._try_play()
	await physics_frames(3)
	check(_started_ids().count("test_scaffold_trigger") == 2, "once: never again")


# --- CaptureTour ----------------------------------------------------------------------

func test_capture_tour_defaults_instant() -> void:
	var tour: GDScript = load("res://devtools/CaptureTour.gd")
	var none := PackedStringArray()
	for name in ["slice", "undercity", "ui", "movement", "combat"]:
		check(tour.tour_cinematic_mode(name, none) == CinematicMode.Mode.INSTANT, "%s tours are INSTANT" % name)
	check(tour.tour_cinematic_mode("story", none) == -1, "story keeps the default")
	check(tour.tour_cinematic_mode("slice", PackedStringArray(["--cinematics=auto"])) == CinematicMode.Mode.AUTO, "--cinematics= wins")
	check(tour.tour_cinematic_mode("story", PackedStringArray(["--cinematics=play"])) == CinematicMode.Mode.PLAY, "--cinematics= wins for story")
	const CFG := "user://settings.cfg"
	var existed := FileAccess.file_exists(CFG)
	var mtime := FileAccess.get_modified_time(CFG) if existed else 0
	var tour_cfg_existed := FileAccess.file_exists(tour.TOUR_SETTINGS_PATH)
	var old_path := Settings._path
	Settings.subtitle_size = 2
	Settings.speaker_labels = false
	CinematicMode.set_mode(CinematicMode.Mode.PLAY)
	var snap: Dictionary = tour.prepare_session("slice", none)
	check(CinematicMode.current() == CinematicMode.Mode.INSTANT, "slice session is INSTANT")
	check(Settings._path == tour.TOUR_SETTINGS_PATH, "settings save to the tour file")
	check(Settings.subtitle_size == 0 and Settings.speaker_labels and Settings.subtitle_background == 1, "M8 settings at defaults")
	var menu: MenuScreen = load("res://ui/menus/SettingsMenu.gd").new()
	add_child(menu)
	menu.open_menu()
	await get_tree().process_frame
	menu.close_menu()
	menu.queue_free()
	check(FileAccess.file_exists(tour.TOUR_SETTINGS_PATH), "the SettingsMenu saved to the tour file")
	check(FileAccess.file_exists(CFG) == existed and (not existed or FileAccess.get_modified_time(CFG) == mtime),
		"user://settings.cfg untouched")
	tour.restore_session(snap)
	check(Settings._path == old_path and Settings.subtitle_size == 2 and not Settings.speaker_labels, "the snapshot comes back")
	if not tour_cfg_existed:
		DirAccess.remove_absolute(tour.TOUR_SETTINGS_PATH)
	CinematicMode.set_mode(CinematicMode.Mode.PLAY)
	tour.prepare_session("story", none)
	check(CinematicMode.current() == CinematicMode.Mode.PLAY, "story leaves the mode alone")
	tour.restore_session(snap)
	if not tour_cfg_existed and FileAccess.file_exists(tour.TOUR_SETTINGS_PATH):
		DirAccess.remove_absolute(tour.TOUR_SETTINGS_PATH)
