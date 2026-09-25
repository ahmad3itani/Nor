extends RedlineTestCase
## M8 memory scenes (T04): data rules, MemoryLibrary pending/seen rules, the
## vignette player (PLAY/AUTO/INSTANT, tap/hold, pause panel, detail pan),
## the Anchor hook, the pickup signal, the HUD card, music and the journal
## gallery. Every test restores CinematicMode, the settings it touches, the
## pause state and the save dir, and frees its MemoryScenePlayer (so later
## suites' Anchor rests never take the memory path).

const ROOM_A := "res://tests/fixtures/WorldA.tscn"
const SAVE_DIR := "user://test_memory_scenes"
const TEMP_SETTINGS := "user://test_memory_scenes.cfg"
const FIXTURE := "res://tests/fixtures/save_v3_slice.json"

var root: Node2D
var _mp: MemoryScenePlayer
var _extras: Array[Node] = []
var _snap: Dictionary = {}
var _flash: bool = false
## [kind, args...] in arrival order.
var events: Array = []


func before_each() -> void:
	_snap = use_default_m8_settings()
	_flash = Settings.flash_reduction
	# Anything that saves settings (the pause panel's size row) writes here.
	Settings.load_settings(TEMP_SETTINGS)
	SaveManager.save_dir = SAVE_DIR
	get_tree().paused = false
	CinematicMode.teardown()
	Game.new_game()
	events.clear()
	EventBus.memory_playback_requested.connect(_on_requested)
	EventBus.memory_scene_started.connect(_on_started)
	EventBus.memory_scene_finished.connect(_on_finished)
	EventBus.memory_playback_finished.connect(_on_done)
	EventBus.menu_requested.connect(_on_menu)


func after_each() -> void:
	EventBus.memory_playback_requested.disconnect(_on_requested)
	EventBus.memory_scene_started.disconnect(_on_started)
	EventBus.memory_scene_finished.disconnect(_on_finished)
	EventBus.memory_playback_finished.disconnect(_on_done)
	EventBus.menu_requested.disconnect(_on_menu)
	CinematicMode.teardown()
	for n in _extras:
		if is_instance_valid(n):
			n.queue_free()
	_extras.clear()
	if is_instance_valid(_mp):
		_mp.queue_free()
	_mp = null
	await get_tree().process_frame
	get_tree().paused = false
	MusicDirector._memory_active = false
	Settings.load_settings(Settings.SETTINGS_PATH)
	DirAccess.remove_absolute(TEMP_SETTINGS)
	restore_m8_settings(_snap)
	Settings.flash_reduction = _flash
	if DirAccess.dir_exists_absolute(SAVE_DIR):
		for f in DirAccess.get_files_at(SAVE_DIR):
			DirAccess.remove_absolute("%s/%s" % [SAVE_DIR, f])
	SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR
	if root:
		SceneRouter.current_room = null
		SceneRouter.world_root = null
		root.queue_free()
		root = null
	Game.new_game()
	await physics_frames(2)


func _on_requested(ids: PackedStringArray, source: StringName) -> void:
	events.append(["requested", ids, source])


func _on_started(id: String, source: StringName) -> void:
	events.append(["started", id, source])


func _on_finished(id: String, source: StringName, skipped: bool, seconds: float, beats_seen: int, detail_found: bool, first_view: bool) -> void:
	events.append(["finished", id, source, skipped, seconds, beats_seen, detail_found, first_view,
		_mp.beat_index() if is_instance_valid(_mp) else -1])


func _on_done(source: StringName) -> void:
	events.append(["done", source])


func _on_menu(id: StringName) -> void:
	events.append(["menu", id])


func _of(kind: String) -> Array:
	return events.filter(func(e: Array) -> bool: return e[0] == kind)


func _index_of(kind: String) -> int:
	for i in events.size():
		if events[i][0] == kind:
			return i
	return -1


func _player() -> MemoryScenePlayer:
	_mp = MemoryScenePlayer.new()
	add_child(_mp)
	return _mp


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _play(ids: Array, source: StringName) -> void:
	EventBus.memory_playback_requested.emit(PackedStringArray(ids), source)


## Waits (process frames) until the advance cue shows; false on timeout.
func _wait_cue(max_frames: int = 400) -> bool:
	for i in max_frames:
		if _mp.cue_visible():
			return true
		await get_tree().process_frame
	return _mp.cue_visible()


