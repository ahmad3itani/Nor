extends CanvasLayer
## Conversation box (bible §19, §24 "pause during dialogue"). Pauses the game
## while open, types text out, and advances on interact/confirm/jump/attack.
## Pressing during typing completes the line first (never skips unread text).

const CHARS_PER_SECOND := 70.0
const ADVANCE_ACTIONS: Array[StringName] = [&"interact", &"ui_accept", &"jump", &"attack_light"]

var dialogue: DialogueData
var line_index: int = 0
var shown_chars: float = 0.0
var _npc_name: String = ""
var _opened_frame: int = -1
var _root: Control


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.draw.connect(_draw_box)
	add_child(_root)
	visible = false
	EventBus.dialogue_requested.connect(open)


func is_open() -> bool:
	return dialogue != null


func open(d: Resource, npc_name: String = "") -> void:
	dialogue = d as DialogueData
	if dialogue == null or dialogue.lines.is_empty():
		dialogue = null
		return
	_npc_name = npc_name
	line_index = 0
	shown_chars = 0.0
	_opened_frame = Engine.get_process_frames()
	visible = true
	get_tree().paused = true
	EventBus.interact_prompt_changed.emit("")


func _process(delta: float) -> void:
	if dialogue == null:
		return
	var line := dialogue.lines[line_index]
	shown_chars = minf(shown_chars + CHARS_PER_SECOND * delta, line.text.length())
	# Ignore the press that opened the box.
	if Engine.get_process_frames() != _opened_frame and _advance_pressed():
		if shown_chars < line.text.length():
			shown_chars = line.text.length()
		else:
			advance()
	_root.queue_redraw()


func _advance_pressed() -> bool:
	for a in ADVANCE_ACTIONS:
		if Input.is_action_just_pressed(a):
			return true
	return false


func advance() -> void:
	line_index += 1
	shown_chars = 0.0
	AudioManager.play_sfx(&"ui_tick")
	if line_index >= dialogue.lines.size():
		_close()


func _close() -> void:
	var finished := dialogue
	dialogue = null
	visible = false
	get_tree().paused = false
	Game.apply_dialogue(finished)
	EventBus.dialogue_finished.emit(finished)


## Wrapped rows the current line needs at the current subtitle size (tests).
func line_count() -> int:
	if dialogue == null:
		return 0
	return SubtitleStyle.line_count(dialogue.lines[line_index].text, _box_width() - SubtitleStyle.PAD_X * 2)


## The box rect for the current line: sized from the full line (so it never
## grows while typing), bottom edge fixed at view.y - 16 like M7.
func box_rect() -> Rect2:
	var view := _root.size
	var h := SubtitleStyle.box_height(dialogue.lines[line_index].text, _box_width())
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
	var line := dialogue.lines[line_index]
	if SubtitleStyle.show_label():
		var speaker := line.speaker if line.speaker != "" else _npc_name
		var lpos := box.position + Vector2(SubtitleStyle.PAD_X, SubtitleStyle.label_y())
		if SubtitleStyle.outline():
			_root.draw_string_outline(font, lpos, speaker.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 1, Color.BLACK)
		_root.draw_string(font, lpos, speaker.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, SubtitleStyle.ACCENT)
	var text := line.text.substr(0, int(shown_chars))
	SubtitleStyle.draw_text(_root, font, box.position + Vector2(SubtitleStyle.PAD_X, SubtitleStyle.text_y()), text, box.size.x - SubtitleStyle.PAD_X * 2, fs, Color.WHITE)
	if shown_chars >= line.text.length() and int(Time.get_ticks_msec() / 400) % 2 == 0:
		_root.draw_string(font, box.end - Vector2(24, 6), "[%s]" % InputGlyphs.label(&"interact"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 1, Color(1, 1, 1, 0.7))
