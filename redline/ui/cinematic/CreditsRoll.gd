class_name CreditsRoll
extends Control
## The credits column SeqCredits scrolls (placeholder look, D-026). A centred
## column rises from below the screen; the closing line stops at the centre
## and holds. Text size and background follow the Subtitle settings (§24);
## the scroll is slow and nothing flashes.
##
## It never moves itself: SeqCredits sets `scroll` from the sequence clock,
## so pause, AUTO speed and skip behave like every other step.

const COLUMN_WIDTH := 300.0
const HEADING_COLOR := SubtitleStyle.ACCENT

var credits: CreditsData
var row_height: float = 11.0
## Pixels the column has risen since it started below the screen.
var scroll: float = 0.0:
	set(v):
		scroll = v
		queue_redraw()

var _rows: Array[Dictionary] = []


func setup(c: CreditsData, row_h: float) -> void:
	credits = c
	row_height = row_h
	_rows.clear()
	if c:
		_rows = c.rows()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Scroll at which the last row sits at the vertical centre (the hold).
func hold_scroll(view_height: float) -> float:
	return view_height * 0.5 + maxf(0.0, _rows.size() - 1) * row_height


func _draw() -> void:
	var view := get_viewport_rect().size
	var f := SubtitleStyle.font()
	var fs := SubtitleStyle.font_size()
	var a := SubtitleStyle.subtitle_alpha()
	var x := (view.x - COLUMN_WIDTH) * 0.5
	if a > 0.0:
		draw_rect(Rect2(x - 8.0, 0.0, COLUMN_WIDTH + 16.0, view.y), Color(SubtitleStyle.BG, a))
	var top := view.y - minf(scroll, hold_scroll(view.y))
	for i in _rows.size():
		var y := top + i * row_height + fs
		if y < -row_height or y > view.y + row_height:
			continue
		var r: Dictionary = _rows[i]
		var text: String = r["text"]
		if text == "":
			continue
		var color := HEADING_COLOR if r["heading"] else Color.WHITE
		if SubtitleStyle.outline():
			draw_string_outline(f, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_CENTER, COLUMN_WIDTH, fs, 1, Color.BLACK)
		draw_string(f, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_CENTER, COLUMN_WIDTH, fs, color)
