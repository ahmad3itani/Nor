extends RedlineTestCase
## M5 map: layout matches the rooms, fog of discovery, pins, charted flags,
## transit, conditions and the v3 save migration.

var map: WorldMapData


func before_each() -> void:
	Game.new_game()
	map = Game.world_map


func after_each() -> void:
	Game.world_map = Game.WORLD_MAP
	Game.new_game()


func test_every_slice_room_is_on_the_map_once() -> void:
	var ids := {}
	for r in map.rooms:
		check(ResourceLoader.exists(r.room_path), "map room missing: %s" % r.room_path)
		check(not ids.has(r.room_id()), "room listed twice: %s" % r.room_id())
		ids[r.room_id()] = true
	for dir in ContentValidator.WORLD_ROOM_DIRS:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".tscn"):
				check(ids.has(f.get_basename()), "room not on the world map: %s/%s" % [dir, f])


## Every exit must meet its target entry on the map (doorways line up),
## unless it is a declared transit link (lifts).
func test_exits_line_up_on_the_map() -> void:
	for r in map.rooms:
		var info := WorldMapIndex.room_info(r.room_path)
		for e: Dictionary in info["exits"]:
			var target := map.room(String(e["target"]).get_file().get_basename())
			check(target != null, "%s exits to a room not on the map" % r.room_id())
			if target == null:
				continue
			var link := "%s>%s" % [r.room_id(), target.room_id()]
			var here: Vector2 = r.offset + (e["rect"] as Rect2).get_center()
			var spawns: Dictionary = WorldMapIndex.room_info(target.room_path)["spawns"]
			check(spawns.has(e["entry"]), "%s: missing entry %s" % [link, e["entry"]])
			var there: Vector2 = target.offset + spawns.get(e["entry"], Vector2.ZERO)
			if map.transit_links.has(link):
				continue
			check(here.distance_to(there) < 160.0, "%s: exit and entry are %d px apart on the map" % [link, roundi(here.distance_to(there))])


func test_rooms_do_not_overlap_on_the_map() -> void:
	for i in map.rooms.size():
		for j in range(i + 1, map.rooms.size()):
			var a := map.rooms[i]
			var b := map.rooms[j]
			var ra: Rect2 = WorldMapIndex.room_info(a.room_path)["bounds"]
			var rb: Rect2 = WorldMapIndex.room_info(b.room_path)["bounds"]
			ra.position += a.offset
			rb.position += b.offset
			var overlap := ra.grow(-2).intersection(rb.grow(-2))
			check(overlap.get_area() <= 0.0, "%s overlaps %s on the map" % [a.room_id(), b.room_id()])


func test_index_finds_anchors_npcs_boss_and_secrets() -> void:
	var relay := WorldMapIndex.room_info("res://world/rooms/lowlight/Relay.tscn")
	check(relay["anchors"].size() == 1 and relay["npcs"].size() >= 3, "relay anchors/npcs not indexed")
	var tower := WorldMapIndex.room_info("res://world/rooms/lowlight/WardenTower.tscn")
	check(tower["bosses"].size() == 1 and tower["bosses"][0]["flag"] == "warden_krail_defeated", "boss not indexed")
	var secrets := 0
	for r in map.rooms:
		secrets += (WorldMapIndex.room_info(r.room_path)["secrets"] as Array).size()
	check(secrets == (SliceStats.totals()["secret_ids"] as Array).size(), "map secrets (%d) != slice secrets" % secrets)


func test_reveal_marks_cells_and_charts_the_district() -> void:
	var path := "res://world/rooms/lowlight/NeonRoofs.tscn"
	var n := MapProgress.reveal(Game.state, map, path, Vector2(200, -120))
	check(n > 0, "reveal should mark cells")
	check(MapProgress.reveal(Game.state, map, path, Vector2(200, -120)) == 0, "second reveal of the same spot adds nothing")
	var ratio := MapProgress.room_ratio(Game.state, map, path)
	check(ratio > 0.0 and ratio < 0.2, "partial ratio expected, got %.2f" % ratio)
	check(not Game.has_flag("map_charted_lowlight"), "not charted yet")
	for r in map.rooms_in("lowlight"):
		var b: Rect2 = WorldMapIndex.room_info(r.room_path)["bounds"]
		var y := b.position.y + 32.0
		while y < b.end.y:
			var x := b.position.x + 32.0
			while x < b.end.x:
				Game.map_reveal(r.room_path, Vector2(x, y))
				x += 96.0
			y += 96.0
	check(MapProgress.district_ratio(Game.state, map, "lowlight") > 0.95, "sweep should explore the district")
	check(Game.has_flag("map_charted_lowlight"), "charted flag should be set past the threshold")