func _wait_beat_phase(max_frames: int = 200) -> void:
	for i in max_frames:
		if _mp.phase() == MemoryScenePlayer.Phase.BEAT:
			return
		await get_tree().process_frame


## A tap: press for 3 frames, then one frame so the release is processed.
func _tap(actions: Array[StringName]) -> void:
	await press_actions(actions, 3)
	await get_tree().process_frame


func _tap_one(action: StringName) -> void:
	var one: Array[StringName] = [action]
	await _tap(one)


## Taps interact through every beat, then waits out the tear.
func _play_through() -> void:
	if not _mp.is_playing():
		check(false, "nothing is playing")
		return
	var beats := MemoryLibrary.scene(_mp.current_id()).beats.size()
	for i in beats:
		if not await _wait_cue():
			check(false, "cue never showed on beat %d" % i)
			return
		await _tap_one(&"interact")
	await _frames(int(MemoryLibrary.config().tear_seconds * 60.0) + 10)


func _enter_room() -> Room:
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	SceneRouter.goto_room(ROOM_A, &"start")
	await physics_frames(3)
	return SceneRouter.current_room as Room


func _scene_with_detail() -> MemorySceneData:
	var s := MemorySceneData.new()
	s.id = "test_mem"
	s.source = MemorySceneData.Source.SURFACED
	s.title = "Test"
	s.tableau_width = 560
	for t in ["One.", "Two.", "Three."]:
		var b := MemoryBeat.new()
		b.text = t
		s.beats.append(b)
	s.detail_x = 350.0
	s.detail_text = "A detail."
	var sh := MemoryShape.new()
	s.shapes.append(sh)
	return s


func _has_error(errors: PackedStringArray, needle: String) -> bool:
	for e in errors:
		if e.contains(needle):
			return true
	return false


# --- Data ---------------------------------------------------------------------------

func test_every_fragment_has_one_scene() -> void:
	var scenes := MemoryLibrary.all_scenes()
	check(scenes.size() == 6, "Act I has 6 memory scenes (5 fragments + mem_first_rest), got %d" % scenes.size())
	for path in DataDir.list("res://data/lore"):
		var frag := load(path) as MemoryFragmentData
		var n := scenes.filter(func(s: MemorySceneData) -> bool:
			return s.source == MemorySceneData.Source.FRAGMENT and s.fragment and s.fragment.id == frag.id).size()
		check(n == 1, "fragment %s has %d scenes (needs exactly one)" % [frag.id, n])
		var s := MemoryLibrary.scene_for_fragment(frag.id)
		check(s != null and s.id == frag.id, "scene_for_fragment(%s)" % frag.id)
	var slots := {}
	for s in scenes:
		var key := "%d:%d" % [s.act, s.timeline_slot]
		check(not slots.has(key), "timeline_slot %s used twice (%s)" % [key, s.id])
		slots[key] = true
	check(MemoryLibrary.scene("mem_first_rest").source == MemorySceneData.Source.SURFACED, "mem_first_rest is surfaced")


func test_scene_validate_rules() -> void:
	var r := MemoryLibrary.config().detail_radius
	var good := _scene_with_detail()
	check(good.validate().is_empty(), "base scene should validate: %s" % [good.validate()])
	var s := _scene_with_detail()
	s.beats[0].text = "x".repeat(111)
	check(_has_error(s.validate(), "111 chars"), "a 111-char beat must fail")
	s = _scene_with_detail()
	s.beats[1].speaker = "Voice"
	check(_has_error(s.validate(), "UPPERCASE"), "a lowercase speaker must fail")
	s = _scene_with_detail()
	s.detail_x = s.max_view_x() + r + 1.0
	check(_has_error(s.validate(), "unreachable"), "a detail beyond W-240+r must fail")
	s = _scene_with_detail()
	s.detail_x = 240.0 - r - 1.0
	check(_has_error(s.validate(), "unreachable"), "a detail before 240-r must fail")
	s = _scene_with_detail()
	s.detail_x = s.start_view_x + r - 1.0
	check(_has_error(s.validate(), "start_view_x"), "a detail within r of start_view_x must fail")
	s = _scene_with_detail()
	s.beats[1].view_x = s.detail_x - r + 5.0
	check(_has_error(s.validate(), "auto-pan"), "a detail within r of a beat view_x must fail")
	s = _scene_with_detail()
	s.beats[2].view_x = s.max_view_x() + 1.0
	check(_has_error(s.validate(), "view_x"), "a beat view_x beyond W-240 must fail")
	s = _scene_with_detail()
	s.shapes[0].from_beat = 2
	s.shapes[0].to_beat = 1
	check(_has_error(s.validate(), "shape beats"), "from_beat > to_beat must fail")
	for sc in MemoryLibrary.all_scenes():
		check(sc.validate().is_empty(), "%s: %s" % [sc.id, sc.validate()])
		var v := ContentValidator.new()
		v.check_resource(sc, sc.resource_path)
		check(v.errors.is_empty(), "%s: validator errors %s" % [sc.id, v.errors])
		check(v.produced.has("mem_seen_" + sc.id), "%s must produce its mem_seen flag" % sc.id)
	check(MemoryLibrary.config().validate().is_empty(), "memory_config: %s" % [MemoryLibrary.config().validate()])
	check(MemoryLibrary.config().max_per_rest == 1, "max_per_rest is 1 (D-112)")


