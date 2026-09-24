extends MenuScreen
## Map screen (bible §20): the MapView plus what the cursor is over, the
## controls, and per-district completion. Opens with the map button (M / View)
## or from the pause menu; closes with the same button or back.

var view: MapView
var _hover: Label


func open_menu() -> void:
	super.open_menu()
	EventBus.map_opened.emit()


func rebuild() -> void:
	clear_body()
	_panel.custom_minimum_size = Vector2(456, 0)
	add_label("MAP", UiTheme.ACCENT, UiTheme.FONT_SIZE + 2)
	view = MapView.new()
	view.custom_minimum_size = Vector2(440, 176)
	view.clip_contents = true
	_body.add_child(view)
	var room := SceneRouter.current_room as Room
	var room_id := SceneRouter.current_room_path.get_file().get_basename()
	var pos := room.player.position if room and is_instance_valid(room.player) else Vector2.ZERO
	view.setup(Game.world_map, Game.state, room_id, pos)
	_hover = add_label("", UiTheme.TEXT, UiTheme.FONT_SIZE - 1)
	view.hover_changed.connect(func(t: String) -> void: _hover.text = t)
	add_label("%s move   [%s]/[%s] zoom   [%s] pin   [%s] close" % [
		"Stick / D-pad" if InputGlyphs.using_pad else "Arrows / WASD", InputGlyphs.label(&"ranged"), InputGlyphs.label(&"grapple"),
		InputGlyphs.label(&"jump"), InputGlyphs.label(&"map")], UiTheme.MUTED, UiTheme.FONT_SIZE - 1)
	add_label(completion_text(), UiTheme.MUTED, UiTheme.FONT_SIZE - 1)


## Bible §20 "district completion statistics": explored share, rooms visited,
## secrets found; shown per district the player has set foot in.
static func completion_text() -> String:
	var parts: PackedStringArray = []
	var map := Game.world_map
	for d in map.districts():
		var rooms := map.rooms_in(d)
		var visited := 0
		var secrets := 0
		var found := 0
		for r in rooms:
			if Game.state.visited_rooms.has(r.room_path):
				visited += 1
			for s: Dictionary in WorldMapIndex.room_info(r.room_path)["secrets"]:
				secrets += 1
				if Game.is_collected(s["id"]):
					found += 1
		if visited == 0:
			continue
		var line := "%s: explored %d%%, rooms %d/%d" % [map.district_names.get(d, d), roundi(100.0 * MapProgress.district_ratio(Game.state, map, d)), visited, rooms.size()]
		if secrets > 0:
			line += ", secrets %d/%d" % [found, secrets]
		parts.append(line)
	return "   ·   ".join(parts)


func _process(delta: float) -> void:
	super._process(delta)
	if visible and Engine.get_process_frames() != _opened_frame and Input.is_action_just_pressed("map"):
		close_menu()
