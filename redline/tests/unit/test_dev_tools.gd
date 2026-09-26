extends RedlineTestCase
## M6 dev tools (bible §34): teleport, unlock-all, quick boss restart, enemy
## spawning, save-state inspector, hitbox view, perf graph, console menu.

var root: Node2D


func before_each() -> void:
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	SaveManager.save_dir = "user://test_dev_tools"
	Game.new_game()


func after_each() -> void:
	SceneRouter.current_room = null
	SceneRouter.world_root = null
	root.queue_free()
	SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR
	Game.new_game()
	await physics_frames(2)


func _arrive(path: String) -> bool:
	for i in 150:
		await physics_frames(1)
		if SceneRouter.current_room_path == path and not SceneRouter.transitioning:
			return true
	return false


func test_available_in_debug_and_lists_every_entry() -> void:
	check(DevActions.available(), "tests run in a debug build; tools should be available")
	var targets := DevActions.teleport_targets()
	var spawns := 0
	for r in Game.world_map.rooms:
		spawns += (WorldMapIndex.room_info(r.room_path)["spawns"] as Dictionary).size()
	check(targets.size() == spawns and spawns > 10, "teleport list should cover every entry (%d/%d)" % [targets.size(), spawns])


func test_teleport_moves_to_room_entry() -> void:
	SceneRouter.goto_room("res://world/rooms/lowlight/Relay.tscn", &"start")
	await physics_frames(3)
	DevActions.teleport("res://world/rooms/lowlight/NeonRoofs.tscn", "from_power")
	check(await _arrive("res://world/rooms/lowlight/NeonRoofs.tscn"), "teleport did not arrive")
	var p := (SceneRouter.current_room as Room).player
	check(p.position.x > 2000.0, "should arrive at the from_power entry (x %.0f)" % p.position.x)


func test_unlock_all_profile() -> void:
	DevActions.unlock_all()
	var st := Game.state
	check(st.owned_weapons.size() == Game.catalog.weapons.size() and st.owned_circuits.size() == Game.catalog.circuits.size(), "everything owned")
	check(Game.check_condition("ability:dash") and Game.transit_unlocked() and Game.has_flag("map_lens"), "abilities and map tools")
	check(MapProgress.district_ratio(st, Game.world_map, "lowlight") > 0.95, "map should be fully explored")
	check(st.anchors_rested.size() >= 3 and Game.core_capacity() >= 7, "anchors / capacity")


func test_quick_boss_restart_rearms_krail() -> void:
	Game.set_flag("warden_krail_defeated")
	Game.set_flag("unlocked_dash")
	Game.state.health = 1
	SceneRouter.goto_room("res://world/rooms/lowlight/Relay.tscn", &"start")
	await physics_frames(3)
	DevActions.quick_boss_restart()
	check(await _arrive("res://world/rooms/lowlight/WardenTower.tscn"), "should land in the Warden Tower")
	check(not Game.has_flag("warden_krail_defeated"), "Krail should be re-armed")
	var arena := SceneRouter.current_room.find_children("*", "BossArena", true, false)[0] as BossArena
	check(is_instance_valid(arena.boss), "boss should be present again")
	var p := (SceneRouter.current_room as Room).player
	check(p.combat.health == p.combat.config.max_health, "full health for the retry")
	# The way out keys on the Dash (owned here): the re-armed fight still
	# seals it (BossArena lists ExitGate, D-100).
	var exit_gate := SceneRouter.current_room.get_node_or_null("Geometry/ExitGate") as Gate
	arena._on_body_entered(p)
	await physics_frames(2)
	check(exit_gate != null and exit_gate.closed, "a re-armed fight seals ExitGate even with the reward owned")


func test_quick_boss_restart_rearms_collector() -> void:
	var path: String = DevActions.boss_restart_target("collector_drone")[0]
	Game.set_flag("collector_drone_defeated")
	Game.state.health = 1
	SceneRouter.goto_room("res://world/rooms/lowlight/Relay.tscn", &"start")
	await physics_frames(3)
	DevActions.quick_boss_restart("collector_drone")
	check(await _arrive(path), "should land in the Collector Bay")
	check(not Game.has_flag("collector_drone_defeated"), "the Collector should be re-armed")
	var arena := SceneRouter.current_room.find_children("*", "BossArena", true, false)[0] as BossArena
	check(is_instance_valid(arena.boss), "boss should be present again")
	var p := (SceneRouter.current_room as Room).player
	check(p.combat.health == p.combat.config.max_health, "full health for the retry")


func test_spawn_enemy_and_inspector() -> void:
	SceneRouter.goto_room("res://world/rooms/lowlight/Relay.tscn", &"start")
	await physics_frames(3)
	check(DevActions.enemy_scenes().size() >= 7, "enemy list should include every variant")
	var e := DevActions.spawn_enemy("res://enemies/variants/Hopper.tscn")
	check(e != null and e.get_parent() == SceneRouter.current_room, "enemy should spawn in the room")
	Game.set_flag("inspect_me")
	var text := DevActions.state_summary()
	check(text.contains("inspect_me") and text.contains("Scrap"), "inspector should list flags and currencies")
	check(JSON.parse_string(DevActions.state_json()) is Dictionary, "save JSON should parse")


