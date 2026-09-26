class_name SubtitleStyle
extends RefCounted
## Subtitle look shared by DialogueBox, the cinematic overlay and memory
## vignettes (bible §24: subtitle size, background, speaker labels), so one
## settings row restyles every line in the game.
##
## The default settings reproduce the M7 DialogueBox exactly (font 7, label at
## box.y+12, text at box.y+25, 62 px box); bigger sizes grow the box upward
## from the same bottom edge.

const SIZES := [7, 9, 11]
## Background alpha for overlay/memory lines: Outline / Box / Solid.
const SUBTITLE_ALPHAS := [0.0, 0.6, 0.92]
## Background alpha for the DialogueBox: Outline / Box (M7 look) / Solid.
const BOX_ALPHAS := [0.0, 0.92, 1.0]
const TIME_SCALES := [1.0, 1.5, 2.0]
const MIN_BOX_HEIGHT := 62
const PAD_X := 8
const BG := Color(0.04, 0.03, 0.07)
const ACCENT := Color("e8283c")

static var _italic: FontVariation


static func font() -> Font:
	return ThemeDB.fallback_font


static func font_size() -> int:
	return SIZES[Settings.effective_subtitle_size()]


## Height of the speaker label row (font size + 2).
static func line_height() -> int:
	return font_size() + 2


## Baseline advance of wrapped text rows, as draw_multiline_string lays them
## out (the font's own height; >= line_height()). Box sizing uses it so a
## wrapped line can never spill out of the box.
static func line_spacing() -> int:
	return maxi(line_height(), ceili(font().get_height(font_size())))


## Speaker label baseline, from the box top.
static func label_y() -> int:
	return font_size() + 5


## First text baseline, from the box top (label row skipped when labels are off).
static func text_y() -> int:
	return label_y() + line_height() + 4 if show_label() else label_y()


## Wrapped rows `text` needs at `width` px with the current size.
static func line_count(text: String, width: float) -> int:
	if text == "":
		return 1
	var h := font().get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size()).y
	return maxi(1, roundi(h / font().get_height(font_size())))


## Box height for `text` wrapped in a box `width` px wide (text is inset PAD_X
## on both sides). Never below the M7 62 px.
static func box_height(text: String, width: float) -> int:
	var lines := line_count(text, width - PAD_X * 2)
	return maxi(MIN_BOX_HEIGHT, text_y() + lines * line_spacing() + 6)


static func subtitle_alpha() -> float:
	return SUBTITLE_ALPHAS[Settings.subtitle_background]


static func box_alpha() -> float:
	return BOX_ALPHAS[Settings.subtitle_background]


## "Outline" background: no box, text keeps a 1 px dark outline instead.
static func outline() -> bool:
	return Settings.subtitle_background == 0


static func show_label() -> bool:
	return Settings.speaker_labels


## Multiplier on timed line durations (Subtitle speed: Normal/Slow/Slower).
static func time_scale() -> float:
	return TIME_SCALES[Settings.subtitle_speed]


## One subtitle line in `rect` (overlay and memory vignettes): background per
## subtitle_alpha, optional UPPERCASE speaker label, wrapped text. A line with
## no speaker is narration and is slanted when italic_narration.
static func draw_line(ci: CanvasItem, rect: Rect2, speaker: String, text: String, speaker_color: Color, italic_narration := true) -> void:
	var fs := font_size()
	var a := subtitle_alpha()
	if a > 0.0:
		ci.draw_rect(rect, Color(BG, a))
	var text_font := font()
	if speaker == "" and italic_narration:
		text_font = _italic_font()
	if show_label() and speaker != "":
		var lpos := rect.position + Vector2(PAD_X, label_y())
		if outline():
			ci.draw_string_outline(font(), lpos, speaker.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 1, Color.BLACK)
		ci.draw_string(font(), lpos, speaker.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, speaker_color)
	draw_text(ci, text_font, rect.position + Vector2(PAD_X, text_y()), text, rect.size.x - PAD_X * 2, fs, Color.WHITE)


## Wrapped text with the outline under it when the background is "Outline".
static func draw_text(ci: CanvasItem, f: Font, pos: Vector2, text: String, width: float, fs: int, color: Color) -> void:
	if outline():
		ci.draw_multiline_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, width, fs, -1, 1, Color(0, 0, 0, color.a))
	ci.draw_multiline_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, width, fs, -1, color)


static func _italic_font() -> Font:
	if _italic == null:
		_italic = FontVariation.new()
		_italic.base_font = font()
		# Placeholder slant until the art pass picks a real italic (D-026).
		_italic.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.2, 1), Vector2.ZERO)
	return _italic


## Drops the static cache (Cinematics clears every story cache at exit, so
## no Resource outlives its script and the engine reports no leaks).
static func clear_cache() -> void:
	_italic = null
