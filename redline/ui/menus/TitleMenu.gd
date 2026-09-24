extends MenuScreen
## Title screen: Continue (last Anchor), New Game, the labs, settings, quit.
## Controller-first; no pause (nothing runs underneath).

signal lab_requested(path: String)

const LABS := {"Combat Lab": "res://world/rooms/CombatLab.tscn", "Movement Lab": "res://world/rooms/MovementLab.tscn"}


func open_menu() -> void:
	visible = true
	_opened_frame = Engine.get_process_frames()
	rebuild()
	focus_index(0)


func close_menu() -> void:
	visible = false
	closed.emit()


func _process(_delta: float) -> void:
	pass  # ui_cancel does nothing on the title screen.


func rebuild() -> void:
	clear_body()
	add_label("R E D L I N E", UiTheme.ACCENT, 16)
	add_label("Movement is life. Violence buys time. Curiosity reveals the truth.", UiTheme.MUTED)
	add_label("vertical slice  —  Lowlight", UiTheme.MUTED)
	if Game.has_save():
		add_button("Continue", _continue)
	add_button("New Game", _new_game)
	for lab: String in LABS:
		add_button(lab, lab_requested.emit.bind(LABS[lab]))
	add_button("Settings", func() -> void: EventBus.menu_requested.emit(&"settings"))
	add_button("Quit", func() -> void: get_tree().quit())


func _continue() -> void:
	if Game.load_game():
		close_menu()
		SceneRouter.transition_to(Game.respawn_room(), Game.respawn_entry())


func _new_game() -> void:
	Game.new_game()
	close_menu()
	SceneRouter.transition_to(Game.START_ROOM, Game.START_ENTRY)
