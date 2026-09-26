class_name MenuScreen
extends CanvasLayer
## Base for pause-the-world menus: controller-first focus navigation,
## ui_cancel (or ui_back outside text fields) closes, the game is paused while open (bible §27).
##
## M9 (T03, D4 §3.3, §7.4, §8.7):
## - Rows live in a ScrollContainer that follows focus, so a long page (or a
##   page at 150 % UI size) scrolls instead of leaving the 270 px canvas. Its
##   height tracks the content up to AccessibilityConfig.menu_max_height, so
##   every page that fit before looks exactly as it did.
## - add_option_row: left/right adjust a value without moving focus.
## - close_menu restores the pause state open_menu found (a menu over a
##   paused dialogue keeps it paused), instead of always unpausing (D-159).
##   A pause is only restored while something still owns it: another open
##   menu, or a node in the PAUSE_OWNERS group whose owns_pause() is true
##   (T11 adds DialogueBox). A bare paused tree with no owner (a test, a
##   stale flag) resumes as before, so "Skip scene" and "Resume" never leave
##   the world frozen with nothing on screen.
## - A footer line pinned under the scroll area (Settings' row descriptions).

signal closed

## Menus open right now (DialogueBox ignores input while any is, T11).
static var open_count: int = 0
## Group of nodes that pause the tree themselves (dialogue, T11). Each
## implements `owns_pause() -> bool`; close_menu keeps the tree paused while
## any of them still returns true.
const PAUSE_OWNERS := &"tree_pause_owners"

var _panel: PanelContainer
var _body: VBoxContainer
var _opened_frame: int = -1
## MenuHost.context at open time; screens read ctx, never MenuHost.context, after open.
var ctx: Dictionary = {}
## The tree's pause state when this menu opened; close_menu puts it back.
var _was_paused: bool = false
var _root: Control
var _frame: VBoxContainer
var _scroll: ScrollContainer
var _footer: Label
## Panel width the screen asked for (MenuScreen default 360, or the width a
## subclass set in _ready); scaled with the UI size on open.
var _declared_width: float = -1.0


## A row whose value changes with ui_left / ui_right as well as confirm.
## The press is accepted, so focus never jumps to a neighbouring control.
class OptionRowButton extends Button:
	var on_left: Callable
	var on_right: Callable

	func _gui_input(event: InputEvent) -> void:
		if event.is_action_pressed(&"ui_left", true):
			if on_left.is_valid():
				on_left.call()
			accept_event()
		elif event.is_action_pressed(&"ui_right", true):
			if on_right.is_valid():
				on_right.call()
			accept_event()


func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Text is translated explicitly through Loc (D5 §3.6): no Label may tr()
	# an already translated string again.
	_root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_root.layout_direction = Control.LAYOUT_DIRECTION_LOCALE
	_root.theme = UiTheme.get_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(360, 0)
	center.add_child(_panel)
	_frame = VBoxContainer.new()
	_frame.add_theme_constant_override("separation", 3)
	_panel.add_child(_frame)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_frame.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 3)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	# Autowrap labels settle over two sort passes, so the cap follows the
	# body's minimum size whenever it changes, not once per rebuild.
	_body.minimum_size_changed.connect(_fit_scroll)
	_footer = Label.new()
	_footer.visible = false
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.add_theme_color_override("font_color", UiTheme.MUTED)
	_frame.add_child(_footer)
	_footer.minimum_size_changed.connect(_fit_scroll)


func is_open() -> bool:
	return visible


func open_menu() -> void:
	if not visible:
		open_count += 1
		_was_paused = get_tree().paused
	visible = true
	_opened_frame = Engine.get_process_frames()
	_apply_look()
	get_tree().paused = true
	EventBus.interact_prompt_changed.emit("")
	rebuild()


func close_menu() -> void:
	if not visible:
		return
	visible = false
	open_count = maxi(open_count - 1, 0)
	get_tree().paused = _was_paused and pause_owned(get_tree())
	closed.emit()


## Whether anything besides a closing menu still holds the tree paused.
static func pause_owned(tree: SceneTree) -> bool:
	if open_count > 0:
		return true
	for n in tree.get_nodes_in_group(PAUSE_OWNERS):
		if n.has_method("owns_pause") and bool(n.call("owns_pause")):
			return true
	return false


func _exit_tree() -> void:
	# A screen freed while open (tests, quit) must not leave the count up.
	if visible:
		open_count = maxi(open_count - 1, 0)
		visible = false


## Subclasses rebuild their contents here (called on open and after changes).
func rebuild() -> void:
	pass


