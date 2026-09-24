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


## The skip is keyed on content, not on the file (M7 plan, M4 §8): the
## CollectorBay stub has no arena, so nothing past the check may run until a
## BossArena whose boss is a collector_drone exists. The CollectorBay room
## task deletes this skip branch.
func test_quick_boss_restart_rearms_collector() -> void:
	var path: String = DevActions.boss_restart_target("collector_drone")[0]
	var armed := false
	if ResourceLoader.exists(path):
		var probe := (load(path) as PackedScene).instantiate()
		for a in probe.find_children("*", "BossArena", true, false):
			var boss := a.get_node_or_null((a as BossArena).boss_path) as Enemy
			if boss and boss.data and boss.data.id == &"collector_drone":
				armed = true
		probe.free()
	if not armed:
		print("PENDING: CollectorBay has no Collector arena yet")
		return
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
