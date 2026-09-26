extends MenuScreen
## Title screen: Continue (last Anchor), New Game, the M9 endgame entries,
## settings, quit; the labs and debug starts sit behind one sub-page.
## Controller-first; no pause (nothing runs underneath).
##
## M9 layout (D-168), top to bottom: wordmark, tagline, subtitle, recording
## notice; the first-run "Comfort & accessibility" row (never focused first);
## Continue, New Game, New Game+, Challenges, Achievements, Settings, the
## "Labs & dev starts…" page (debug builds), Quit (not on the web); build label.
## Rows whose feature a build disables or whose screen has not landed are
## simply absent.

signal lab_requested(path: String)

const RELAY_START_LABEL := "Slice (Relay start)"
const LABS := {"Combat Lab": "res://world/rooms/CombatLab.tscn", "Movement Lab": "res://world/rooms/MovementLab.tscn"}

## Row focused before another screen opened; MenuHost refocuses it on close.
var last_focus: int = 0
## &"main" or &"labs".
var _page: StringName = &"main"
## Row to focus after a rebuild of the main page (Continue, else New Game).
var _default_focus: int = 0


func open_menu() -> void:
	visible = true
	_opened_frame = Engine.get_process_frames()
	_page = &"main"
	rebuild()
	focus_index(_default_focus)


func close_menu() -> void:
	visible = false
	closed.emit()


## ui_cancel does nothing on the main page; on the labs page it goes back.
func _process(_delta: float) -> void:
	if visible and _page == &"labs" and Engine.get_process_frames() != _opened_frame and cancel_pressed():
		_show_page(&"main")


func rebuild() -> void:
	clear_body()
	if _page == &"labs":
		_labs_page()
	else:
		_main_page()


func _main_page() -> void:
	var tag := BuildInfo.title_tag()
	# l10n: ignore(brand)
	add_label("R E D L I N E" + ("  " + tag if tag != "" else ""), UiTheme.ACCENT, 16)
	add_label("Movement is life. Violence buys time. Curiosity reveals the truth.", UiTheme.MUTED)
	add_label(BuildInfo.title_subtitle(), UiTheme.MUTED)
	# Be upfront about recording (M4): what, where, and how to turn it off.
	if Playtest.recording_allowed():
		add_label("Playtest recording ON: your run is saved to a local file only (%s). Turn off in Settings." % ProjectSettings.globalize_path(Playtest.dir), UiTheme.MUTED, UiTheme.FONT_SIZE - 1)
	var data := SaveManager.load_profile(1)
	var rows := 0
	_default_focus = -1
	if Settings.first_run:
		add_button(Loc.t("Comfort & accessibility"), _act.bind(func() -> void:
			_open_screen(&"settings", {"page": &"quick"})))
		rows += 1
	if not data.is_empty():
		var cycle := NewGamePlus.cycle_of(data)
		var label := Loc.t("Continue") if cycle < 1 else Loc.f("Continue ({cycle})", {"cycle": NewGamePlus.cycle_label(cycle)})
		var allowed := BuildInfo.room_allowed(Game.respawn_room_for(GameState.from_dict(data)))
		add_button(label, _act.bind(_continue), Callable(), allowed)
		if allowed:
			_default_focus = rows
		else:
			add_label(Loc.t("This save is from the full game."), UiTheme.MUTED)
		rows += 1
	add_button(Loc.t("New Game"), _act.bind(_new_game))
	if _default_focus < 0:
		_default_focus = rows
	rows += 1
	if BuildInfo.enabled(&"ngplus") and _host_has(&"ng_plus") and NewGamePlus.can_begin(data):
		add_button(Loc.t("New Game+"), _act.bind(func() -> void: _open_screen(&"ng_plus", {"from": "title"})))
	if not data.is_empty() and BuildInfo.enabled(&"challenges") and _host_has(&"challenges") and Challenges.any_unlocked_for(data):
		add_button(Loc.t("Challenges"), _act.bind(func() -> void:
			last_focus = focused_index()
			Challenges.open_from_title()))
	if _host_has(&"achievements"):
		add_button(Loc.t("Achievements"), _act.bind(func() -> void: _open_screen(&"achievements", {"from": "title"})))
	add_button(Loc.t("Settings"), _act.bind(func() -> void: _open_screen(&"settings", {})))
	if OS.is_debug_build() and (BuildInfo.enabled(&"labs") or BuildInfo.enabled(&"relay_start")):
		add_button(Loc.t("Labs & dev starts…"), func() -> void: _show_page(&"labs"))
	if BuildInfo.can_quit():
		add_button(Loc.t("Quit"), func() -> void: get_tree().quit())
	add_label(BuildInfo.label(), UiTheme.MUTED, UiTheme.FONT_SIZE - 1)


## Debug builds only (D-059): the pre-campaign slice start, kept for the
## pending M4 playtest (D-068) and quick checks of the Lowlight slice, and the
## movement and combat labs.
func _labs_page() -> void:
	add_label(Loc.t("LABS & DEV STARTS"), UiTheme.ACCENT, UiTheme.FONT_SIZE + 2)
	if BuildInfo.enabled(&"relay_start"):
		add_button(RELAY_START_LABEL, _new_relay_game)
	if BuildInfo.enabled(&"labs"):
		for lab: String in LABS:
			add_button(lab, lab_requested.emit.bind(LABS[lab]))
	add_button(Loc.t("Back"), func() -> void: _show_page(&"main"))


func _show_page(p: StringName) -> void:
	var back_to_labs_row := _page == &"labs"
	_page = p
	_opened_frame = Engine.get_process_frames()
	rebuild()
	if p == &"main" and back_to_labs_row:
		focus_index(_labs_row_index())
	else:
		focus_index(0 if p == &"labs" else _default_focus)


## Index of the "Labs & dev starts…" row among the main page's buttons.
func _labs_row_index() -> int:
	var buttons := _body.get_children().filter(func(n: Node) -> bool: return n is Button)
	for i in buttons.size():
		if (buttons[i] as Button).text == Loc.t("Labs & dev starts…"):
			return i
	return _default_focus


## Every title action first retires the first-run row (D-168): it shows once.
func _act(action: Callable) -> void:
	if Settings.first_run:
		Settings.first_run = false
		# Only the real settings file: tests and tours use their own paths.
		if Settings._path == Settings.SETTINGS_PATH:
			Settings.save_settings()
	action.call()


## Opens another screen over the title through the host (no-op without one:
## tests add a bare TitleMenu).
func _open_screen(id: StringName, ctx: Dictionary) -> void:
	last_focus = focused_index()
	var host := get_parent()
	if host != null and host.has_method("open_with"):
		host.call("open_with", id, ctx)
	else:
		EventBus.menu_requested.emit(id)


func _host_has(id: StringName) -> bool:
	return get_parent() != null and get_parent().has_method("has_screen") and get_parent().call("has_screen", id)


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
