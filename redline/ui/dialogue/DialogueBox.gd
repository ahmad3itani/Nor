class_name DialogueBox
extends CanvasLayer
## Conversation box (bible §19, §24 "pause during dialogue"). Pauses the game
## while open, types text out, and advances on interact/confirm/jump/attack.
## Pressing during typing completes the line first (never skips unread text).
##
## M8 choice mode (bible §19 "meaningful choice", §24): a dialogue with
## `choices` lists them under its last line and waits; there is no timeout and
## no auto-pick (text auto-advance is cut, D-110). Selection moves on
## move_up/move_down/ui_up/ui_down; confirm is ui_accept, jump, or keyboard
## interact (E, the key the box's "[E]" cue taught). Pad D-pad Up is bound to
## both interact and move_up (project.godot button 11), so interact only
## confirms while the keyboard is the active device. A confirm counts only
## after CinematicConfig.choice_arm_seconds real time (the tree is paused) and after every
## advance action has been seen released since the options appeared, so a
## held or mashed press carried over from the last line never picks. The
## picked answer's reply plays with the normal advance rules, then the box
## closes and Game.apply_dialogue(d, choice) applies everything at once.
##
## M9 (D4 §8.7, D-159): pause opens the pause menu over the box (both modes,
## Orr's choice included); while any menu is open the box ignores input, and
## the menu's close keeps the tree paused because the box owns that pause
## (MenuScreen.PAUSE_OWNERS). Save & Quit aborts the conversation (abort():
## no effects, so it replays on Continue). Text auto-advance (D-110, Settings
## .text_auto_advance) moves fully typed lines on after a reading time;
## choices always wait. In NG+ a conversation whose flags the player already
## set in an earlier cycle shows each line fully typed (R11.13).

const CHARS_PER_SECOND := 70.0
const ADVANCE_ACTIONS: Array[StringName] = [&"interact", &"ui_accept", &"jump", &"attack_light"]
## Choice mode input (never attack_light: a combat button must not answer).
const CHOICE_UP_ACTIONS: Array[StringName] = [&"move_up", &"ui_up"]
const CHOICE_DOWN_ACTIONS: Array[StringName] = [&"move_down", &"ui_down"]
const CHOICE_CONFIRM_ACTIONS: Array[StringName] = [&"ui_accept", &"jump"]

var dialogue: DialogueData
var line_index: int = 0
var shown_chars: float = 0.0
var _npc_name: String = ""
var _opened_frame: int = -1
var _root: Control
## Lines on screen: the dialogue's own, then the picked choice's reply.
var _lines: Array[DialogueLine] = []
var _choosing: bool = false
var _selected: int = 0
## Index of the picked DialogueChoice (-1 = none yet).
var _choice: int = -1
var _choice_shown_ms: int = 0
## Advance actions seen released since the options appeared.
var _released: Dictionary = {}
## Seconds a fully typed line has waited (text auto-advance; process delta,
## which keeps running while the tree is paused).
var _auto_wait: float = 0.0

## The box with a conversation on screen (null when none): Save & Quit
## aborts it (PauseMenu.save_and_quit_state).
static var open_instance: DialogueBox = null


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.draw.connect(_draw_box)
	add_child(_root)
	visible = false
	# PauseMenu finds the box through this group (Map and Journal stay shut
	# over a conversation); MenuScreen keeps the tree paused while it is open.
	add_to_group(&"dialogue_box")
	add_to_group(MenuScreen.PAUSE_OWNERS)
	EventBus.dialogue_requested.connect(open)


func _exit_tree() -> void:
	if open_instance == self:
		open_instance = null


## MenuScreen.PAUSE_OWNERS: a menu closing over the box leaves the tree paused.
func owns_pause() -> bool:
	return is_open()


func is_open() -> bool:
	return dialogue != null


func open(d: Resource, npc_name: String = "") -> void:
	dialogue = d as DialogueData
	if dialogue == null or dialogue.lines.is_empty():
		dialogue = null
		return
	_npc_name = npc_name
	_lines = dialogue.lines
	_choosing = false
	_selected = 0
	_choice = -1
	_released.clear()
	line_index = 0
	_line_opened()
	_opened_frame = Engine.get_process_frames()
	visible = true
	open_instance = self
	get_tree().paused = true
	EventBus.interact_prompt_changed.emit("")


