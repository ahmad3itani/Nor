class_name PauseMenu
extends MenuScreen
## Pause (bible §27): resume, journal, settings, save & quit to title. During
## a scripted sequence it also offers "Skip scene" (§24, no hold needed).
## M9: inside a challenge run the run rows replace the normal ones (restart,
## ghost mode, quit the run); the header shows the NG+ cycle.

signal quit_to_title


func rebuild() -> void:
	clear_body()
	var header := Loc.t("PAUSED")
	var cycle := NewGamePlus.cycle()
	if cycle >= 1:
		header += "  ·  " + NewGamePlus.cycle_label(cycle)
	add_label(header, UiTheme.ACCENT, UiTheme.FONT_SIZE + 2)
	if Challenges.active():
		_run_rows()
		return
	var room := SceneRouter.current_room as Room
	if room:
		add_label("%s  —  %s" % [room.district_name, room.room_name], UiTheme.MUTED)
	add_button("Resume", close_menu)
	if Cinematics.can_skip():
		add_button("Skip scene", _skip_scene)
	if room and room.world_room:
		# Same rule as MenuHost.can_open: a locking scene keeps the map shut.
		if not Cinematics.locks_input():
			add_button("Map", _open.bind(&"map"))
		add_button("Journal", _open.bind(&"journal"))
	if Playtest.is_recording():
		add_button("Report a moment (playtest)", _open.bind(&"moment"))
		if (Playtest.session.data["survey"] as Dictionary).is_empty():
			add_button("Playtest survey", _open.bind(&"survey"))
	add_button("Settings", _open.bind(&"settings"))
	add_button("Save & Quit to Title", _quit)


## A challenge run: no Map, Journal or Save & Quit (the profile is held
## untouched while the run owns a sandbox, D-147).
func _run_rows() -> void:
	add_label(Challenges.current_title(), UiTheme.MUTED)
	add_button(Loc.t("Resume"), close_menu)
	add_button(Loc.t("Restart"), func() -> void:
		close_menu()
		Challenges.restart(&"menu"))
	if Challenges.has_stages():
		add_button(Loc.t("Restart descent"), func() -> void:
			close_menu()
			Challenges.restart_run())
	add_button(Loc.f("Ghost: {mode}", {"mode": Challenges.ghost_mode_label()}), func() -> void:
		var i := focused_index()
		Challenges.cycle_ghost_mode()
		rebuild()
		focus_index(i))
	add_button(Loc.t("Settings"), _open.bind(&"settings"))
	add_button(Loc.t("Quit challenge"), func() -> void:
		close_menu()
		Challenges.quit())


func _open(menu: StringName) -> void:
	close_menu()
	EventBus.menu_requested.emit(menu)


## Close first (unpauses), then request: the skip runs on the sequence's next
## unpaused frame, so play() never resolves while this menu is still open.
func _skip_scene() -> void:
	close_menu()
	Cinematics.request_skip()


func _quit() -> void:
	save_and_quit_state()
	close_menu()
	quit_to_title.emit()


## Everything Save & Quit does before leaving (DemoEndMenu reuses it).
## Stop any scene before the save: an aborted scene runs none of its
## remaining effects and replays on Continue; left running, it could end
## during the title fade and open a menu over it.
static func save_and_quit_state() -> void:
	CinematicMode.abort_all()
	var room := SceneRouter.current_room as Room
	if room and room.world_room and is_instance_valid(room.player):
		Game.capture_from_player(room.player)
		Game.save_game()
