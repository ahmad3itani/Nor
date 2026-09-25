extends RedlineTestCase
## M8 foundation (T01): the Subtitles & scenes settings page, SkipGate (the one
## advance/skip rule for sequences, memory vignettes and endings),
## CinematicMode, SubtitleStyle/DialogueBox geometry and the HUD hint hold.
## Every test restores what it changes (settings, CinematicMode, pause).

const TEMP_SETTINGS := "user://test_m8_settings.cfg"

var _snap: Dictionary = {}


func before_each() -> void:
	_snap = use_default_m8_settings()
	# SettingsMenu.close_menu always saves: point it at a temp file.
	Settings.load_settings(TEMP_SETTINGS)


func after_each() -> void:
	Settings.load_settings(Settings.SETTINGS_PATH)
	DirAccess.remove_absolute(TEMP_SETTINGS)
	restore_m8_settings(_snap)
	get_tree().paused = false


func _button(menu: MenuScreen, prefix: String) -> Button:
	for n in menu._body.get_children():
		if n is Button and (n as Button).text.begins_with(prefix):
			return n
	return null


func test_settings_menu_fits_viewport() -> void:
	var menu: MenuScreen = load("res://ui/menus/SettingsMenu.gd").new()
	add_child(menu)
	menu.open_menu()
	var h_main: float = await menu_height(menu)
	check(h_main <= 270.0, "settings main page is %.0f px tall (> 270)" % h_main)
	check(h_main > 100.0, "panel height not measured (%.0f px)" % h_main)
	print("  settings main page %.0f px" % h_main)
	var sub := _button(menu, "Subtitles & scenes")
	check(sub != null, "main page has no 'Subtitles & scenes…' row")
	if sub == null:
		menu.close_menu()
		menu.queue_free()
		return
	sub.pressed.emit()
	check(menu.page == &"subtitles", "row did not open the sub-page")
	check(_button(menu, "Subtitle size: Small") != null, "sub-page lacks the size row")
	for prefix in ["Subtitle background: Box", "Speaker names: On", "Subtitle speed: Normal", "Skip scenes: Hold", "Memories play at Anchors: On", "Back"]:
		check(_button(menu, prefix) != null, "sub-page lacks row '%s'" % prefix)
	var h_sub: float = await menu_height(menu)
	check(h_sub <= 270.0, "subtitles page is %.0f px tall (> 270)" % h_sub)
	print("  subtitles page %.0f px" % h_sub)
	# Rows cycle their setting.
	_button(menu, "Subtitle size").pressed.emit()
	check(Settings.subtitle_size == 1, "size row did not cycle")
	_button(menu, "Subtitle size").pressed.emit()
	_button(menu, "Subtitle size").pressed.emit()
	check(Settings.subtitle_size == 0, "size row did not wrap")
	# Back returns to main and focuses the row that opened the page.
	_button(menu, "Back").pressed.emit()
	check(menu.page == &"main" and menu.is_open(), "Back did not return to the main page")
	await get_tree().process_frame
	var focused := menu.get_viewport().gui_get_focus_owner() as Button
	check(focused != null and focused.text.begins_with("Subtitles & scenes"), "Back did not focus the Subtitles row")
	# Cancel on the sub-page goes back instead of closing.
	_button(menu, "Subtitles & scenes").pressed.emit()
	await press_action(&"ui_cancel", 2)
	await get_tree().process_frame
	check(menu.is_open(), "ui_cancel on the sub-page closed the menu")
	check(menu.page == &"main", "ui_cancel on the sub-page did not return to main")
	menu.close_menu()
	check(not get_tree().paused, "menu did not unpause")
	menu.open_menu()
	check(menu.page == &"main", "open_menu must reset to the main page")
	menu.close_menu()
	menu.queue_free()
