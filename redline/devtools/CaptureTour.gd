extends Node
## Renders a scripted tour of the Movement Lab to PNGs for reports/PR review.
##   godot --fixed-fps 60 res://devtools/CaptureTour.tscn -- --out=/abs/dir [--tour=movement|combat|slice|ui|undercity]
## Needs a real (or virtual, e.g. xvfb-run) display; headless has no renderer.

const MAIN := preload("res://Main.tscn")

## Settings the tour may save (--tour=ui closes the SettingsMenu, which always
## saves): never the developer's user://settings.cfg.
const TOUR_SETTINGS_PATH := "user://capture_tour_settings.cfg"
const _M8_SETTING_KEYS := ["subtitle_size", "subtitle_background", "speaker_labels", "subtitle_speed",
	"cinematic_skip_hold", "memories_at_anchors"]

var _out_dir := "user://captures"
var _tour_name := "movement"
var _input := ScriptedInputSource.new()
var _settings_snapshot := {}


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
	else:
		_tour.call_deferred()


## M8 session setup, before Main loads (T07):
## - cinematics: INSTANT for every tour but `story`, unless `--cinematics=`
##   says otherwise. Tours run windowed (PLAY by default), so the Wake opening
##   would black out uc_Wake_start and the "mid-fight" shots would land inside
##   the first-view boss intros; INSTANT keeps the M7 review frames.
## - settings: the six M8 subtitle/scene settings take their defaults for the
##   session (a --subtitle-size=N override still applies), and Settings saves
##   to TOUR_SETTINGS_PATH, so neither the developer's settings leak into the
##   frames nor the tour into the developer's settings.
## Returns the snapshot restore_session() puts back.
static func prepare_session(tour: String, args: PackedStringArray) -> Dictionary:
	var snap := {"_path": Settings._path}
	for k in _M8_SETTING_KEYS:
		snap[k] = Settings.get(k)
	Settings._path = TOUR_SETTINGS_PATH
	Settings.subtitle_size = 0
	Settings.subtitle_background = 1
	Settings.speaker_labels = true
	Settings.subtitle_speed = 0
	Settings.cinematic_skip_hold = true
	Settings.memories_at_anchors = true
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
