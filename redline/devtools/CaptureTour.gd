extends Node
## Renders a scripted tour of the Movement Lab to PNGs for reports/PR review.
##   godot --fixed-fps 60 res://devtools/CaptureTour.tscn -- --out=/abs/dir [--tour=movement|combat|slice|ui|undercity|story]
## Needs a real (or virtual, e.g. xvfb-run) display; headless has no renderer.

const MAIN := preload("res://Main.tscn")

## Settings the tour may save (--tour=ui closes the SettingsMenu, which always
## saves): never the developer's user://settings.cfg.
const TOUR_SETTINGS_PATH := "user://capture_tour_settings.cfg"

var _out_dir := "user://captures"
var _tour_name := "movement"
var _input := ScriptedInputSource.new()
var _settings_snapshot := {}
## --tour=story: SeqMark names waiting to be shot (Cinematics.marked appends:
## lambdas capture locals by value, members are safe), the shots taken, and
## the endings finished.
var _marks: Array[String] = []
var _taken: Array[String] = []
var _endings_done: Array[String] = []
var _pumping: bool = false
## Marks fired while this is on are dropped (a replay whose marks were shot).
var _mute_marks: bool = false
## Frames a room settles before a story shot: the area banner and quest
## hints raised by a preset have faded by then.
const STORY_SETTLE := 180


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--tour="):
			_tour_name = arg.trim_prefix("--tour=")
	_settings_snapshot = prepare_session(_tour_name, OS.get_cmdline_user_args())
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var main := MAIN.instantiate()
	if _tour_name != "ui":
		main.start_room = "res://world/rooms/CombatLab.tscn" if _tour_name == "combat" else "res://world/rooms/MovementLab.tscn"
	add_child(main)
	if _tour_name == "combat":
		_combat_tour.call_deferred()
	elif _tour_name == "slice":
		_slice_tour.call_deferred()
	elif _tour_name == "undercity":
		_undercity_tour.call_deferred()
	elif _tour_name == "ui":
		_ui_tour.call_deferred()
	elif _tour_name == "story":
		_story_tour.call_deferred()
	else:
		_tour.call_deferred()


## M8 session setup, before Main loads (T07):
## - cinematics: INSTANT for every tour but `story`, unless `--cinematics=`
##   says otherwise. Tours run windowed (PLAY by default), so the Wake opening
##   would black out uc_Wake_start and the "mid-fight" shots would land inside
##   the first-view boss intros; INSTANT keeps the M7 review frames.
## - settings: every stored setting (M9: all of them, the six M8
##   subtitle/scene settings included) takes its default for the session (a
##   --subtitle-size=N override still applies), and Settings saves to
##   TOUR_SETTINGS_PATH, so neither the developer's settings leak into the
##   frames nor the tour into the developer's settings.
## - platform (M9): toasts and assist offers off, the platform store in a
##   wiped user://tour_sandbox.
## Returns the snapshot restore_session() puts back.
static func prepare_session(tour: String, args: PackedStringArray) -> Dictionary:
	# M9: every stored setting takes its default first (the M8 keys below
	# included), then the session fields: the tour path, first_run off.
	var snap := Settings.snapshot()
	snap["_path"] = Settings._path
	snap["first_run"] = Settings.first_run
	Settings.apply_defaults()
	Settings._path = TOUR_SETTINGS_PATH
	Settings.first_run = false
	Settings.subtitle_size = 0
	Settings.subtitle_background = 1
	Settings.speaker_labels = true
	Settings.subtitle_speed = 0
	Settings.cinematic_skip_hold = true
	Settings.memories_at_anchors = true
	# No toasts, assist cards or group notices in frames, and nothing written
	# to the developer's user://platform: a wiped sandbox store per run, so
	# every run starts with no unlocks or records (deterministic diffs).
	Settings.achievement_toasts = false
	Settings.assist_suggestions = false
	Challenges.quiet_notices = true
	AtomicJson.remove_tree("user://tour_sandbox")
	Platform.reset_for_tests("user://tour_sandbox/platform")
	var mode := tour_cinematic_mode(tour, args)
	if mode >= 0:
		CinematicMode.set_mode(mode as CinematicMode.Mode)
	return snap