func _process(_delta: float) -> void:
	if visible and Engine.get_process_frames() != _opened_frame and cancel_pressed():
		close_menu()


## Back-out input for menus: ui_cancel (Esc, pad B) or ui_back (Backspace,
## which the browser leaves alone in web fullscreen). Backspace is a separate
## action, not part of ui_cancel: Godot's LineEdit/TextEdit treat ui_cancel as
## "release focus", so a Backspace in ui_cancel could never delete a character.
## ui_back is ignored while a text field has focus, so Backspace edits the text.
func cancel_pressed() -> bool:
	if Input.is_action_just_pressed(&"ui_cancel"):
		return true
	if not Input.is_action_just_pressed(&"ui_back"):
		return false
	var focus := get_viewport().gui_get_focus_owner() if get_viewport() != null else null
	return not (focus is LineEdit or focus is TextEdit)


func clear_body() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()


func add_label(text: String, color: Color = UiTheme.TEXT, size: int = UiTheme.FONT_SIZE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", UiTheme.label_color(color))
	l.add_theme_font_size_override("font_size", UiTheme.scaled(size))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(l)
	return l


func add_button(text: String, on_press: Callable, on_focus: Callable = Callable(), enabled := true) -> Button:
	var b := Button.new()
	_setup_button(b, text, on_press, on_focus, enabled)
	_body.add_child(b)
	return b


## A value row: confirm runs on_confirm (cycle forward, the one-button rule),
## ui_left / ui_right run on_left / on_right without moving focus.
func add_option_row(text: String, on_confirm: Callable, on_left: Callable, on_right: Callable, on_focus: Callable = Callable()) -> Button:
	var b := OptionRowButton.new()
	b.on_left = on_left
	b.on_right = on_right
	_setup_button(b, text, on_confirm, on_focus, true)
	_body.add_child(b)
	return b


func _setup_button(b: Button, text: String, on_press: Callable, on_focus: Callable, enabled: bool) -> void:
	b.text = (UiTheme.DISABLED_PREFIX + text) if not enabled and UiTheme.high_contrast() else text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(on_press)
	if on_focus.is_valid():
		b.focus_entered.connect(on_focus)


## The pinned line under the scroll area. reserve_lines > 0 keeps that many
## lines of room even for short or empty text, so the panel does not jump as
## focus moves; "" with no reserve hides it.
func set_footer(text: String, reserve_lines: int = 0) -> void:
	_footer.text = text
	_footer.visible = text != "" or reserve_lines > 0
	var fsize := UiTheme.font_size()
	_footer.add_theme_font_size_override("font_size", fsize)
	_footer.add_theme_color_override("font_color", UiTheme.muted_color())
	var font := _footer.get_theme_font(&"font")
	var line := font.get_height(fsize) if font else float(fsize + 2)
	_footer.custom_minimum_size.y = line * reserve_lines
	_fit_scroll()


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


## Theme and panel width for the current contrast and UI size.
func _apply_look() -> void:
	_root.theme = UiTheme.get_theme()
	if _declared_width < 0.0:
		_declared_width = _panel.custom_minimum_size.x
	_panel.custom_minimum_size.x = panel_width_for(_declared_width)
	_fit_scroll()


## A 360 px panel takes AccessibilityConfig.menu_panel_width for the UI size;
## wider screens scale their own width. Never wider than the viewport - 16.
func panel_width_for(declared: float) -> float:
	var w := declared
	var cfg := Settings.config()
	if cfg != null:
		w = float(cfg.panel_width(UiTheme.scale_index())) if is_equal_approx(declared, 360.0) else declared * UiTheme.scale()
	var view := get_viewport().get_visible_rect().size.x if get_viewport() != null else 480.0
	return minf(w, view - 16.0)


## Scroll height = content height, capped so the whole panel content (rows
## plus the pinned footer) stays within menu_max_height.
func _fit_scroll() -> void:
	if _scroll == null:
		return
	var cap := 250.0
	var cfg := Settings.config()
	if cfg != null:
		cap = float(cfg.menu_max_height)
	if _footer != null and _footer.visible:
		cap -= _footer.get_combined_minimum_size().y + float(_frame.get_theme_constant(&"separation"))
	var content := _body.get_combined_minimum_size().y
	cap = maxf(cap, 40.0)
	_scroll.custom_minimum_size.y = minf(content, cap)
	# A page that fits keeps the M8 geometry exactly: no reserved scrollbar
	# width and no clipping (glyphs may overhang their label by a pixel).
	var overflow := content > cap
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if overflow else ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.clip_contents = overflow
