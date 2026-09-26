class_name MenuScreen
extends CanvasLayer
## Base for pause-the-world menus: controller-first focus navigation,
## ui_cancel closes, the game is paused while open (bible §27).

signal closed

var _panel: PanelContainer
var _body: VBoxContainer
var _opened_frame: int = -1
## MenuHost.context at open time; screens read ctx, never MenuHost.context, after open.
var ctx: Dictionary = {}


func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.get_theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(360, 0)
	center.add_child(_panel)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 3)
	_panel.add_child(_body)


func is_open() -> bool:
	return visible


func open_menu() -> void:
	visible = true
	_opened_frame = Engine.get_process_frames()
	get_tree().paused = true
	EventBus.interact_prompt_changed.emit("")
	rebuild()


func close_menu() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	closed.emit()


## Subclasses rebuild their contents here (called on open and after changes).
func rebuild() -> void:
	pass


func _process(_delta: float) -> void:
	if visible and Engine.get_process_frames() != _opened_frame and Input.is_action_just_pressed("ui_cancel"):
		close_menu()


func clear_body() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()


func add_label(text: String, color: Color = UiTheme.TEXT, size: int = UiTheme.FONT_SIZE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(l)
	return l


func add_button(text: String, on_press: Callable, on_focus: Callable = Callable(), enabled := true) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(on_press)
	if on_focus.is_valid():
		b.focus_entered.connect(on_focus)
	_body.add_child(b)
	return b


## Keeps focus on the same row after a rebuild (controller users never lose their place).
func focus_index(index: int) -> void:
	var buttons := _body.get_children().filter(func(n: Node) -> bool: return n is Button)
	if buttons.is_empty():
		return
	(buttons[clampi(index, 0, buttons.size() - 1)] as Button).grab_focus()


func focused_index() -> int:
	var buttons := _body.get_children().filter(func(n: Node) -> bool: return n is Button)
	for i in buttons.size():
		if (buttons[i] as Button).has_focus():
			return i
	return 0