func test_fragment_quotes_are_verbatim() -> void:
	var quote := RegEx.create_from_string("\"([^\"]*)\"")
	var sentence := RegEx.create_from_string("[^.!?]+[.!?]")
	for s in MemoryLibrary.all_scenes():
		if s.source != MemorySceneData.Source.FRAGMENT:
			continue
		var beats := PackedStringArray()
		for b in s.beats:
			beats.append(b.text)
		var all := "\n".join(beats)
		var found := 0
		for m in quote.search_all(s.fragment.text):
			for sm in sentence.search_all(m.get_string(1)):
				var line := sm.get_string().strip_edges()
				found += 1
				check(all.contains(line), "%s: quoted sentence '%s' is not in any beat" % [s.id, line])
		check(found > 0, "%s: its fragment has no quoted speech" % s.id)


# --- MemoryLibrary ------------------------------------------------------------------

func test_pending_order_and_cap() -> void:
	Game.state.memory_fragments.append("mf_undercity_01")
	var ids := MemoryLibrary.pending().map(func(s: MemorySceneData) -> String: return s.id)
	check(ids == ["mem_first_rest", "mf_undercity_01"], "pending order %s" % [ids])
	check(MemoryLibrary.pending_for_rest() == PackedStringArray(["mem_first_rest"]), "one per rest: %s" % [MemoryLibrary.pending_for_rest()])
	MemoryLibrary.mark_seen("mem_first_rest")
	check(MemoryLibrary.pending_for_rest() == PackedStringArray(["mf_undercity_01"]), "next rest: %s" % [MemoryLibrary.pending_for_rest()])
	# Pickup order decides between fragments.
	Game.state.memory_fragments.append("mf_lowlight_02")
	ids = MemoryLibrary.pending().map(func(s: MemorySceneData) -> String: return s.id)
	check(ids == ["mf_undercity_01", "mf_lowlight_02"], "fragments play in pickup order: %s" % [ids])


func test_mark_seen_idempotent_sets_flags() -> void:
	var seen: Array = []
	var probe := func(id: String, _v: Variant) -> void:
		if id == "mem_seen_mf_lowlight_02":
			seen.append(id)
	EventBus.flag_changed.connect(probe)
	MemoryLibrary.mark_seen("mf_lowlight_02")
	MemoryLibrary.mark_seen("mf_lowlight_02")
	EventBus.flag_changed.disconnect(probe)
	check(MemoryLibrary.is_seen("mf_lowlight_02"), "mem_seen flag not set")
	check(MemoryLibrary.remembered_count() == 1, "memories_remembered should be 1, got %d" % MemoryLibrary.remembered_count())
	check(seen.size() == 1, "flag_changed for mem_seen should fire once, got %d" % seen.size())
	MemoryLibrary.mark_detail("mf_lowlight_02")
	check(MemoryLibrary.is_detail_found("mf_lowlight_02"), "mark_detail")
	MemoryLibrary.dev_reset()
	check(not MemoryLibrary.is_seen("mf_lowlight_02") and MemoryLibrary.remembered_count() == 0 and not MemoryLibrary.is_detail_found("mf_lowlight_02"), "dev_reset clears memories")
	MemoryLibrary.dev_grant_all_fragments()
	check(Game.state.memory_fragments.size() == 5 and Game.is_collected("mf_lowlight_04"), "dev_grant_all_fragments")


