extends RedlineTestCase
## M9 T11 (D4 §8.7, D-159, R11.1, R11.6, R11.9): pause over a conversation
## (Orr's choice included), the paused state kept on close, the box ignoring
## input under a menu, Save & Quit over a conversation reaching the title,
## the DialogueBox class name, and text auto-advance.

const MARKET := "res://world/rooms/lowlight/MarketRun.tscn"
const TITLE_ROOM := "res://world/rooms/TitleBackdrop.tscn"
const TMP_CFG := "user://test_dialogue_pause.cfg"
const SAVE_DIR := "user://test_dialogue_pause_saves"

var root: Node2D
var _main: Node
var _extras: Array[Node] = []
var _snap: Dictionary = {}


func before_each() -> void:
	_snap = snapshot_settings()
	Settings.remove_settings_files(TMP_CFG)
	Settings._path = TMP_CFG
	Settings.apply_defaults()
	SaveManager.save_dir = SAVE_DIR
	get_tree().paused = false
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	Game.new_game()


func after_each() -> void:
	for n in _extras:
		if is_instance_valid(n):
			n.queue_free()
	_extras.clear()
	_main = null
	await get_tree().process_frame
	get_tree().paused = false
	SceneRouter.current_room = null
	SceneRouter.current_room_path = ""
	SceneRouter.world_root = null
	SceneRouter._fade = null
	if is_instance_valid(root):
		root.queue_free()
	SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR
	AtomicJson.remove_tree(SAVE_DIR)
	Settings.remove_settings_files(TMP_CFG)
	restore_settings(_snap)
	Game.new_game()
	await physics_frames(2)


func _boot_main(start_room: String) -> MenuHost:
	_main = (load("res://Main.tscn") as PackedScene).instantiate()
	_main.set("start_room", start_room)
	add_child(_main)
	_extras.append(_main)
	await physics_frames(4)
	return _main.get_node("Menus") as MenuHost


func _box() -> DialogueBox:
	return _main.get_node("DialogueBox") as DialogueBox


static func _line(text: String) -> DialogueLine:
	var l := DialogueLine.new()
	l.text = text
	l.speaker = "Test"
	return l


static func _talk(n_lines := 3, flag := "test_talk_done") -> DialogueData:
	var d := DialogueData.new()
	d.id = "test_talk"
	for i in n_lines:
		d.lines.append(_line("Line number %d of the test conversation." % i))
	if flag != "":
		d.set_flags = PackedStringArray([flag])
	return d


static func _choice_talk() -> DialogueData:
	var d := _talk(1, "")
	d.id = "test_choice"
	for id in ["a", "b"]:
		var c := DialogueChoice.new()
		c.id = id
		c.label = "Answer %s" % id
		c.set_flags = PackedStringArray(["test_choice_%s" % id])
		d.choices.append(c)
	return d


func _labels(menu: MenuScreen) -> Array:
	var out: Array = []
	for c in menu._body.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append((c as Button).text)
	return out


func _wait_idle(max_frames := 240) -> void:
	await get_tree().process_frame
	for i in max_frames:
		if not SceneRouter.transitioning:
			break
		await get_tree().process_frame
	await physics_frames(3)


# --- Tests ---------------------------------------------------------------------

func test_dialogue_box_class_name_loads() -> void:
	var script := load("res://ui/dialogue/DialogueBox.gd") as GDScript
	check(script != null and script.get_global_name() == &"DialogueBox", "DialogueBox.gd declares class_name DialogueBox")
	var box := DialogueBox.new()
	check(box is CanvasLayer, "a DialogueBox is a CanvasLayer")
	box.free()


func test_pause_opens_over_dialogue() -> void:
	var host := await _boot_main(MARKET)
	var box := _box()
	box.open(_talk())
	await get_tree().process_frame
	check(box.is_open() and get_tree().paused, "the box pauses the world")
	check(DialogueBox.open_instance == box, "open_instance names the open box")
	await press_action(&"pause", 1)
	await get_tree().process_frame
	var pause := host.screen(&"pause")
	check(pause.is_open(), "pause opens over the conversation (§24)")
	check(box.is_open() and get_tree().paused, "the conversation waits underneath")


func test_close_restores_paused_true() -> void:
	var host := await _boot_main(MARKET)
	var box := _box()
	box.open(_talk())
	await get_tree().process_frame
	await press_action(&"pause", 1)
	await get_tree().process_frame
	var pause := host.screen(&"pause")
	pause.close_menu()
	check(not pause.is_open(), "closed")
	check(get_tree().paused, "closing the menu keeps the conversation's pause (D-159)")
	check(box.is_open(), "the conversation is still on screen")


func test_dialogue_ignores_input_while_menu_open() -> void:
	var host := await _boot_main(MARKET)
	var box := _box()
	box.open(_talk())
	await physics_frames(2)
	await press_action(&"pause", 1)
	await get_tree().process_frame
	check(host.screen(&"pause").is_open(), "pause is open")
	var line := box.line_index
	var shown := box.shown_chars
	for a: StringName in [&"jump", &"interact", &"attack_light"]:
		await press_action(a, 1)
		await get_tree().process_frame
	check(box.line_index == line and box.shown_chars == shown, "no press reaches the box under a menu")
	check(box.is_open(), "the conversation stays open")


