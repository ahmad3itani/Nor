class_name CinematicOverlay
extends CanvasLayer
## What a scripted sequence draws over the game: letterbox bars, fades, one
## subtitle line, a title card and the skip prompt (placeholder look, D-026).
## Created by the Cinematics autoload as its own child, so it exists in every
## run (tests included). Idle, it draws nothing.
##
## Layering: HUD 50 < overlay 65 < DialogueBox 70 < menus 80 < memory player
## 85 < SceneRouter fade 90.
## Lines: letterboxed lines sit in the bottom bar (growing upward if the
## subtitle size needs it); lines without a letterbox (radio barks) sit with
## their box bottom at view.y - 68, above CombatHud's hint line (view.y - 58)
## and interact prompt (view.y - 46), and CinematicMode.bark_line holds HUD
## hints while one is on screen.

const LAYER := 65
const BAR_HEIGHT := 26
const LINE_MAX_WIDTH := 400
const BARK_BOTTOM_OFFSET := 68
const FADE_COLOR := Color(0.03, 0.02, 0.05)
const TITLE_SIZE := 16
const TITLE_SUB_COLOR := Color(0.75, 0.72, 0.8)

## 0..1 slide of the bars (tweened by letterbox()).
var letterbox_ratio: float = 0.0:
	set(v):
		letterbox_ratio = v
		_redraw()
var fade_alpha: float = 0.0:
	set(v):
		fade_alpha = v
		_redraw()
var fade_color: Color = FADE_COLOR
## Target state of the bars (true while a letterboxed scene holds them).
var letterbox_on: bool = false
var line_on: bool = false
var line_speaker: String = ""
var line_color: Color = Color.WHITE
var line_text: String = ""
var line_narration: bool = false
## Typed characters shown; -1 = the whole line.
var visible_chars: int = -1
var title_on: bool = false
var title_text: String = ""
var subtitle_text: String = ""
var prompt_on: bool = false
var prompt_text: String = ""
var prompt_ratio: float = 0.0

var _canvas: Control
var _lb_tween: Tween
var _fade_tween: Tween
var _children: Array[Node] = []


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_overlay)
	add_child(_canvas)


func letterbox(show: bool, seconds: float) -> Tween:
	letterbox_on = show
	_update_bark()
	if _lb_tween and _lb_tween.is_valid():
		_lb_tween.kill()
	_lb_tween = null
	if seconds <= 0.0 or not is_inside_tree():
		letterbox_ratio = 1.0 if show else 0.0
		return null
	_lb_tween = create_tween()
	_lb_tween.tween_property(self, "letterbox_ratio", 1.0 if show else 0.0, seconds)
	return _lb_tween


## Returns the tween (null when instant) so a sequence step can adopt it.
func fade(to_alpha: float, seconds: float, color: Color = FADE_COLOR) -> Tween:
	fade_color = color
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
	if seconds <= 0.0 or not is_inside_tree():
		fade_alpha = clampf(to_alpha, 0.0, 1.0)
		return null
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "fade_alpha", clampf(to_alpha, 0.0, 1.0), seconds)
	return _fade_tween


func show_line(speaker_label: String, color: Color, text: String, narration: bool) -> void:
	line_on = true
	line_speaker = "" if narration else speaker_label
	line_color = color
	line_text = text
	line_narration = narration
	visible_chars = -1
	_update_bark()
	_redraw()


func set_visible_chars(n: int) -> void:
	if n != visible_chars:
		visible_chars = n
		_redraw()


func clear_line() -> void:
	line_on = false
	line_text = ""
	_update_bark()
	_redraw()


func show_title(title: String, subtitle: String) -> void:
	title_on = true
	title_text = title
	subtitle_text = subtitle
	_redraw()


func clear_title() -> void:
	title_on = false
	_redraw()


func set_skip_prompt(text: String, ratio: float, show: bool) -> void:
	if show == prompt_on and text == prompt_text and is_equal_approx(ratio, prompt_ratio):
		return
	prompt_on = show
	prompt_text = text
	prompt_ratio = clampf(ratio, 0.0, 1.0)
	_redraw()


## Extra full-screen nodes above the overlay's own drawing (the credits roll).
func add_layer_child(node: Node) -> void:
	add_child(node)
	_children.append(node)