func test_old_save_fragments_become_pending() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	check(SaveManager.save_profile(1, data) == OK, "fixture save")
	check(Game.load_game(1), "fixture load")
	var ids := MemoryLibrary.pending().map(func(s: MemorySceneData) -> String: return s.id)
	check(ids == ["mem_first_rest"], "an M7 slice save has the surfaced memory pending: %s" % [ids])
	check(not Game.state.flags.keys().any(func(k: String) -> bool: return k.begins_with("mem_seen_")), "no memory seen on an old save")
	var copy := data.duplicate(true)
	copy["memory_fragments"] = ["mf_lowlight_02", "mf_lowlight_04"]
	SaveManager.save_profile(1, copy)
	check(Game.load_game(1), "modified fixture load")
	ids = MemoryLibrary.pending().map(func(s: MemorySceneData) -> String: return s.id)
	check(ids == ["mem_first_rest", "mf_lowlight_02", "mf_lowlight_04"], "recovered fragments become pending: %s" % [ids])
	check(MemoryLibrary.remembered_count() == 0 and not MemoryLibrary.is_seen("mf_lowlight_02"), "nothing is seen after load")


# --- Player ---------------------------------------------------------------------------

func test_instant_mode_never_hangs() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.INSTANT)
	_player()
	_play(["mem_first_rest", "mf_undercity_01"], &"dev")
	check(_of("finished").size() == 2 and _of("done").size() == 1, "INSTANT must finish in the same call: %s" % [events])
	check(not get_tree().paused and not _mp.is_playing() and not CinematicMode.hud_hidden, "INSTANT leaves nothing paused or hidden")
	check(MemoryLibrary.is_seen("mem_first_rest") and MemoryLibrary.is_seen("mf_undercity_01"), "INSTANT remembers every queued scene")
	var f: Array = _of("finished")[0]
	check(f[3] == false and f[7] == true, "INSTANT reports skipped=false, first_view=true")
	_play(["no_such_memory"], &"dev")
	check(_of("done").size() == 2, "an empty request still reports finished")


func test_skip_counts_as_remembered() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.PLAY)
	_player()
	_play(["mem_first_rest"], &"anchor")
	await _frames(20)
	check(get_tree().paused and _mp.is_playing(), "a vignette pauses the world")
	await press_actions([&"jump", &"cinematic_skip"], 51)
	await _frames(2)
	check(MemoryLibrary.is_seen("mem_first_rest"), "a skipped memory is remembered")
	var fin := _of("finished")
	check(fin.size() == 1 and fin[0][3] == true and fin[0][7] == true, "finished(skipped=true, first_view=true): %s" % [fin])
	check(not get_tree().paused and not _mp.is_playing(), "skip ends the vignette")


func test_playthrough_advances_and_unpauses() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.PLAY)
	_player()
	var inside: Array = []
	var probe := func(_s: StringName) -> void:
		inside.append([get_tree().paused, CinematicMode.hud_hidden])
	EventBus.memory_playback_finished.connect(probe)
	_play(["mem_first_rest"], &"anchor")
	await _frames(3)
	check(MusicDirector.state == MusicDirector.State.MEMORY, "music goes to MEMORY")
	check(CinematicMode.hud_hidden, "the HUD hides during a vignette")
	var beats := MemoryLibrary.scene("mem_first_rest").beats.size()
	for i in beats:
		check(await _wait_cue(), "cue on beat %d" % i)
		check(_mp.beat_index() == i, "beat index %d, expected %d" % [_mp.beat_index(), i])
		await _tap_one(&"interact")
	await _frames(50)
	EventBus.memory_playback_finished.disconnect(probe)
	check(not _mp.is_playing() and not get_tree().paused, "played through and unpaused")
	check(inside.size() == 1 and inside[0] == [false, false], "tree unpaused and HUD shown before playback_finished: %s" % [inside])
	var fin := _of("finished")
	check(fin.size() == 1 and fin[0][3] == false and fin[0][5] == beats, "finished unskipped with every beat: %s" % [fin])
	await _frames(2)
	check(MusicDirector.state != MusicDirector.State.MEMORY, "music leaves MEMORY")


func test_hold_skips_without_advancing() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.PLAY)
	_player()
	_play(["mem_first_rest"], &"anchor")
	check(await _wait_cue(), "cue on the first beat")
	var at_press := _mp.beat_index()
	await press_actions([&"jump", &"cinematic_skip"], 60)
	await _frames(2)
	var fin := _of("finished")
	check(fin.size() == 1 and fin[0][3] == true, "a 1 s hold skips: %s" % [fin])
	check(fin.size() == 1 and fin[0][8] == at_press, "the hold never advanced a beat (%d -> %s)" % [at_press, fin])


