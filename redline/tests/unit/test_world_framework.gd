extends RedlineTestCase
## M5 world framework: Nix and the Chart Lowlight quest, transit between
## Anchors, NPC talk state, world-state switches, map markers.

const RELAY := "res://world/rooms/lowlight/Relay.tscn"
const BELL := "res://world/rooms/lowlight/BellTower.tscn"

var root: Node2D
var menus: Array[StringName] = []


func before_each() -> void:
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	SaveManager.save_dir = "user://test_world_framework"
	Game.new_game()
	menus.clear()
	EventBus.menu_requested.connect(_on_menu)


func after_each() -> void:
	EventBus.menu_requested.disconnect(_on_menu)
	SceneRouter.current_room = null
	SceneRouter.world_root = null
	root.queue_free()
	SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR
	Game.new_game()
	await physics_frames(2)


func _on_menu(id: StringName) -> void:
	menus.append(id)


func _nix() -> NpcProfile:
	return load("res://data/npcs/nix.tres")


func _quest(id: String) -> QuestData:
	for q in Game.quests.quests:
		if q.id == id:
			return q
	return null


func test_nix_is_in_the_relay_and_on_the_map() -> void:
	var npcs: Array = WorldMapIndex.room_info(RELAY)["npcs"]
	var nix := npcs.filter(func(n: Dictionary) -> bool: return n["id"] == "nix")
	check(nix.size() == 1 and nix[0]["role"] == "Cartographer", "Nix should be in the Relay with a map pin")
	for n: Dictionary in npcs:
		check(n["role"] != "", "%s has no map label" % n["id"])
	check(_nix().validate().is_empty(), "nix profile invalid")


func test_nix_intro_starts_chart_quest_and_report_pays_out() -> void:
	var d := _nix().pick_dialogue()
	check(d.id == "nix_intro", "first talk should be the intro, got %s" % d.id)
	Game.apply_dialogue(d)
	check(menus.has(&"shop_nix"), "intro should open Nix's shop")
	var q := _quest("chart_lowlight")
	check(q != null and q.is_started(), "Chart Lowlight should start")
	check(_nix().pick_dialogue().id == "nix_shop", "after the intro Nix just sells")
	Game.set_flag("talks_nix", 4)
	check(_nix().pick_dialogue().id == "nix_regular", "a regular gets a different line (talk count state)")
	var scrap := Game.state.total_scrap()
	Game.set_flag("map_charted_lowlight")
	check(q.current_stage() == 1, "charting should finish stage 1")
	check(_nix().pick_dialogue().id == "nix_report", "Nix should react to the charted map")
	Game.apply_dialogue(_nix().pick_dialogue())
	check(Game.has_flag("chart_lowlight_complete"), "quest should complete")
	check(Game.state.total_scrap() == scrap + q.reward_scrap and Game.has_flag("map_lens"), "reward: Scrap and the lens (scrap %d -> %d, lens %s)" % [scrap, Game.state.total_scrap(), Game.has_flag("map_lens")])


func test_npc_talks_are_counted() -> void:
	SceneRouter.goto_room(RELAY, &"start")
	await physics_frames(3)
	var npc: NPC = SceneRouter.current_room.find_child("NPC_nix", true, false)
	npc.interact((SceneRouter.current_room as Room).player)
	npc.interact((SceneRouter.current_room as Room).player)
	check(Game.flag_int("talks_nix") == 2, "talk count should be tracked")
	check(Game.check_condition("atleast:talks_nix:2") and not Game.check_condition("atleast:talks_nix:3"), "atleast condition")


func test_buying_the_base_map_reveals_outlines() -> void:
	var shop: ShopData = load("res://data/shops/shop_nix.tres")
	var menu: MenuScreen = load("res://ui/menus/ShopMenu.gd").new()
	add_child(menu)
	menu.shop = shop
	Game.state.scrap_banked = 500
	var base_map: ShopItem = shop.items.filter(func(i: ShopItem) -> bool: return i.upgrade_flag == "map_lowlight")[0]
	check(not MapProgress.knows_outline(Game.state, Game.world_map.room("NeonRoofs")), "roofs unknown before the map")
	check(menu.buy(base_map), "base map purchase")
	check(MapProgress.knows_outline(Game.state, Game.world_map.room("NeonRoofs")), "base map should reveal Lowlight outlines")
	check(not menu.buy(base_map), "can't buy it twice")
	menu.queue_free()


func test_transit_between_rested_anchors() -> void:
	SceneRouter.goto_room(RELAY, &"start")
	await physics_frames(3)
	Game.rest_at_anchor(BELL, "bell_top")
	Game.rest_at_anchor(RELAY, "relay")
	var menu: MenuScreen = load("res://ui/menus/LoadoutMenu.gd").new()
	add_child(menu)
	menu.open_menu()
	var labels := menu._body.get_children().filter(func(n: Node) -> bool: return n is Button).map(func(b: Button) -> String: return b.text)
	check(not labels.any(func(t: String) -> bool: return t.begins_with("Transit")), "no transit without the pass")
	menu.close_menu()
	Game.set_flag("transit_pass")
	menu.open_menu()
	menu._show_transit()
	var dest := menu._body.get_children().filter(func(n: Node) -> bool: return n is Button)
	check(dest.size() == 2 and (dest[0] as Button).text.contains("Bell Tower"), "Bell Tower should be the one destination")
	(dest[0] as Button).pressed.emit()
	for i in 120:
		await physics_frames(1)
		if SceneRouter.current_room_path == BELL and not SceneRouter.transitioning:
			break
	check(SceneRouter.current_room_path == BELL, "should arrive in the Bell Tower")
	var anchor_pos: Vector2 = WorldMapIndex.room_info(BELL)["spawns"]["bell_top"]
	var p := (SceneRouter.current_room as Room).player
	check(p.position.distance_to(anchor_pos) < 40.0, "should arrive at the Anchor (%s vs %s)" % [p.position, anchor_pos])
	check(Game.state.last_anchor_room == BELL and Game.state.last_anchor_id == "bell_top", "arrival Anchor becomes the respawn")
	menu.queue_free()


func test_relay_world_state_switches() -> void:
	SceneRouter.goto_room(RELAY, &"start")
	await physics_frames(3)
	var radio: WorldStateSwitch = SceneRouter.current_room.find_child("RadioRestored", true, false)
	var trophy: WorldStateSwitch = SceneRouter.current_room.find_child("KrailTrophy", true, false)
	check(radio != null and trophy != null, "Relay switches missing")
	check(not radio.visible and not trophy.visible, "nothing restored yet")
	Game.set_flag("dead_air_complete")
	check(radio.visible and not trophy.visible, "radio should light up live when Dead Air completes")
	Game.set_flag("warden_krail_defeated")
	check(trophy.visible, "trophy after Krail")


func test_dash_gap_marker_resolves_with_dash() -> void:
	var markers: Array = WorldMapIndex.room_info("res://world/rooms/lowlight/FloodedAlley.tscn")["markers"]
	check(markers.size() == 1 and markers[0]["resolved_when"] == "ability:dash", "alley dash-gap marker missing")
	check(not Game.check_condition(markers[0]["resolved_when"]), "unresolved before Dash")
	Game.set_ability(&"dash", true)
	check(Game.check_condition(markers[0]["resolved_when"]), "resolved with Dash")
