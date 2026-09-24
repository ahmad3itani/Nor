extends MenuScreen
## Title screen: Continue (last Anchor), New Game, the labs, settings, quit.
## Controller-first; no pause (nothing runs underneath).

signal lab_requested(path: String)

const RELAY_START_LABEL := "Slice (Relay start)"
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
	add_label(Game.onboarding.title_subtitle, UiTheme.MUTED)
	# Be upfront about recording (M4): what, where, and how to turn it off.
	if Playtest.recording_allowed():
		add_label("Playtest recording ON: your run is saved to a local file only (%s). Turn off in Settings." % ProjectSettings.globalize_path(Playtest.dir), UiTheme.MUTED, UiTheme.FONT_SIZE - 1)
	if Game.has_save():
		add_button("Continue", _continue)
	add_button("New Game", _new_game)
	# Debug builds only (D-059): the pre-campaign slice start, kept for the
	# pending M4 playtest (D-068) and quick checks of the Lowlight slice.
	if OS.is_debug_build():
		add_button(RELAY_START_LABEL, _new_relay_game)
	for lab: String in LABS:
		add_button(lab, lab_requested.emit.bind(LABS[lab]))
	add_button("Settings", func() -> void: EventBus.menu_requested.emit(&"settings"))
	add_button("Quit", func() -> void: get_tree().quit())


func _continue() -> void:
	if Game.load_game():
		Playtest.begin_session("continue")
		close_menu()
		SceneRouter.transition_to(Game.respawn_room(), Game.respawn_entry())


## The campaign (bible §42): unarmed in the Undercity once onboarding is
## enforced, otherwise the legacy slice start. The "new" session kind is what
## the playtest analyzer's Undercity timeline counts.
func _new_game() -> void:
	Game.start_campaign()
	Playtest.begin_session("new")
	close_menu()
	SceneRouter.transition_to(Game.campaign_start_room(), Game.campaign_start_entry())


## Legacy slice start (full kit, Relay). Its own session kind, so it never
## pollutes the Undercity timeline.
func _new_relay_game() -> void:
	Game.new_game()
	Playtest.begin_session("new_relay")
	close_menu()
	SceneRouter.transition_to(Game.START_ROOM, Game.START_ENTRY)