func test_replay_taps_advance_not_skip() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.PLAY)
	MemoryLibrary.mark_seen("mem_first_rest")
	_player()
	_play(["mem_first_rest"], &"journal")
	check(await _wait_cue(), "cue on the first beat")
	var i0 := _mp.beat_index()
	await _tap([&"jump", &"ui_accept", &"cinematic_skip"])
	check(_mp.is_playing() and _mp.beat_index() == i0 + 1, "a pad-A tap advances one beat on a replay (%d -> %d)" % [i0, _mp.beat_index()])
	check(await _wait_cue(), "cue on the second beat")
	await _tap_one(&"interact")
	check(_mp.is_playing() and _mp.beat_index() == i0 + 2, "an interact tap advances one beat (%d)" % _mp.beat_index())
	check(_of("finished").is_empty(), "a replay is never skipped by taps")
	check(MemoryLibrary.remembered_count() == 1, "a replay does not recount")


func test_detail_dwell() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.PLAY)
	_player()
	for s in MemoryLibrary.all_scenes():
		Game.new_game()
		_play([s.id], &"dev")
		await _wait_beat_phase()
		for i in s.beats.size():
			check(await _wait_cue(), "%s: cue on beat %d" % [s.id, i])
			await _frames(40)
			check(not MemoryLibrary.is_detail_found(s.id), "%s: detail found without panning (beat %d, view %.0f)" % [s.id, i, _mp.view_x()])
			if i < s.beats.size() - 1:
				await _tap_one(&"interact")
		await get_tree().process_frame
		Input.action_press(&"move_right")
		for f in 600:
			if _mp.view_x() >= s.max_view_x() - 0.01:
				break
			await get_tree().process_frame
		check(is_equal_approx(_mp.view_x(), s.max_view_x()), "%s: view reaches its maximum (%.1f)" % [s.id, _mp.view_x()])
		await _frames(int(MemoryLibrary.config().detail_dwell * 60.0) + 6)
		Input.action_release(&"move_right")
		check(MemoryLibrary.is_detail_found(s.id), "%s: panning to the end and waiting finds the detail" % s.id)
		MemoryScenePlayer.abort_active()
		await get_tree().process_frame
		check(not get_tree().paused, "%s: abort unpaused" % s.id)


func test_flash_reduction_disables_shear() -> void:
	_player()
	Settings.flash_reduction = true
	check(not _mp.uses_shear(), "flash reduction replaces the tear shear with a fade")
	var view := MemoryTableauView.new()
	check(not view.uses_shear(), "tableau view agrees")
	view.free()
	Settings.flash_reduction = false
	check(_mp.uses_shear(), "shear is the default tear")


func test_memory_music_state() -> void:
	EventBus.memory_scene_started.emit("mem_first_rest", &"dev")
	await _frames(2)
	check(MusicDirector.state == MusicDirector.State.MEMORY, "memory_scene_started -> MEMORY")
	EventBus.memory_playback_finished.emit(&"dev")
	await _frames(2)
	check(MusicDirector.state != MusicDirector.State.MEMORY, "memory_playback_finished leaves MEMORY")


func test_no_menus_during_vignette() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.PLAY)
	_player()
	_play(["mem_first_rest"], &"anchor")
	await _wait_beat_phase()
	check(get_tree().paused, "the vignette pauses the tree")
	var host: GDScript = load("res://ui/menus/MenuHost.gd")
	if host.get_script_method_list().any(func(m: Dictionary) -> bool: return m["name"] == "can_open"):
		check(not host.call("can_open", &"map", true, false), "map cannot open during a vignette")
		check(not host.call("can_open", &"pause", true, false), "pause menu cannot open during a vignette")
	await press_action(&"pause", 3)
	await get_tree().process_frame
	check(_mp.panel_open(), "pause opens the vignette's own panel")
	await _tap_one(&"ui_cancel")
	check(not _mp.panel_open(), "ui_cancel closes the panel")
	var idx := _mp.beat_index()
	await _frames(600)
	check(_mp.is_playing() and _mp.beat_index() == idx, "beats wait for input (%d -> %d)" % [idx, _mp.beat_index()])
	await press_actions([&"jump", &"cinematic_skip"], 60)
	await _frames(2)
	check(not _mp.is_playing() and _of("finished").size() == 1 and _of("finished")[0][3] == true, "hold-skip still works")