## Chart thresholds per district (M7, D8a; final values D8b). D8a's interim
## Lowlight 0.34 kept Nix's chart as hard as before the four new Lowlight
## rooms landed; D8b set both from measured standable coverage (see
## test_thresholds_match_standable_coverage).
func test_district_thresholds() -> void:
	check_near(map.threshold_for("lowlight"), 0.5, 0.0001, "lowlight threshold")
	check_near(map.threshold_for("undercity"), 0.4, 0.0001, "undercity threshold")
	check_near(map.threshold_for("relay"), map.charted_threshold, 0.0001, "districts without an entry use charted_threshold")
	# Game.map_reveal must read the per-district value, not charted_threshold.
	# A full sweep of Lowlight reveals 0.999 of it (a few corner cells are
	# never within reach), so 1.0 is out of reach and 0.9 is not.
	for pair: Array in [[1.0, false], [0.9, true]]:
		Game.new_game()
		var dup := map.duplicate() as WorldMapData
		dup.district_thresholds = {"lowlight": pair[0]}
		dup.charted_threshold = 0.1
		Game.world_map = dup
		_sweep_district("lowlight")
		Game.world_map = map
		check(Game.has_flag("map_charted_lowlight") == pair[1], "threshold %.2f: charted should be %s" % [pair[0], pair[1]])


func _sweep_district(district: String) -> void:
	for r in Game.world_map.rooms_in(district):
		var b: Rect2 = WorldMapIndex.room_info(r.room_path)["bounds"]
		var y := b.position.y + 32.0
		while y < b.end.y:
			var x := b.position.x + 32.0
			while x < b.end.x:
				Game.map_reveal(r.room_path, Vector2(x, y))
				x += 96.0
			y += 96.0


## Final chart thresholds (M7, D8b). Each district's share must lie within
## [0.6, 0.85] of its standable coverage: the share a player reaches who
## stands on every surface of every room (secrets included). Below 0.6 the
## chart is a formality; above 0.85 it demands near-perfect sweeping of
## rooms whose tall bounds hold many cells no path reaches.
func test_thresholds_match_standable_coverage() -> void:
	for district in ["undercity", "lowlight"]:
		var standable := _standable_ratio(district)
		var t := map.threshold_for(district)
		print("  [D8b] %s: standable %.3f, threshold %.2f (band %.3f..%.3f)" % [district, standable, t, 0.6 * standable, 0.85 * standable])
		check(t >= 0.6 * standable - 0.0001 and t <= 0.85 * standable + 0.0001,
			"%s threshold %.2f outside [0.6, 0.85] x standable %.3f" % [district, t, standable])


## Reveals from Rook's body centre (17 px above the top) every 32 px along
## the top of every graybox block and one-way in the district, into a scratch
## state, and returns the district ratio: an upper bound on real exploration.
func _standable_ratio(district: String) -> float:
	var state := GameState.new()
	for r in map.rooms_in(district):
		for blk: Dictionary in WorldMapIndex.room_info(r.room_path)["blocks"]:
			var rect: Rect2 = blk["rect"]
			var x := rect.position.x
			while true:
				MapProgress.reveal(state, map, r.room_path, Vector2(minf(x, rect.end.x), rect.position.y - 17.0))
				if x >= rect.end.x:
					break
				x += 32.0
	return MapProgress.district_ratio(state, map, district)


func test_pins_toggle_and_cap() -> void:
	check(Game.toggle_pin("Relay", Vector2(100, 0)), "pin added")
	check(not Game.toggle_pin("Relay", Vector2(110, 0)), "nearby toggle removes it")
	check(Game.state.map_pins.is_empty(), "pin not removed")
	for i in map.max_pins + 3:
		Game.toggle_pin("MarketRun", Vector2(i * 200, 0))
	check(Game.state.map_pins.size() == map.max_pins, "pins must be capped")


func test_conditions() -> void:
	check(Game.check_condition(""), "empty is true")
	check(not Game.check_condition("flag:x") and Game.check_condition("!flag:x"), "flag / negation")
	Game.set_flag("x")
	check(Game.check_condition("flag:x"), "flag set")
	check(not Game.check_condition("ability:dash"), "no dash yet")
	Game.set_ability(&"dash", true)
	check(Game.check_condition("ability:dash"), "dash owned")
	Game.mark_collected("cs_market")
	check(Game.check_condition("collected:cs_market"), "collected id")


