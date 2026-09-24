extends MenuScreen
## Pause (bible §27): resume, journal, settings, save & quit to title.

signal quit_to_title


func rebuild() -> void:
	clear_body()
	add_label("PAUSED", UiTheme.ACCENT, UiTheme.FONT_SIZE + 2)
	var room := SceneRouter.current_room as Room
	if room:
		add_label("%s  —  %s" % [room.district_name, room.room_name], UiTheme.MUTED)
	add_button("Resume", close_menu)
	if room and room.world_room:
		add_button("Map", _open.bind(&"map"))
		add_button("Journal", _open.bind(&"journal"))
	if Playtest.is_recording():
		add_button("Report a moment (playtest)", _open.bind(&"moment"))
		if (Playtest.session.data["survey"] as Dictionary).is_empty():
			add_button("Playtest survey", _open.bind(&"survey"))
	add_button("Settings", _open.bind(&"settings"))
	add_button("Save & Quit to Title", _quit)


func _open(menu: StringName) -> void:
	close_menu()
	EventBus.menu_requested.emit(menu)


func _quit() -> void:
	var room := SceneRouter.current_room as Room
	if room and room.world_room and is_instance_valid(room.player):
		Game.capture_from_player(room.player)
		Game.save_game()
	close_menu()
	quit_to_title.emit()