func test_abort_active_restores() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.PLAY)
	_player()
	_play(["mem_first_rest"], &"anchor")
	await _frames(10)
	check(get_tree().paused and CinematicMode.hud_hidden, "playing pauses and hides the HUD")
	CinematicMode.teardown()
	check(not get_tree().paused, "teardown unpauses the tree the player paused")
	check(not CinematicMode.hud_hidden, "teardown shows the HUD")
	check(not _mp.is_playing() and _mp.current_id() == "", "teardown clears the scene")
	check(_of("done").is_empty(), "an abort reports nothing")
	check(not MemoryLibrary.is_seen("mem_first_rest"), "an abort does not remember")


func test_advance_cue_and_skip_prompt() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.PLAY)
	_player()
	_play(["mem_first_rest"], &"anchor")
	await _wait_beat_phase()
	check(not _mp.cue_visible(), "no cue before min_seconds")
	check(not _mp.skip_prompt_visible(), "a first view starts without a skip prompt")
	check(await _wait_cue(), "cue after min_seconds with the line shown")
	check(_mp.beat_time() >= MemoryLibrary.scene("mem_first_rest").beats[0].min_seconds, "cue waited for min_seconds")
	await _tap_one(&"jump")
	check(_mp.skip_prompt_visible(), "a press shows the skip prompt")
	await get_tree().process_frame
	Input.action_press(&"jump")
	Input.action_press(&"cinematic_skip")
	await _frames(30)
	check(_mp.skip_gate().progress_ratio() > 0.0, "a 0.5 s hold fills the bar")
	Input.action_release(&"jump")
	Input.action_release(&"cinematic_skip")
	await _frames(2)
	check(_mp.is_playing(), "a 0.5 s hold does not skip a first view")


func test_vignette_pause_panel() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.PLAY)
	_player()
	_play(["mem_first_rest"], &"anchor")
	await _wait_beat_phase()
	await _frames(5)
	await press_actions([&"pause", &"ui_cancel"], 3)
	await get_tree().process_frame
	check(_mp.panel_open(), "Esc opens the panel and its ui_cancel does not close it")
	var idx := _mp.beat_index()
	var bt := _mp.beat_time()
	await _frames(120)
	check(_mp.beat_index() == idx and is_equal_approx(_mp.beat_time(), bt), "the beat clock is frozen behind the panel")
	await _tap_one(&"ui_down")
	await _tap_one(&"ui_accept")
	check(MemoryLibrary.is_seen("mem_first_rest"), "Skip memory remembers")
	var fin := _of("finished")
	check(fin.size() == 1 and fin[0][3] == true, "Skip memory reports skipped: %s" % [fin])
	check(not _mp.is_playing() and not get_tree().paused, "Skip memory ends the vignette")
	# Second run: subtitle size, then Resume with a carried pad-A press.
	Game.new_game()
	_play(["mem_first_rest"], &"anchor")
	check(await _wait_cue(), "cue on the first beat")
	await _tap_one(&"pause")
	check(_mp.panel_open(), "panel open again")
	await _tap_one(&"ui_down")
	await _tap_one(&"ui_down")
	await _tap_one(&"ui_accept")
	check(Settings.subtitle_size == 1, "Subtitle size cycles 0 -> 1 (got %d)" % Settings.subtitle_size)
	await _tap_one(&"ui_up")
	await _tap_one(&"ui_up")
	idx = _mp.beat_index()
	await _tap([&"jump", &"ui_accept", &"cinematic_skip"])
	await _frames(3)
	check(not _mp.panel_open(), "Resume closes the panel")
	check(_mp.is_playing() and _mp.beat_index() == idx, "the carried press neither advances nor skips (%d -> %d)" % [idx, _mp.beat_index()])


# --- Anchor, pickup, HUD --------------------------------------------------------------------

func test_anchor_plays_then_opens_loadout() -> void:
	var room := await _enter_room()
	_player()
	var loadout: MenuScreen = load("res://ui/menus/LoadoutMenu.gd").new()
	add_child(loadout)
	_extras.append(loadout)
	var opener := func(id: StringName) -> void:
		if id == &"loadout":
			loadout.open_menu()
	EventBus.menu_requested.connect(opener)
	CinematicMode.set_mode(CinematicMode.Mode.PLAY)
	var anchor := room.find_child("Anchor", true, false) as Anchor
	anchor.interact(room.player)
	check(_index_of("requested") >= 0, "the rest requested a memory")
	check(_index_of("menu") == -1, "no loadout while the memory plays")
	check(_mp.is_playing(), "the pending memory plays")
	await _play_through()
	EventBus.menu_requested.disconnect(opener)
	var done := _index_of("done")
	var menu := _index_of("menu")
	check(done >= 0 and menu > done, "loadout requested only after playback finished: %s" % [events])
	check(get_tree().paused and loadout.is_open(), "the loadout is open over a paused world")
	check(MemoryLibrary.is_seen("mem_first_rest"), "the rest remembered the memory")
	loadout.close_menu()