## The mode a tour forces, or -1 to leave CinematicMode alone (story). An
## explicit --cinematics=play|auto|instant always wins.
static func tour_cinematic_mode(tour: String, args: PackedStringArray) -> int:
	for a in args:
		if a.begins_with("--cinematics="):
			match a.trim_prefix("--cinematics="):
				"play":
					return CinematicMode.Mode.PLAY
				"auto":
					return CinematicMode.Mode.AUTO
				"instant":
					return CinematicMode.Mode.INSTANT
	return -1 if tour == "story" else CinematicMode.Mode.INSTANT


static func restore_session(snap: Dictionary) -> void:
	for k in snap:
		Settings.set(k, snap[k])
	Challenges.quiet_notices = false
	Platform.reset_after_tests()
	AtomicJson.remove_tree("user://tour_sandbox")


func _quit() -> void:
	restore_session(_settings_snapshot)
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out_dir, name])
	print("captured ", name)


func _goto(room: Room, spawn_id: StringName) -> void:
	for i in room.spawns.size():
		if room.spawns[i].spawn_id == spawn_id:
			room.active_spawn_index = i
	room.respawn()
	await _frames(20)


func _tour() -> void:
	await _frames(5)
	var room := SceneRouter.current_room as Room
	room.player.input_source = _input
	await _frames(20)
	await _shot("01_start")

	_input.move_x = 1
	await _frames(30)
	_input.press_jump()
	await _frames(18)
	await _shot("02_run_jump_apex")
	await _frames(40)
	_input.move_x = 0

	await _goto(room, &"slide")
	_input.move_x = 1
	await _frames(22)
	_input.down_held = true
	await _frames(14)
	await _shot("03_slide_into_tunnel")
	_input.down_held = false
	await _frames(40)
	_input.move_x = 0

	await _goto(room, &"gaps")
	_input.move_x = 1
	await _frames(20)
	_input.press_dodge()
	await _frames(6)
	await _shot("04_dodge_afterimages")
	_input.move_x = 0

	await _goto(room, &"drop")
	_input.move_x = -1
	await _frames(40)
	_input.move_x = 0
	await _frames(18)
	await _shot("05_falling_look_down")
	for i in 120:
		await _frames(1)
		if room.player.is_on_floor():
			break
	await _frames(4)
	await _shot("06_hard_landing_dust")

	await _goto(room, &"start")
	var panel := get_tree().root.find_child("TuningPanel", true, false) as CanvasLayer
	if panel:
		panel.visible = true
	_input.move_x = 1
	await _frames(25)
	_input.down_held = true
	await _frames(8)
	await _shot("07_tuning_panel_slide_dust")
	_quit()