func test_menu_hop_still_unpauses() -> void:
	var host := await _boot_main(MARKET)
	var pause := host.screen(&"pause") as PauseMenu
	check(host.open(&"pause"), "pause opens in play")
	pause._open(&"settings")
	var settings := host.screen(&"settings")
	check(settings.is_open() and get_tree().paused, "settings over the world")
	settings.close_menu()
	check(not get_tree().paused, "pause -> settings -> close ends unpaused")
	# The same hop over a conversation stays paused.
	var box := _box()
	box.open(_talk())
	await get_tree().process_frame
	check(host.open(&"pause"), "pause opens over the box")
	pause._open(&"settings")
	settings.close_menu()
	check(get_tree().paused and box.is_open(), "over a conversation the hop keeps the pause")


func test_pause_over_orr_choice() -> void:
	var host := await _boot_main(MARKET)
	var box := _box()
	box.open(_choice_talk())
	await get_tree().process_frame
	box.shown_chars = 999.0
	box.advance()
	check(box.is_choosing(), "the options are up")
	await press_action(&"pause", 1)
	await get_tree().process_frame
	var pause := host.screen(&"pause")
	check(pause.is_open(), "pause opens over a choice too")
	box._choice_shown_ms -= 5000
	await press_action(&"jump", 1)
	await press_action(&"ui_accept", 1)
	check(box.is_choosing() and not Game.has_flag("test_choice_a"), "no answer is picked under the menu")
	pause.close_menu()
	check(get_tree().paused and box.is_choosing(), "back to the same choice, still paused")


func test_pause_rows_hide_map_journal_in_dialogue() -> void:
	var host := await _boot_main(MARKET)
	var pause := host.screen(&"pause") as PauseMenu
	host.open(&"pause")
	var rows := _labels(pause)
	check(rows.has("Map") and rows.has("Journal"), "in play the pause menu has Map and Journal: %s" % [rows])
	pause.close_menu()
	var box := _box()
	box.open(_talk())
	await get_tree().process_frame
	host.open(&"pause")
	rows = _labels(pause)
	check(not rows.has("Map") and not rows.has("Journal"), "over a conversation Map and Journal are hidden: %s" % [rows])
	check(rows.has("Resume") and rows.has("Settings") and rows.has("Save & Quit to Title"), "Resume, Settings and Save & Quit stay")


## R11.1: Save & Quit over a conversation must not hang on the paused tree.
func test_save_and_quit_from_pause_over_dialogue_reaches_title() -> void:
	var host := await _boot_main(MARKET)
	var box := _box()
	box.open(_talk())
	await get_tree().process_frame
	await press_action(&"pause", 1)
	await get_tree().process_frame
	var pause := host.screen(&"pause") as PauseMenu
	check(pause.is_open(), "pause is open over the conversation")
	pause._quit()
	await _wait_idle()
	check(SceneRouter.current_room_path == TITLE_ROOM, "the title backdrop loaded (in %s)" % SceneRouter.current_room_path)
	check(not get_tree().paused or (host.get_node("TitleMenu") as MenuScreen).is_open(), "the tree is not frozen behind the title")
	check((host.get_node("TitleMenu") as MenuScreen).is_open(), "the title menu is open")
	check(not box.is_open() and DialogueBox.open_instance == null, "no conversation is left open")
	check(not Game.has_flag("test_talk_done"), "an aborted conversation applies nothing (it replays)")


func test_abort_applies_nothing_and_unpauses() -> void:
	var box := DialogueBox.new()
	add_child(box)
	_extras.append(box)
	box.open(_talk())
	check(get_tree().paused, "paused by the box")
	box.abort()
	check(not get_tree().paused and not box.is_open(), "abort closes and unpauses")
	check(not Game.has_flag("test_talk_done"), "no effects")
	check(DialogueBox.open_instance == null, "open_instance cleared")


# --- Text auto-advance (D-110, R11.9) ---------------------------------------------

func _bare_box() -> DialogueBox:
	var box := DialogueBox.new()
	add_child(box)
	_extras.append(box)
	return box


func test_auto_advance_off_waits_for_input() -> void:
	Settings.text_auto_advance = 0
	var box := _bare_box()
	box.open(_talk(2))
	for i in 600:
		await get_tree().process_frame
	check(box.is_open() and box.line_index == 0, "Off (the default): a typed line waits for a press")
	box.abort()


func test_auto_advance_on_advances_lines_not_choices() -> void:
	Settings.text_auto_advance = 1
	var box := _bare_box()
	box.open(_talk(2))
	var line: String = box._current_line().text
	var wait := Settings.config().auto_advance_seconds(line.length()) * SubtitleStyle.time_scale()
	var frames := int((line.length() / DialogueBox.CHARS_PER_SECOND + wait) * 60.0) + 30
	for i in frames:
		await get_tree().process_frame
	check(box.line_index >= 1 or not box.is_open(), "On: a typed line moves on by itself")
	box.abort()
	box.open(_choice_talk())
	for i in 1200:
		await get_tree().process_frame
	check(box.is_open() and box.is_choosing(), "the options come up and wait")
	check(not Game.has_flag("test_choice_a") and not Game.has_flag("test_choice_b"), "no choice is ever made by itself")
	box.abort()