## Back to idle: no line, title, prompt, fade or layer children; the bars
## slide out over `letterbox_seconds` (0 = at once).
func clear_all(letterbox_seconds: float = 0.0) -> void:
	line_on = false
	line_text = ""
	title_on = false
	prompt_on = false
	prompt_ratio = 0.0
	fade(0.0, 0.0)
	fade_color = FADE_COLOR
	letterbox(false, letterbox_seconds)
	for c in _children:
		if is_instance_valid(c):
			c.queue_free()
	_children.clear()
	_update_bark()
	_redraw()


func is_idle() -> bool:
	return not line_on and not title_on and not prompt_on and fade_alpha <= 0.0 and not letterbox_on \
		and _children.all(func(c: Node) -> bool: return not is_instance_valid(c) or c.is_queued_for_deletion())


func bar_height() -> int:
	return BAR_HEIGHT + int((SubtitleStyle.font_size() - 7) * 4.5)


func _update_bark() -> void:
	CinematicMode.bark_line = line_on and not letterbox_on


func _redraw() -> void:
	if _canvas:
		_canvas.queue_redraw()


func _draw_overlay() -> void:
	var view := _canvas.get_viewport_rect().size
	var bar := float(bar_height()) * letterbox_ratio
	if bar > 0.0:
		_canvas.draw_rect(Rect2(0, 0, view.x, bar), Color.BLACK)
		_canvas.draw_rect(Rect2(0, view.y - bar, view.x, bar), Color.BLACK)
	if fade_alpha > 0.0:
		_canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(fade_color, fade_alpha))
	if title_on:
		_draw_title(view)
	if line_on and line_text != "":
		_draw_line(view, bar)
	if prompt_on and prompt_text != "":
		_draw_prompt(view)


func _draw_title(view: Vector2) -> void:
	var f := SubtitleStyle.font()
	var y := view.y * 0.42
	var fs := SubtitleStyle.font_size()
	# The title grows with the Subtitle size setting (§24), 16 px at size 7.
	var ts := roundi(TITLE_SIZE * fs / 7.0)
	_canvas.draw_string_outline(f, Vector2(0, y), title_text, HORIZONTAL_ALIGNMENT_CENTER, view.x, ts, 2, Color.BLACK)
	_canvas.draw_string(f, Vector2(0, y), title_text, HORIZONTAL_ALIGNMENT_CENTER, view.x, ts, Color.WHITE)
	if subtitle_text != "":
		_canvas.draw_string_outline(f, Vector2(0, y + fs + 8), subtitle_text, HORIZONTAL_ALIGNMENT_CENTER, view.x, fs, 1, Color.BLACK)
		_canvas.draw_string(f, Vector2(0, y + fs + 8), subtitle_text, HORIZONTAL_ALIGNMENT_CENTER, view.x, fs, TITLE_SUB_COLOR)


## The box is sized for the whole line, so it does not grow while typing.
func _draw_line(view: Vector2, bar: float) -> void:
	var width := minf(LINE_MAX_WIDTH, view.x - 32.0)
	var lines := SubtitleStyle.line_count(line_text, width - SubtitleStyle.PAD_X * 2)
	var h := float(SubtitleStyle.text_y() + lines * SubtitleStyle.line_spacing() + 4)
	var y := view.y - BARK_BOTTOM_OFFSET - h
	if letterbox_on:
		y = view.y - bar + (float(bar_height()) - h) * 0.5
		y = minf(y, view.y - 3.0 - h)
	var shown := line_text if visible_chars < 0 else line_text.substr(0, visible_chars)
	var rect := Rect2(Vector2((view.x - width) * 0.5, y), Vector2(width, h))
	SubtitleStyle.draw_line(_canvas, rect, "" if line_narration else line_speaker, shown, line_color, true)


func _draw_prompt(view: Vector2) -> void:
	# The skip prompt follows the Subtitle size setting like every line (§24).
	var f := SubtitleStyle.font()
	var fs := SubtitleStyle.font_size()
	var w := f.get_string_size(prompt_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(view.x - 8.0 - w, 5.0 + fs)
	_canvas.draw_string_outline(f, pos, prompt_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 1, Color.BLACK)
	_canvas.draw_string(f, pos, prompt_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.85, 0.85, 0.9))
	if prompt_ratio > 0.0:
		_canvas.draw_rect(Rect2(pos.x, pos.y + 3.0, w, 2.0), Color(1, 1, 1, 0.2))
		_canvas.draw_rect(Rect2(pos.x, pos.y + 3.0, w * prompt_ratio, 2.0), SubtitleStyle.ACCENT)
