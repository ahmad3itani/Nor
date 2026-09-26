extends MenuScreen
## The demo end card (M9 D6 §2.5, D-165), opened by MenuHost on
## demo_boundary_reached (or instead of the Act I card in an ACT_CLOSE demo).
## Every line comes from DemoConfig data through Loc. Like the Act I card it
## shows time, secrets and fragments, never deaths (§24: nothing shames).
## "Keep exploring" has focus and ui_cancel does the same, so the default
## action never leaves the game: the player walks away and the card opens
## again only when they walk back into the border.
## Height: fits the 270 px canvas at 100 % UI (test_demo_flow).

signal quit_to_title

## No text fields of its own: the card's lines are DemoConfig data (its
## LOC_FIELDS) and two Loc.f literals with named placeholders.
const LOC_FIELDS := {}
const LOC_EXEMPT := []


func open_menu() -> void:
	# First open only (the flag marks a profile that saw the demo's end).
	if not Game.has_flag("demo_end_seen"):
		Game.set_flag("demo_end_seen")
	super.open_menu()


func rebuild() -> void:
	clear_body()
	var c := BuildInfo.config()
	if c == null:
		add_button(Loc.t("Keep exploring"), close_menu)
		focus_index(0)
		return
	add_label(Loc.t(c.end_header), UiTheme.ACCENT, UiTheme.FONT_SIZE + 2)
	for line in c.end_lines:
		add_label(Loc.t(line))
	add_label(Loc.f("Time {time}", {"time": SliceStats.format_time(Game.state.play_time_sec)}))
	var t := SliceStats.totals()
	var total := (t["secret_ids"] as Array).size()
	var found := SliceStats.secrets_found()
	add_label(Loc.f("Secrets {found} / {total}    Memory fragments {frags} / {frag_total}", {
		"found": found, "total": total, "frags": Game.state.memory_fragments.size(), "frag_total": t["fragments"]}))
	if found < total and c.secrets_note != "":
		add_label(Loc.t(c.secrets_note), UiTheme.MUTED)
	for line in c.cta_lines:
		add_label(Loc.t(line), UiTheme.MUTED)
	add_button(Loc.t(c.keep_label), close_menu)
	add_button(Loc.t(c.quit_label), _save_and_quit)
	focus_index(0)


## Same path as Pause's Save & Quit: stop any scene, capture, save, then
## MenuHost forwards quit_to_title to Main.
func _save_and_quit() -> void:
	PauseMenu.save_and_quit_state()
	close_menu()
	quit_to_title.emit()