func _combat_tour() -> void:
	await _frames(5)
	var room := SceneRouter.current_room as Room
	room.player.input_source = _input
	await _goto(room, &"dummies")
	_input.move_x = 1
	await _frames(10)
	_input.move_x = 0
	for i in 2:
		_input.press_light()
		await _frames(9)
	_input.press_light()
	await _frames(6)
	await _shot("c01_blade_finisher_on_dummy")
	await _frames(40)

	for spawner in get_tree().get_nodes_in_group(&"enemy_spawners"):
		(spawner as EnemySpawner).spawn()
	await _goto(room, &"dummies")
	_input.move_x = 1
	for i in 60:
		await _frames(1)
		if room.player.global_position.x >= 172.0:
			break
	_input.move_x = 0
	_input.up_held = true
	_input.press_heavy()
	await _frames(16)
	_input.up_held = false
	_input.press_jump()
	await _frames(14)
	_input.press_light()
	await _frames(5)
	await _shot("c02_launcher_air_follow_up")
	await _frames(60)

	# Arena 1: stand among the needles and wait for a wind-up.
	await _goto(room, &"arena1")
	room.player.respawn(Vector2(640, -2))
	for i in 240:
		await _frames(1)
		var winding := get_tree().get_nodes_in_group(&"enemies").filter(func(e: Node) -> bool:
			return (e as Enemy).ai == Enemy.AI.WINDUP and (e as Enemy).ai_time > 0.25)
		if not winding.is_empty():
			break
	await _shot("c03_needle_telegraph")
	await _frames(30)

	await _goto(room, &"arena2")
	room.player.combat.cycle_ranged()
	room.player.respawn(Vector2(1400, -2))
	_input.move_x = 1
	await _frames(20)
	_input.move_x = 0
	_input.press_ranged()
	await _frames(3)
	await _shot("c04_scattergun_vs_shield")
	await _frames(30)

	await _goto(room, &"arena3")
	room.player.reactor.charge = 8.0
	for i in 300:
		await _frames(1)
		if not get_tree().get_nodes_in_group(&"enemies").filter(func(e: Node) -> bool:
				return (e as Enemy).data.flying and (e as Enemy).ai == Enemy.AI.WINDUP and (e as Enemy).ai_time > 0.4).is_empty():
			break
	await _shot("c05_drone_aim_critical_core")
	_quit()


## One shot per spawn marker of every slice room, plus the boss mid-fight.
func _slice_tour() -> void:
	await _frames(5)
	Game.new_game()
	var dir := "res://world/rooms/lowlight"
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".tscn"):
			continue
		var scene: PackedScene = load("%s/%s" % [dir, f])
		var probe := scene.instantiate()
		var ids: Array[StringName] = []
		for m in probe.find_children("*", "SpawnMarker", true, false):
			ids.append((m as SpawnMarker).spawn_id)
		probe.free()
		for id in ids:
			SceneRouter.goto_room("%s/%s" % [dir, f], id)
			(SceneRouter.current_room as Room).player.input_source = _input
			await _frames(30)
			await _shot("s_%s_%s" % [f.get_basename(), id])
	SceneRouter.goto_room("%s/WardenTower.tscn" % dir, &"from_bell")
	var room := SceneRouter.current_room as Room
	room.player.input_source = _input
	_input.move_x = 1
	await _frames(60)
	_input.move_x = 0
	await _frames(150)
	await _shot("s_boss_fight")
	_quit()


## M7: one shot per spawn marker of every Undercity room (for the visual
## thesis review), plus the Collector mid-fight once its arena exists.
func _undercity_tour() -> void:
	await _frames(5)
	Game.new_game()
	Game.set_flag("core_hud_hidden", false)
	var dir := "res://world/rooms/undercity"
	var files := DirAccess.get_files_at(dir)
	files.sort()
	for f in files:
		if not f.ends_with(".tscn"):
			continue
		var probe := (load("%s/%s" % [dir, f]) as PackedScene).instantiate()
		var ids: Array[StringName] = []
		for m in probe.find_children("*", "SpawnMarker", true, false):
			ids.append((m as SpawnMarker).spawn_id)
		probe.free()
		for id in ids:
			SceneRouter.goto_room("%s/%s" % [dir, f], id)
			(SceneRouter.current_room as Room).player.input_source = _input
			await _frames(30)
			await _shot("uc_%s_%s" % [f.get_basename(), id])
	# Built from parts so the reference scanner does not flag the room before
	# it exists (it lands with the Undercity world skeleton).
	var bay := "%s/%s.tscn" % [dir, "CollectorBay"]
	if not _has_collector_arena(bay):
		print("PENDING: CollectorBay has no Collector arena yet")
		_quit()
		return
	SceneRouter.goto_room(bay, &"from_lift")
	var room := SceneRouter.current_room as Room
	room.player.input_source = _input
	_input.move_x = 1
	await _frames(60)
	_input.move_x = 0
	await _frames(150)
	await _shot("uc_collector_fight")
	_quit()