func test_anchor_without_pending_or_setting_off() -> void:
	var room := await _enter_room()
	_player()
	CinematicMode.set_mode(CinematicMode.Mode.PLAY)
	var anchor := room.find_child("Anchor", true, false) as Anchor
	MemoryLibrary.mark_seen("mem_first_rest")
	anchor.interact(room.player)
	check(_index_of("requested") == -1 and _of("menu").size() == 1, "no pending memory -> loadout at once: %s" % [events])
	events.clear()
	Game.new_game()
	Settings.memories_at_anchors = false
	anchor.interact(room.player)
	check(_index_of("requested") == -1 and _of("menu").size() == 1, "memories_at_anchors off -> loadout at once: %s" % [events])
	check(not _mp.is_playing() and not get_tree().paused, "nothing plays")
	events.clear()
	Settings.memories_at_anchors = true
	_mp.queue_free()
	await get_tree().process_frame
	anchor.interact(room.player)
	check(_index_of("requested") == -1 and _of("menu").size() == 1, "no memory player -> loadout at once: %s" % [events])


func test_pickup_never_pauses() -> void:
	var room := await _enter_room()
	_player()
	CinematicMode.set_mode(CinematicMode.Mode.PLAY)
	var c := Collectible.new()
	c.persist_id = "mf_lowlight_02"
	c.kind = Collectible.Kind.MEMORY_FRAGMENT
	c.fragment = load("res://data/lore/mf_lowlight_02.tres")
	c.position = Vector2(80, 0)
	room.add_child(c)
	room.player.teleport(Vector2(80, -2))
	await physics_frames(3)
	check(Game.state.memory_fragments.has("mf_lowlight_02"), "fragment picked up")
	check(not get_tree().paused and not _mp.is_playing(), "a pickup never pauses or plays a memory")
	check(_index_of("requested") == -1, "a pickup requests no playback")


func test_collectible_taken_emitted() -> void:
	var room := await _enter_room()
	var seen: Array = []
	var probe := func(id: String, kind: int) -> void:
		seen.append([id, kind, Game.state.core_shards, Game.is_collected(id), Game.state.memory_fragments.has(id)])
	EventBus.collectible_taken.connect(probe)
	var shard := Collectible.new()
	shard.persist_id = "test_mem_shard"
	shard.kind = Collectible.Kind.CORE_SHARD
	shard.position = Vector2(80, 0)
	room.add_child(shard)
	room.player.teleport(Vector2(80, -2))
	await physics_frames(3)
	check(seen.size() == 1, "one collectible_taken per pickup, got %d" % seen.size())
	if seen.size() == 1:
		check(seen[0][0] == "test_mem_shard" and seen[0][1] == Collectible.Kind.CORE_SHARD, "id and kind: %s" % [seen[0]])
		check(seen[0][2] == 1 and seen[0][3], "listener sees the shard counted and collected: %s" % [seen[0]])
	var frag := Collectible.new()
	frag.persist_id = "mf_lowlight_03"
	frag.kind = Collectible.Kind.MEMORY_FRAGMENT
	frag.fragment = load("res://data/lore/mf_lowlight_03.tres")
	frag.position = Vector2(120, 0)
	room.add_child(frag)
	room.player.teleport(Vector2(120, -2))
	await physics_frames(3)
	EventBus.collectible_taken.disconnect(probe)
	check(seen.size() == 2 and seen[1][4], "the fragment listener sees the id already recovered: %s" % [seen])


func test_fragment_card_short_text() -> void:
	var hud = load("res://ui/hud/CombatHud.gd").new()
	add_child(hud)
	_extras.append(hud)
	var cfg := MemoryLibrary.config()
	EventBus.memory_fragment_found.emit(load("res://data/lore/mf_lowlight_02.tres"))
	check(hud._lore_title == "MEMORY FRAGMENT  —  Rain Clinic", "card title: %s" % hud._lore_title)
	check(hud._lore_text == cfg.card_body_anchor, "card body at Anchors: %s" % hud._lore_text)
	Settings.memories_at_anchors = false
	EventBus.memory_fragment_found.emit(load("res://data/lore/mf_lowlight_02.tres"))
	check(hud._lore_text == cfg.card_body_journal, "card body without Anchor playback: %s" % hud._lore_text)