func _process(delta: float) -> void:
	if dialogue == null:
		return
	# A menu over the box (pause, settings) owns every press until it closes.
	if MenuScreen.open_count > 0:
		return
	# §24 pause during dialogue: the pause menu opens over the box (MenuHost
	# refuses its own pause key while the tree is paused). Not on the frame
	# the box opened, like every other press.
	if Engine.get_process_frames() != _opened_frame and Input.is_action_just_pressed(&"pause"):
		EventBus.menu_requested.emit(&"pause")
		return
	# Choice mode first: the generic advance path below would confirm on the
	# D-pad Up (interact) a pad player uses to move the cursor.
	if _choosing:
		_process_choice()
		_root.queue_redraw()
		return
	var line := _current_line()
	shown_chars = minf(shown_chars + CHARS_PER_SECOND * delta, line.text.length())
	# Ignore the press that opened the box.
	if Engine.get_process_frames() != _opened_frame and _advance_pressed():
		if shown_chars < line.text.length():
			shown_chars = line.text.length()
		else:
			advance()
	elif _auto_advance_due(line, delta):
		advance()
	_root.queue_redraw()


## Text auto-advance (D-110): Off (the default) never advances by itself.
## On, a fully typed line waits AccessibilityConfig's reading time (scaled
## like subtitles) and moves on. Never while choosing (choices always wait).
func _auto_advance_due(line: DialogueLine, delta: float) -> bool:
	if Settings.text_auto_advance != 1 or _choosing or shown_chars < line.text.length():
		_auto_wait = 0.0
		return false
	_auto_wait += delta
	var cfg := Settings.config()
	var wait := (cfg.auto_advance_seconds(line.text.length()) if cfg else 3.0) * SubtitleStyle.time_scale()
	return _auto_wait >= wait


## A new line is on screen: typing starts over, unless NG+ already knows the
## conversation (R11.13: every flag it sets was seen in an earlier cycle), in
## which case it shows fully typed and the first confirm advances.
func _line_opened() -> void:
	shown_chars = 0.0
	_auto_wait = 0.0
	if _known_in_new_game_plus():
		shown_chars = float(_current_line().text.length())


func _known_in_new_game_plus() -> bool:
	if dialogue == null or dialogue.set_flags.is_empty() or NewGamePlus.cycle() < 1:
		return false
	for f in dialogue.set_flags:
		if not NewGamePlus.knows_seen_flag(f):
			return false
	return true


func _advance_pressed() -> bool:
	for a in ADVANCE_ACTIONS:
		if Input.is_action_just_pressed(a):
			return true
	return false


## Next line, or the choices after the last one, or close. While choosing
## it picks the selected option (test/automation helper: an advance()-only
## loop always terminates, with choice 0 unless the cursor moved).
func advance() -> void:
	if dialogue == null:
		return
	if _choosing:
		choose(_selected)
		return
	AudioManager.play_sfx(&"ui_tick")
	if line_index + 1 >= _lines.size() and _choice < 0 and not dialogue.choices.is_empty():
		_enter_choice_mode()
		return
	line_index += 1
	if line_index >= _lines.size():
		shown_chars = 0.0
		_close()
		return
	_line_opened()


func is_choosing() -> bool:
	return _choosing


## Options appear under the last line (kept on screen, fully typed).
func _enter_choice_mode() -> void:
	_choosing = true
	_selected = 0
	_choice_shown_ms = Time.get_ticks_msec()
	_released.clear()
	shown_chars = _current_line().text.length()


## True once a fresh confirm press may pick: the arm time has passed (real
## ms, the tree is paused) and every advance action was seen released since
## the options appeared.
func confirm_armed() -> bool:
	if not _choosing or Time.get_ticks_msec() - _choice_shown_ms < int(CinematicMode.config().choice_arm_seconds * 1000.0):
		return false
	for a in ADVANCE_ACTIONS:
		if not _released.has(a):
			return false
	return true


func _process_choice() -> void:
	for a in ADVANCE_ACTIONS:
		if not Input.is_action_pressed(a):
			_released[a] = true
	var n := dialogue.choices.size()
	var moved := false
	if _any_just_pressed(CHOICE_UP_ACTIONS):
		_selected = (_selected - 1 + n) % n
		moved = true
	if _any_just_pressed(CHOICE_DOWN_ACTIONS):
		_selected = (_selected + 1) % n
		moved = true
	if moved:
		AudioManager.play_sfx(&"ui_tick")
		return
	if _confirm_pressed() and confirm_armed():
		choose(_selected)


func _confirm_pressed() -> bool:
	if _any_just_pressed(CHOICE_CONFIRM_ACTIONS):
		return true
	return not InputGlyphs.using_pad and Input.is_action_just_pressed(&"interact")


func _any_just_pressed(actions: Array[StringName]) -> bool:
	for a in actions:
		if Input.is_action_just_pressed(a):
			return true
	return false


## Records the answer and plays its reply (or closes). The flags apply on
## close, like every other dialogue effect.
func choose(i: int) -> void:
	if dialogue == null or not _choosing or i < 0 or i >= dialogue.choices.size():
		return
	_choosing = false
	_choice = i
	var c := dialogue.choices[i]
	EventBus.dialogue_choice_made.emit(dialogue.id, c.id)
	AudioManager.play_sfx(&"ui_tick")
	if c.reply.is_empty():
		_close()
		return
	_lines = c.reply
	line_index = 0
	_line_opened()


