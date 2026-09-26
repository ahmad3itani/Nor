class_name RebindActionData
extends Resource
## One rebindable action (D4 §4.1): how many key and pad slots the Controls
## page offers, when the action is live (conflicts only count between actions
## live at the same time) and which events can never be removed.

## Localization (D5): player-visible text fields -> max source chars.
const LOC_FIELDS := {"label": 32, "group": 16}
const LOC_EXEMPT := ["contexts", "locked_pad"]

@export var action: StringName = &""
## "Light attack" (English source; Loc.t at display).
@export var label: String = ""
## Heading the Controls page lists it under ("Movement", "Combat", ...).
@export var group: String = ""
@export var key_slots: int = 2
@export var pad_slots: int = 2
## Where the action is live: "gameplay" (world and labs), "challenge" (runs).
@export var contexts: PackedStringArray = ["gameplay"]
## Physical keycodes that can never be removed (pause: Esc).
@export var locked_keys: PackedInt32Array = []
## Encoded pad events that can never be removed (pause: "b6" Start).
@export var locked_pad: PackedStringArray = []
## move_*: the stick axis stays as shipped (shown, not editable); only the
## D-pad button slot is rebindable.
@export var pad_stick_fixed: bool = false


func slot_count(device: StringName) -> int:
	return key_slots if device == &"key" else pad_slots