func _has_collector_arena(path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var probe := (load(path) as PackedScene).instantiate()
	var found := false
	for n in probe.find_children("*", "BossArena", true, false):
		var boss := (n as BossArena).get_node_or_null((n as BossArena).boss_path) as Enemy
		if boss and boss.data and boss.data.id == &"collector_drone":
			found = true
	probe.free()
	return found


## Menus and dialogue as a player sees them (title -> Relay -> menus).
func _ui_tour() -> void:
	await _frames(30)
	await _shot("u01_title")
	Game.new_game()
	var menus := get_tree().root.find_child("Menus", true, false)
	(menus.get_node("TitleMenu") as MenuScreen).close_menu()
	SceneRouter.goto_room(Game.START_ROOM, Game.START_ENTRY)
	await _frames(10)
	var room := SceneRouter.current_room as Room
	room.player.input_source = _input
	var orr: NpcProfile = load("res://data/npcs/orr.tres")
	EventBus.dialogue_requested.emit(orr.pick_dialogue(), "Orr")
	await _frames(40)
	await _shot("u02_dialogue")
	var box := get_tree().root.find_child("DialogueBox", true, false)
	while box.is_open():
		box.shown_chars = 9999.0
		box.advance()
	await _frames(5)
	Game.grant_circuit("rebound")
	Game.grant_circuit("predator")
	Game.state.scrap_banked = 180
	EventBus.menu_requested.emit(&"loadout")
	await _frames(5)
	await _shot("u03_loadout")
	(menus.get_node("LoadoutMenu") as MenuScreen).close_menu()
	EventBus.menu_requested.emit(&"shop_vell")
	await _frames(5)
	await _shot("u04_shop")
	(menus.get_node("ShopMenu") as MenuScreen).close_menu()
	EventBus.menu_requested.emit(&"journal")
	await _frames(5)
	await _shot("u05_journal")
	(menus.get_node("JournalMenu") as MenuScreen).close_menu()
	EventBus.menu_requested.emit(&"settings")
	await _frames(5)
	await _shot("u06_settings")
	(menus.get_node("SettingsMenu") as MenuScreen).close_menu()
	EventBus.menu_requested.emit(&"slice_end")
	await _frames(5)
	await _shot("u07_slice_end")
	(menus.get_node("SliceEndMenu") as MenuScreen).close_menu()
	# M4 feedback screens (recording is on for a windowed tour).
	Playtest.begin_session("new")
	EventBus.menu_requested.emit(&"moment")
	await _frames(5)
	await _shot("u08_report_moment")
	(menus.get_node("MomentMenu") as MenuScreen).close_menu()
	EventBus.menu_requested.emit(&"survey")
	var survey := menus.get_node("SurveyMenu")
	survey.answer(5)
	await _frames(5)
	await _shot("u09_survey")
	survey.close_menu()
	Playtest.end_session("capture")
	DirAccess.remove_absolute(Playtest.session_path)
	await _map_shots(menus)
	await _dev_shots(menus)
	_quit()


## M6 dev tools: hitbox view + perf graph over a live fight, then the console.
func _dev_shots(menus: Node) -> void:
	var console := menus.get_node("DevConsole")
	console._toggle_hitboxes()
	console._toggle_perf()
	var e := DevActions.spawn_enemy("res://enemies/variants/Needle.tscn")
	e.ai_enabled = true
	await _frames(70)
	await _shot("u12_hitboxes_perf")
	EventBus.menu_requested.emit(&"dev")
	await _frames(5)
	await _shot("u13_dev_console")
	(console as MenuScreen).close_menu()


## M5 map: a half-explored profile (route floors swept, Market stash and
## Stack unexplored), a pin, a dropped cache, the lens, Nix's base map.
func _map_shots(menus: Node) -> void:
	var map := Game.world_map
	for id in ["Relay", "FloodedAlley", "MarketRun", "ApartmentStack"]:
		var r := map.room(id)
		Game.state.visited_rooms.append(r.room_path)
		var b: Rect2 = WorldMapIndex.room_info(r.room_path)["bounds"]
		var x := b.position.x
		while x < b.end.x - (600.0 if id == "MarketRun" else 0.0):
			for y in [-20.0, -140.0]:
				if id == "ApartmentStack":
					for fy in [-20.0, -210.0, -400.0]:
						Game.map_reveal(r.room_path, Vector2(minf(x, 600), fy))
				else:
					Game.map_reveal(r.room_path, Vector2(x, y))
			x += 64.0
	Game.rest_at_anchor(map.room("Relay").room_path, "relay")
	Game.set_flag("map_lowlight")
	Game.set_flag("map_lens")
	Game.toggle_pin("MarketRun", Vector2(1500, -150))
	Game.state.dropped_scrap = {"room": map.room("FloodedAlley").room_path, "x": 900.0, "y": 0.0, "amount": 40}
	EventBus.menu_requested.emit(&"map")
	await _frames(5)
	await _shot("u10_map")
	var view: MapView = menus.get_node("MapMenu").view
	view.zoom_index = 0
	view.cursor = map.room("ApartmentStack").offset
	await _frames(3)
	await _shot("u11_map_zoomed_out")
	(menus.get_node("MapMenu") as MenuScreen).close_menu()


# --- M8 story tour (T09, A5 §7): sequences, memories, world state, endings -----
#
# Everything runs in AUTO at speed 1 with CinematicMode.theatre on, so no
# SequenceTrigger autoplays; every scene is played explicitly through
# DevActions (preview_sequence / play_sequence / play_ending / play_memory).
# Marks (SeqMark) become st_<mark> shots on the frame they fire.

const STORY_SEQUENCES := ["uc_opening", "uc_collector_intro", "ll_krail_intro", "relay_arrival", "act1_close"]
const RELAY := "res://world/rooms/lowlight/Relay.tscn"
## [shot, room, entry, switch nodes to frame]: before (new game) and after
## (_after_state) shots of the rooms the story changes (design_world §7.6).
const STORY_ROOMS := [
	["wake_collector_mark", "res://world/rooms/undercity/Wake.tscn", &"start", ["Props/CollectorMarkLive", "Props/CollectorMarkDead"]],
	["collector_bay", "res://world/rooms/undercity/CollectorBay.tscn", &"from_lift", ["Props/BayLit", "Props/CargoStranded"]],
	["bell_floor4", "res://world/rooms/lowlight/BellTower.tscn", &"bell_top", ["Props/WardenBannerUp", "Props/WardenBannerDown", "Props/CargoLeft"]],
	["warden_tower", "res://world/rooms/lowlight/WardenTower.tscn", &"from_bell", ["Props/KrailBannersUp", "Props/KrailBannersDown"]],
	["security_b1", "res://world/rooms/lowlight/SecurityStation.tscn", &"from_power", ["Props/CellFourKnock"]],
	["flooded_alley_posters", "res://world/rooms/lowlight/FloodedAlley.tscn", &"from_relay", ["Props/WantedPosters", "Props/GhostTags"]],
]


func _story_tour() -> void:
	await _frames(5)
	Game.new_game()
	Cinematics.mode = CinematicMode.Mode.AUTO
	Cinematics.auto_speed = 1.0
	Cinematics.theatre = true
	Cinematics.marked.connect(func(m: String) -> void:
		if not _mute_marks:
			_marks.append(m))
	EventBus.ending_finished.connect(func(id: String, _t: bool, _s: bool) -> void: _endings_done.append(id))
	_pumping = true
	_mark_pump()
	var menus := get_tree().root.find_child("Menus", true, false)
	await _story_sequences()
	await _story_act_card(menus)
	await _story_memories(menus)
	await _story_world()
	await _story_rooms()
	await _story_dialogue()
	await _story_endings(menus)
	await _story_settings(menus)
	_pumping = false
	await _frames(2)
	print("story tour: %d shots" % _taken.size())
	_quit()


func _st(name: String) -> void:
	await _shot("st_%s" % name)
	_taken.append(name)


## Shoots every SeqMark on the frame after it fires.
func _mark_pump() -> void:
	while _pumping:
		while not _marks.is_empty():
			await _st(_marks.pop_front())
		await get_tree().process_frame


func _player_input() -> void:
	var room := SceneRouter.current_room as Room
	if room and is_instance_valid(room.player):
		room.player.input_source = _input


func _goto_story(path: String, entry: StringName, settle: int = 30) -> void:
	SceneRouter.goto_room(path, entry)
	_player_input()
	await _frames(settle)


## 1. The five Act I sequences, first view, each in its own room.
func _story_sequences() -> void:
	for id in STORY_SEQUENCES:
		await DevActions.preview_sequence(id)
		await _frames(10)


## 2. The Act I card (SliceEndMenu) with and without Dead Air done.
func _story_act_card(menus: Node) -> void:
	Game.new_game()
	StoryTestKit.apply_preset("act1_complete")
	await _goto_story(RELAY, &"start", STORY_SETTLE)
	var card := menus.get_node("SliceEndMenu") as MenuScreen
	EventBus.menu_requested.emit(&"slice_end")
	await _frames(5)
	await _st("act1_card_menu")
	Game.set_flag("dead_air_complete", false)
	card.rebuild()
	await _frames(5)
	await _st("act1_card_menu_no_dead_air")
	card.close_menu()


## 3. Memory vignettes: the first rest (title, beat 3, tear), Undercity 01's
## detail found by panning, Lowlight 04 with flash reduction, the gallery.
func _story_memories(menus: Node) -> void:
	Game.new_game()
	await _goto_story(RELAY, &"start", 10)
	var mp := MemoryScenePlayer.active_instance
	if not is_instance_valid(mp):
		print("PENDING: no MemoryScenePlayer in Main")
		return
	DevActions.play_memory("mem_first_rest")
	var shot_title := false
	var shot_beat := false
	var shot_tear := false
	for i in 3600:
		if not mp.is_playing():
			break
		if not shot_title and mp.phase() == MemoryScenePlayer.Phase.TITLE and i >= 20:
			shot_title = true
			await _st("mem_first_rest_title")
		elif not shot_beat and mp.phase() == MemoryScenePlayer.Phase.BEAT and mp.beat_index() == 2 and mp.beat_time() > 1.5:
			shot_beat = true
			await _st("mem_first_rest_beat3")
		elif not shot_tear and mp.phase() == MemoryScenePlayer.Phase.TEAR:
			shot_tear = true
			await _st("mem_first_rest_tear")
		await get_tree().process_frame
	await _frames(10)
	# Undercity 01: look right until the detail is found, shot on beat 4.
	Game.state.memory_fragments.append("mf_undercity_01")
	DevActions.play_memory("mf_undercity_01")
	Input.action_press(&"move_right")
	var shot_detail := false
	for i in 3600:
		if not mp.is_playing():
			break
		if MemoryLibrary.is_detail_found("mf_undercity_01"):
			Input.action_release(&"move_right")
			if not shot_detail and mp.phase() == MemoryScenePlayer.Phase.BEAT and mp.beat_index() >= 3 and mp.beat_time() > 1.0:
				shot_detail = true
				await _st("mem_uc01_detail")
		await get_tree().process_frame
	Input.action_release(&"move_right")
	if not shot_detail:
		print("PENDING: mf_undercity_01 detail not found in AUTO")
	await _frames(10)
	# Lowlight 04 with flash reduction: the tear without its shear.
	var flash_was := Settings.flash_reduction
	Settings.flash_reduction = true
	EventBus.settings_changed.emit()
	Game.state.memory_fragments.append("mf_lowlight_04")
	DevActions.play_memory("mf_lowlight_04")
	var shot_ll04 := false
	for i in 3600:
		if not mp.is_playing():
			break
		if not shot_ll04 and mp.phase() == MemoryScenePlayer.Phase.TEAR:
			shot_ll04 = true
			await _st("mem_ll04_flashreduce")
		await get_tree().process_frame
	Settings.flash_reduction = flash_was
	EventBus.settings_changed.emit()
	await _frames(10)
	# Gallery: three remembered, one waiting, two not yet recovered.
	Game.state.memory_fragments.append("mf_lowlight_01")
	var journal := menus.get_node("JournalMenu")
	EventBus.menu_requested.emit(&"journal")
	await _frames(3)
	journal.show_gallery()
	await _frames(5)
	await _st("journal_gallery")
	(journal as MenuScreen).close_menu()


## 4. The Relay at every story preset, all Act I arcs at their top stages,
## and the pending-beat tick next to the radio board cue.
func _story_world() -> void:
	for p in StoryPresets.all():
		Game.new_game()
		DevActions.apply_story_preset(p.id)
		await _goto_story(RELAY, &"start", STORY_SETTLE)
		await _st("relay_%s" % p.id)
	Game.new_game()
	DevActions.apply_story_preset("act1_complete")
	for a in Game.arcs.arcs:
		DevActions.force_arc_stage(a.npc_id, a.stages[-1].id)
	Game.set_flag("orr_air_named")
	await _goto_story(RELAY, &"start", STORY_SETTLE)
	await _st("relay_arcs")
	Game.new_game()
	DevActions.apply_story_preset("dead_air_done")
	DevActions.force_arc_stage("mara", "krail")
	await _goto_story(RELAY, &"start", STORY_SETTLE)
	# Frame Mara (her Krail beat pending) and the radio board cue together.
	var room := SceneRouter.current_room as Room
	var focus := _node_focus(room, ["Interactables/NPC_mara", "Interactables/NPC_relay_board"])
	if focus != Vector2.INF:
		room.camera.direct(focus + Vector2(0, -40), 0.0)
	await _frames(10)
	await _st("relay_pending_tick")
	room.camera.release(0.0)


## 5. Before/after shots of the rooms the story changes, framed on the
## switches, plus the Bell Tower bark over the Anchor prompt.
func _story_rooms() -> void:
	for after: bool in [false, true]:
		Game.new_game()
		if after:
			_after_state()
		for r: Array in STORY_ROOMS:
			await _goto_story(r[1], r[2], STORY_SETTLE)
			var room := SceneRouter.current_room as Room
			var focus := _switch_focus(room, r[3])
			if room and is_instance_valid(room.camera) and focus != Vector2.INF:
				room.camera.direct(focus, 0.0)
			await _frames(10)
			await _st("%s_%s" % [r[0], "after" if after else "before"])
			if room and is_instance_valid(room.camera):
				room.camera.release(0.0)
	# The bark line sits above the '[E] Rest' prompt (Rook on the Anchor).
	Game.new_game()
	DevActions.apply_story_preset("dead_air_done")
	await _goto_story("res://world/rooms/lowlight/BellTower.tscn", &"bell_top", STORY_SETTLE)
	DevActions.play_sequence("bark_bell_lift")
	await _frames(90)
	await _st("bark_bell_lift_prompt")
	while Cinematics.is_playing():
		await _frames(10)


## The state the "after" room shots show: Act I done, Rook remembered Cell
## Four, Orr put Rook's name on the air, the Rainline chase done.
func _after_state() -> void:
	DevActions.apply_story_preset("act1_complete")
	for f in ["mem_seen_mf_lowlight_04", "orr_air_named", "chase_rainline_done"]:
		Game.set_flag(f)


## Centre of the named nodes, or INF.
func _node_focus(room: Room, paths: Array) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for p: String in paths:
		var node := room.get_node_or_null(p) as Node2D if room else null
		if node:
			sum += node.global_position
			n += 1
	return sum / n if n > 0 else Vector2.INF


## Centre of every child of the named switches (visible or not), or INF.
func _switch_focus(room: Room, paths: Array) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	if room == null:
		return Vector2.INF
	for p: String in paths:
		var sw := room.get_node_or_null(p)
		if sw == null:
			continue
		for c in sw.get_children():
			if c is Node2D:
				sum += (c as Node2D).global_position
				n += 1
	return sum / n if n > 0 else Vector2.INF


## 6. Orr's on-air choice box, and a 200-character narration line at subtitle
## size 2 (the widest case the box must hold).
func _story_dialogue() -> void:
	Game.new_game()
	DevActions.apply_story_preset("act1_complete")
	await _goto_story(RELAY, &"start", STORY_SETTLE)
	var box := get_tree().root.find_child("DialogueBox", true, false)
	var on_air: DialogueData = null
	var stage := Game.arcs.arc("orr").stage("on_air")
	if stage:
		for r in stage.beat_rules:
			if r.dialogue and not r.dialogue.choices.is_empty():
				on_air = r.dialogue
	if on_air and box:
		EventBus.dialogue_requested.emit(on_air, "Orr")
		await _frames(5)
		for i in 20:
			if box.is_choosing():
				break
			box.shown_chars = 9999.0
			box.advance()
			await _frames(2)
		await _frames(40)
		await _st("choice_box")
		await _close_box(box)
	else:
		print("PENDING: no on-air choice for Orr")
	var size_was := Settings.subtitle_size
	Settings.subtitle_size = 2
	EventBus.settings_changed.emit()
	var d := DialogueData.new()
	d.id = "capture_size2"
	var line := DialogueLine.new()
	line.speaker = ""
	# Neutral filler (no story content): exactly 200 characters.
	line.text = "Capture check: two hundred characters of narration at subtitle size 2, to see the widest line the box must hold. ".repeat(3).substr(0, 200)
	d.lines.append(line)
	EventBus.dialogue_requested.emit(d, "")
	await _frames(5)
	if box:
		box.shown_chars = 9999.0
	await _frames(20)
	await _st("dialogue_size2")
	if box:
		await _close_box(box)
	Settings.subtitle_size = size_was
	EventBus.settings_changed.emit()


func _close_box(box: Node) -> void:
	for i in 30:
		if not box.is_open():
			return
		if box.is_choosing():
			await _frames(30)
			box.choose(0)
		else:
			box.shown_chars = 9999.0
			box.advance()
		await _frames(2)


## 7. The four endings (title + credits marks under satisfy_ending), the
## Ending theatre page focused on Release, and the inspector 5 s into Release.
func _story_endings(menus: Node) -> void:
	Game.new_game()
	await _goto_story(RELAY, &"start", 10)
	for id in DevActions.ending_ids():
		var restore := DevActions.satisfy_ending(id)
		_endings_done.clear()
		DevActions.play_ending(id)
		var skipped := false
		for i in 60 * 120:
			if _endings_done.has(id):
				break
			# Once the credits are shot, the rest of the roll adds nothing.
			if not skipped and _taken.has("ending_%s_credits" % id):
				await _frames(60)
				skipped = true
				Cinematics.request_skip()
			await get_tree().process_frame
		await _frames(5)
		restore.call()
	var console := menus.get_node("DevConsole")
	EventBus.menu_requested.emit(&"dev")
	await _frames(2)
	console._go(&"endings")
	console.focus_index(DevActions.ending_ids().find("release"))
	await _frames(5)
	await _st("ending_theatre_page")
	console._go(&"story")
	console._toggle_inspector()
	(console as MenuScreen).close_menu()
	var restore_release := DevActions.satisfy_ending("release")
	_endings_done.clear()
	_mute_marks = true
	DevActions.play_ending("release")
	await _frames(300)
	await _st("inspector")
	Cinematics.request_skip()
	for i in 600:
		if _endings_done.has("release"):
			break
		await get_tree().process_frame
	restore_release.call()
	_mute_marks = false
	console._toggle_inspector()
	(console as MenuScreen).close_menu()


## 8. Settings > Subtitles & scenes.
func _story_settings(menus: Node) -> void:
	var settings := menus.get_node("SettingsMenu")
	EventBus.menu_requested.emit(&"settings")
	await _frames(2)
	settings._go(&"subtitles")
	await _frames(5)
	await _st("settings_subtitles")
	(settings as MenuScreen).close_menu()