func test_console_hitboxes_and_perf_graph() -> void:
	SceneRouter.goto_room("res://world/rooms/lowlight/Relay.tscn", &"start")
	await physics_frames(3)
	var menu: MenuScreen = load("res://ui/menus/DevConsole.gd").new()
	add_child(menu)
	menu.open_menu()
	check(menu.is_open() and get_tree().paused, "console should open and pause")
	menu._toggle_hitboxes()
	menu._toggle_perf()
	menu._go(&"state")
	menu._go(&"teleport")
	menu._go(&"main")
	await get_tree().process_frame
	check(is_instance_valid(menu.hitboxes) and is_instance_valid(menu.perf), "overlays should exist")
	menu._toggle_hitboxes()
	menu._toggle_perf()
	menu.close_menu()
	check(not get_tree().paused, "console should unpause on close")
	menu.queue_free()


# --- M9 T14: the Endgame & build hub and its pages (D6 §6) ---------------------------

func _console() -> DevConsole:
	var c: DevConsole = load("res://ui/menus/DevConsole.gd").new()
	add_child(c)
	c.open_menu()
	return c


func _rows(c: DevConsole) -> PackedStringArray:
	var out := PackedStringArray()
	for n in c._body.get_children():
		if n is Button and not n.is_queued_for_deletion():
			out.append((n as Button).text)
	return out


func test_endgame_hub_and_pages_fit_270() -> void:
	var c := _console()
	for page: StringName in [&"main", &"endgame"] + DevConsole.M9_PAGES.keys():
		c._go(page)
		await get_tree().process_frame
		var h := await menu_height(c)
		check(h <= 270.0, "dev page %s is %.0f px tall" % [page, h])
		check(_rows(c).size() <= DevConsole.PAGE_ROWS + 2, "page %s rows %d" % [page, _rows(c).size()])
	c.close_menu()
	c.queue_free()


func test_parent_map_back_navigation() -> void:
	var c := _console()
	for page: StringName in DevConsole.PARENT:
		c._go(page)
		var back := -1
		var rows := _rows(c)
		for i in rows.size():
			if rows[i] == "Back":
				back = i
		check(back >= 0, "page %s has a Back row" % page)
		var buttons := c._body.get_children().filter(func(n: Node) -> bool: return n is Button and not n.is_queued_for_deletion())
		(buttons[back] as Button).pressed.emit()
		check(c.page == DevConsole.PARENT[page], "Back from %s returns to %s (got %s)" % [page, DevConsole.PARENT[page], c.page])
	c.close_menu()
	c.queue_free()


func test_demo_session_toggle_restores() -> void:
	var before := {"save": SaveManager.save_dir, "store": Platform.store_dir, "settings": Settings._path, "playtest": Playtest.dir,
		"demo": BuildInfo.is_demo()}
	var had_demo_dir := DirAccess.dir_exists_absolute("user://demo")
	DemoDevActions.set_demo_session(true)
	check(BuildInfo.is_demo() and DemoDevActions.demo_session_on(), "a demo session is on")
	DemoDevActions.set_demo_session(false)
	var after := {"save": SaveManager.save_dir, "store": Platform.store_dir, "settings": Settings._path, "playtest": Playtest.dir,
		"demo": BuildInfo.is_demo()}
	check(after == before, "every path and the build kind come back: %s -> %s" % [before, after])
	check(not DemoDevActions.demo_session_on(), "the session is off")
	# The redirect made user://demo for its settings file (BuildInfo).
	if not had_demo_dir:
		AtomicJson.remove_tree("user://demo")


func test_locale_reset_restores_en() -> void:
	var c := _console()
	c._go(&"locale")
	LocaleDevActions.set_locale("en_XA")
	Loc.flag_missing = true
	check(Loc.locale() == "en_XA", "pseudo-locale on")
	var buttons := c._body.get_children().filter(func(n: Node) -> bool: return n is Button and (n as Button).text == "Reset to en")
	check(buttons.size() == 1, "the Locale page has its reset row")
	(buttons[0] as Button).pressed.emit()
	check(Loc.locale() == Loc.SOURCE_LOCALE and not Loc.flag_missing, "back to English, no markers")
	c.close_menu()
	c.queue_free()


func test_enemy_scenes_uses_datadir() -> void:
	check(DataDir.load_name("Hopper.tscn.remap", "tscn") == "Hopper.tscn", "an exported .remap name loads as its scene")
	check(DataDir.load_name("Hopper.tscn.import", "tscn") == "", "other files are skipped")
	var src := FileAccess.get_file_as_string("res://devtools/DevActions.gd")
	var i := src.find("static func enemy_scenes()")
	check(i >= 0 and src.substr(i, 120).contains("DataDir.list_scenes"), "enemy_scenes lists through DataDir")
	check(DevActions.enemy_scenes().has("res://enemies/variants/Hopper.tscn"), "the variants are listed")
