extends MenuScreen
## The New Game+ screen (M9 D3 §2.7, D-153), menu id ng_plus, opened from the
## title's "New Game+" row (ctx {"from": "title"}). Two steps on one screen:
## what carries and what resets with the two options, then a confirm that
## says plainly the Continue save is replaced (the archive copy cannot be
## loaded from the game, R09.5). A refusal keeps this screen open with a
## neutral line; Back (or ui_cancel) returns to the title.
## Height: both steps fit the 270 px canvas at 100 % UI (test_ng_plus).

## Every line is a Loc literal with named placeholders; no data text.
const LOC_FIELDS := {}
const LOC_EXEMPT := []

var _from: String = ""
var _remix: bool = true
var _keep_dash: bool = true
var _confirm: bool = false
var _refused: bool = false


func open_menu() -> void:
	_from = String(ctx.get("from", ""))
	_remix = true
	_keep_dash = true
	_confirm = false
	_refused = false
	super.open_menu()
	focus_index(0)


func _process(delta: float) -> void:
	# ui_cancel in the confirm step goes back one step, not to the title.
	if visible and _confirm and Engine.get_process_frames() != _opened_frame and cancel_pressed():
		_back_to_options()
		return
	super._process(delta)


func rebuild() -> void:
	clear_body()
	var next := NewGamePlus.cycle_of(SaveManager.load_profile(1)) + 1
	add_label(Loc.t("NEW GAME+") + "  " + NewGamePlus.cycle_label(next), UiTheme.ACCENT, UiTheme.FONT_SIZE + 2)
	if _confirm:
		_confirm_step()
	else:
		_options_step()


func _options_step() -> void:
	if _refused:
		add_label(Loc.t("New Game+ is not available for this save."), UiTheme.MUTED)
	add_label(Loc.t("Keeps: your weapons, Circuits, banked Scrap and upgrades. Core Shards you found stay found."))
	add_label(Loc.t("Resets: the story, people, map and memories. Secret stashes refill with a quarter of their Scrap."))
	add_option_row(_remix_text(), _toggle_remix, _toggle_remix, _toggle_remix)
	add_option_row(_dash_text(), _toggle_dash, _toggle_dash, _toggle_dash)
	add_label(Loc.t("Your cleared save is copied to an archive file; the game cannot load it back."), UiTheme.MUTED)
	add_button(Loc.t("Begin"), func() -> void:
		_confirm = true
		_opened_frame = Engine.get_process_frames()
		rebuild()
		focus_index(0))
	add_button(Loc.t("Back"), close_menu)


func _confirm_step() -> void:
	add_label(Loc.t("Replace your Continue save with New Game+?"))
	add_label(Loc.t("Memories and quests you have not finished start over."), UiTheme.MUTED)
	add_button(Loc.t("Begin New Game+"), _begin)
	add_button(Loc.t("Back"), _back_to_options)


func _remix_text() -> String:
	return Loc.f("Remixed enemies and hazards: {state}", {"state": _on_off(_remix)})


func _dash_text() -> String:
	return Loc.f("Start with the Dash: {state}", {"state": _on_off(_keep_dash)})


func _on_off(on: bool) -> String:
	return Loc.t("On") if on else Loc.t("Off")


## Option rows: confirm, left and right all flip the value (two states), and
## focus stays on the row.
func _toggle_remix() -> void:
	_remix = not _remix
	var at := focused_index()
	rebuild()
	focus_index(at)


func _toggle_dash() -> void:
	_keep_dash = not _keep_dash
	var at := focused_index()
	rebuild()
	focus_index(at)


func _back_to_options() -> void:
	_confirm = false
	_opened_frame = Engine.get_process_frames()
	rebuild()
	# Focus the Begin row the player came from.
	focus_index(2)


func _begin() -> void:
	var ok := NewGamePlus.begin({"from": _from, "remix": _remix, "keep_dash": _keep_dash})
	if not ok:
		_refused = true
		_back_to_options()
		focus_index(3)
		return
	close_menu()
	var host := get_parent() as MenuHost
	if host != null and host.title != null:
		host.title.close_menu()