# --- Journal --------------------------------------------------------------------------------

func _journal() -> MenuScreen:
	var j: MenuScreen = load("res://ui/menus/JournalMenu.gd").new()
	add_child(j)
	_extras.append(j)
	return j


func _labels(menu: MenuScreen) -> PackedStringArray:
	var out := PackedStringArray()
	for n in menu._body.get_children():
		if n is Label:
			out.append((n as Label).text)
	return out


func _button(menu: MenuScreen, prefix: String) -> Button:
	for n in menu._body.get_children():
		if n is Button and (n as Button).text.begins_with(prefix):
			return n
	return null


func test_journal_replay_and_remember_now() -> void:
	var cfg := MemoryLibrary.config()
	_player()
	var j := _journal()
	MemoryLibrary.mark_seen("mem_first_rest")
	j.open_menu()
	check(not Array(_labels(j)).any(func(t: String) -> bool: return t.begins_with("Fragments remembered")), "no fragment line before any fragment: %s" % [_labels(j)])
	check(_button(j, cfg.gallery_button) != null, "Memories… button once a memory is seen")
	Game.state.memory_fragments.append("mf_lowlight_02")
	j.rebuild()
	check(_labels(j).has(cfg.remembered_line % [0, 1]), "line reads 0 / 1: %s" % [_labels(j)])
	_button(j, cfg.gallery_button).pressed.emit()
	var replay := _button(j, "%s %s" % [cfg.glyph_seen, "Count the Last One"])
	check(replay != null, "the seen memory is a replay row")
	if replay:
		replay.pressed.emit()
	check(MemoryLibrary.remembered_count() == 1, "a replay does not change memories_remembered")
	check(_of("requested").size() == 1 and _of("requested")[0][2] == &"journal", "replay source is journal")
	var now := _button(j, "%s %s" % [cfg.glyph_pending, "Rain Clinic"])
	check(now != null, "the recovered memory is a Remember now row")
	if now:
		now.pressed.emit()
	check(MemoryLibrary.remembered_count() == 2 and MemoryLibrary.is_seen("mf_lowlight_02"), "Remember now counts")
	check(_of("requested").size() == 2 and _of("requested")[1][2] == &"journal_first", "Remember now source is journal_first")
	check(j.visible, "the journal is back after playback")
	_button(j, cfg.back_label).pressed.emit()
	check(_labels(j).has(cfg.remembered_line % [1, 1]), "line reads 1 / 1: %s" % [_labels(j)])
	j.close_menu()


func test_journal_fits_viewport() -> void:
	var cfg := MemoryLibrary.config()
	for q in Game.quests.quests:
		if q.start_flag != "":
			Game.state.flags[q.start_flag] = true
		Game.state.flags[q.complete_flag] = true
	MemoryLibrary.dev_grant_all_fragments()
	for id in ["mem_first_rest", "mf_lowlight_02", "mf_lowlight_01", "mf_undercity_01"]:
		MemoryLibrary.mark_seen(id)
	MemoryLibrary.mark_detail("mf_undercity_01")
	check(MemoryLibrary.pending().size() == 2, "two memories pending")
	var j := _journal()
	j.open_menu()
	var h: float = await menu_height(j)
	check(h <= 270.0, "journal main page is %.0f px tall (max 270)" % h)
	_button(j, cfg.gallery_button).pressed.emit()
	var longest := _button(j, "%s %s" % [cfg.glyph_seen, "It Won't Come Out"])
	check(longest != null, "the Undercity memory is listed")
	if longest:
		longest.grab_focus()
	check(Array(_labels(j)).any(func(t: String) -> bool: return t == cfg.detail_line % MemoryLibrary.scene("mf_undercity_01").detail_text), "the focused card shows its found detail: %s" % [_labels(j)])
	check(_button(j, cfg.glyph_pending) != null and _button(j, cfg.glyph_pending).text.contains(cfg.pending_hint), "pending rows carry the hint")
	h = await menu_height(j)
	check(h <= 270.0, "journal gallery is %.0f px tall (max 270)" % h)
	j.close_menu()
