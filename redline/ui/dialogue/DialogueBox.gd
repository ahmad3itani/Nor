extends CanvasLayer
## Conversation box (bible §19, §24 "pause during dialogue"). Pauses the game
## while open, types text out, and advances on interact/confirm/jump/attack.
## Pressing during typing completes the line first (never skips unread text).

const CHARS_PER_SECOND := 70.0
const FONT_SIZE := 7
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


func _draw_box() -> void:
	if dialogue == null:
		return
	var font := ThemeDB.fallback_font
	var view := _root.size
	var box := Rect2(24, view.y - 78, view.x - 48, 62)
	_root.draw_rect(box, Color(0.04, 0.03, 0.07, 0.92))
	_root.draw_rect(Rect2(box.position, Vector2(box.size.x, 1)), Color("e8283c"))
	var line := dialogue.lines[line_index]
	var speaker := line.speaker if line.speaker != "" else _npc_name
	_root.draw_string(font, box.position + Vector2(8, 12), speaker.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color("e8283c"))
	var text := line.text.substr(0, int(shown_chars))
	_root.draw_multiline_string(font, box.position + Vector2(8, 25), text, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 16, FONT_SIZE, -1, Color.WHITE)
	if shown_chars >= line.text.length() and int(Time.get_ticks_msec() / 400) % 2 == 0:
		_root.draw_string(font, box.end - Vector2(24, 6), "[%s]" % InputGlyphs.label(&"interact"), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1, Color(1, 1, 1, 0.7))
