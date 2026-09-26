class_name GlyphSet
extends Resource
## Controller button names for one pad family (D4 §5). Godot numbers buttons
## by SDL position (0 = bottom face button), so each family maps the same
## index to its own printed name: Xbox A, PlayStation Cross, Nintendo B.
## Text only until glyph art exists (D-026); `icons` is the slot for it.

## Localization (D5): player-visible text fields -> max source chars. Short
## marks (A, B, LB, ZR) read the same in every language; the multi-letter
## names (D-Pad Up, Left stick, Options) are wrapped by T13.
const LOC_FIELDS := {"display_name": 24, "buttons": 16, "axes": 16}
const LOC_EXEMPT := ["id"]

@export var id: StringName = &""
## Name in the Settings "Button prompts" row.
@export var display_name: String = ""
## JOY_BUTTON index -> printed name.
@export var buttons: Dictionary = {}
## Encoded axis direction ("a5+", "a0-") -> printed name (sticks and triggers).
@export var axes: Dictionary = {}
## Reserved for final glyph art (D-026); unused while prompts are text.
@export var icons: Texture2D = null


func button_name(index: int) -> String:
	return str(buttons.get(index, ""))


func axis_name(axis: int, positive: bool) -> String:
	return str(axes.get("a%d%s" % [axis, "+" if positive else "-"], ""))