## Footer under the options: the button that confirms on the active device
## (the same E / A the conversation used to advance).
func choice_footer() -> String:
	var glyph := InputGlyphs.label(&"jump") if InputGlyphs.using_pad else InputGlyphs.label(&"interact")
	return "[%s] choose" % glyph


func _current_line() -> DialogueLine:
	return _lines[mini(line_index, _lines.size() - 1)]


func _close() -> void:
	var finished := dialogue
	var picked := _choice
	dialogue = null
	_choosing = false
	visible = false
	if open_instance == self:
		open_instance = null
	get_tree().paused = false
	Game.apply_dialogue(finished, picked)
	EventBus.dialogue_finished.emit(finished)


## Leaves the conversation without any of its effects (Save & Quit over a
## dialogue, R11.1): no flags, gifts or follow-up menu and no
## dialogue_finished, so it replays on Continue like an aborted scene. The
## tree is unpaused here, or the quit's fade could never run.
func abort() -> void:
	if dialogue == null:
		return
	dialogue = null
	_choosing = false
	_choice = -1
	visible = false
	if open_instance == self:
		open_instance = null
	if is_inside_tree():
		get_tree().paused = false


## Wrapped rows the current line needs at the current subtitle size (tests).
func line_count() -> int:
	if dialogue == null:
		return 0
	return SubtitleStyle.line_count(_current_line().text, _box_width() - SubtitleStyle.PAD_X * 2)


## The box rect for the current line: sized from the full line (so it never
## grows while typing), bottom edge fixed at view.y - 16 like M7. Choice mode
## adds one row per option under the text.
func box_rect() -> Rect2:
	var view := _root.size
	var h := SubtitleStyle.box_height(_current_line().text, _box_width())
	if _choosing:
		h += dialogue.choices.size() * SubtitleStyle.line_spacing()
	return Rect2(24, view.y - 16 - h, _box_width(), h)


func _box_width() -> float:
	return _root.size.x - 48


## Look comes from SubtitleStyle (bible §24 subtitle size/background/speaker
## labels). Default settings draw exactly the M7 box.
func _draw_box() -> void:
	if dialogue == null:
		return
	var font := SubtitleStyle.font()
	var fs := SubtitleStyle.font_size()
	var box := box_rect()
	var alpha := SubtitleStyle.box_alpha()
	if alpha > 0.0:
		_root.draw_rect(box, Color(SubtitleStyle.BG, alpha))
		_root.draw_rect(Rect2(box.position, Vector2(box.size.x, 1)), SubtitleStyle.ACCENT)
	var line := _current_line()
	if SubtitleStyle.show_label():
		var speaker := line.speaker if line.speaker != "" else _npc_name
		var lpos := box.position + Vector2(SubtitleStyle.PAD_X, SubtitleStyle.label_y())
		if SubtitleStyle.outline():
			_root.draw_string_outline(font, lpos, speaker.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 1, Color.BLACK)
		_root.draw_string(font, lpos, speaker.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, SubtitleStyle.ACCENT)
	var text := line.text.substr(0, int(shown_chars))
	SubtitleStyle.draw_text(_root, font, box.position + Vector2(SubtitleStyle.PAD_X, SubtitleStyle.text_y()), text, box.size.x - SubtitleStyle.PAD_X * 2, fs, Color.WHITE)
	if _choosing:
		_draw_choices(box, font, fs)
		return
	if shown_chars >= line.text.length() and int(Time.get_ticks_msec() / 400) % 2 == 0:
		_root.draw_string(font, box.end - Vector2(24, 6), "[%s]" % InputGlyphs.label(&"interact"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 1, Color(1, 1, 1, 0.7))


## Options under the text rows: "> " marker plus the accent colour on the
## selected one (not colour alone, §24), then the confirm footer.
func _draw_choices(box: Rect2, font: Font, fs: int) -> void:
	var rows := line_count()
	var spacing := SubtitleStyle.line_spacing()
	for i in dialogue.choices.size():
		var selected := i == _selected
		var y := box.position.y + SubtitleStyle.text_y() + (rows + i) * spacing
		var text := ("> " if selected else "  ") + dialogue.choices[i].label
		var pos := Vector2(box.position.x + SubtitleStyle.PAD_X, y)
		if SubtitleStyle.outline():
			_root.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 1, Color.BLACK)
		_root.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, SubtitleStyle.ACCENT if selected else Color.WHITE)
	var footer := choice_footer()
	var w := font.get_string_size(footer, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 1).x
	_root.draw_string(font, box.end - Vector2(w + SubtitleStyle.PAD_X, 6), footer, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 1, Color(1, 1, 1, 0.7))