func test_anchor_network_and_save_roundtrip() -> void:
	Game.state.map_explored.clear()
	Game.rest_at_anchor("res://world/rooms/lowlight/Relay.tscn", "relay")
	Game.rest_at_anchor("res://world/rooms/lowlight/BellTower.tscn", "bell_top")
	Game.rest_at_anchor("res://world/rooms/lowlight/Relay.tscn", "relay")
	check(Game.state.anchors_rested.size() == 2, "anchors rested should be unique")
	check(Game.transit_destinations("res://world/rooms/lowlight/Relay.tscn", "relay").size() == 1, "destinations exclude here")
	MapProgress.reveal(Game.state, map, "res://world/rooms/lowlight/MarketRun.tscn", Vector2(500, -50))
	Game.toggle_pin("MarketRun", Vector2(500, -50))
	var json := JSON.stringify(SaveManager.migrate(Game.state.to_dict().merged({"schema_version": SaveManager.CURRENT_SCHEMA_VERSION})))
	var back := GameState.from_dict(JSON.parse_string(json))
	check(MapProgress.explored_count(back, "MarketRun") == MapProgress.explored_count(Game.state, "MarketRun") and MapProgress.explored_count(back, "MarketRun") > 0, "explored cells lost through JSON")
	check(back.map_pins.size() == 1 and back.anchors_rested.size() == 2, "pins / anchors lost")


func test_migrates_v2_save_to_v3() -> void:
	var v2 := GameState.new().to_dict()
	for k in ["map_explored", "map_pins", "anchors_rested"]:
		v2.erase(k)
	v2["schema_version"] = 2
	v2["last_anchor_room"] = "res://world/rooms/lowlight/ApartmentStack.tscn"
	v2["last_anchor_id"] = "stack_mid"
	v2["visited_rooms"] = ["res://world/rooms/lowlight/Relay.tscn"]
	var migrated := SaveManager.migrate(v2)
	check(int(migrated["schema_version"]) == 3, "not migrated to v3")
	var s := GameState.from_dict(migrated)
	check(s.anchors_rested == ["res://world/rooms/lowlight/ApartmentStack.tscn|stack_mid"], "respawn Anchor should join the transit network")
	check(MapProgress.knows_outline(s, map.room("Relay")) and not MapProgress.knows_outline(s, map.room("MarketRun")), "outlines come from visited rooms")


func test_map_menu_opens_draws_and_pins() -> void:
	var root := Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	SceneRouter.goto_room("res://world/rooms/lowlight/Relay.tscn", &"start")
	await physics_frames(8)
	check(MapProgress.explored_count(Game.state, "Relay") > 0, "entering a room should reveal around Rook")
	var menu: MenuScreen = load("res://ui/menus/MapMenu.gd").new()
	add_child(menu)
	menu.open_menu()
	await get_tree().process_frame
	var view: MapView = menu.view
	check(view != null and view.current_room == "Relay", "map should centre on the current room")
	check(view.room_at(view.cursor) != null, "cursor starts inside the current room")
	check(view.hover_text().contains("Relay"), "hover names the room: %s" % view.hover_text())
	check(view.toggle_pin_at_cursor() and Game.state.map_pins.size() == 1, "pin placed at the cursor")
	view.cursor = Vector2(-99999, -99999)
	check(not view.toggle_pin_at_cursor(), "no pins outside known rooms")
	check(MapMenu_completion().contains("The Relay"), "completion stats missing")
	view.queue_redraw()
	await get_tree().process_frame
	menu.close_menu()
	check(not get_tree().paused, "map should unpause on close")
	menu.queue_free()
	SceneRouter.current_room = null
	SceneRouter.world_root = null
	root.queue_free()
	await physics_frames(2)


func MapMenu_completion() -> String:
	return load("res://ui/menus/MapMenu.gd").completion_text()


func test_unknown_rooms_stay_hidden_until_base_map() -> void:
	var view := MapView.new()
	view.setup(map, Game.state, "Relay", Vector2.ZERO)
	check(view.room_at(map.room("MarketRun").offset + Vector2(100, -50)) == null, "unvisited room must be hidden")
	Game.set_flag("map_lowlight")
	check(view.room_at(map.room("MarketRun").offset + Vector2(100, -50)) != null, "base map reveals outlines")
	view.free()
