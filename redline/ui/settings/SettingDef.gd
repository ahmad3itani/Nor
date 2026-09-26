class_name SettingDef
extends Resource
## One setting row (D4 §3.1). Settings.load_settings/save_settings loop over
## every persisted def, so a new option is one data row plus one clamped
## property on Settings, never two more hand-written cfg lines (§37.4).
## SettingsMenu renders the same row from the same data.

enum Kind {
	TOGGLE, ## bool; choices (optional) = [off label, on label]
	CHOICE, ## int index into choices
	STEPS, ## float from steps, shown as a percentage; left/right move one step
	ACTION, ## a row with custom behaviour (see `action`); persisted only when `persisted`
}

## Localization (D5): player-visible text fields -> max source chars.
const LOC_FIELDS := {"label": 40, "description": 90, "choices": 20}
const LOC_EXEMPT := ["key", "section", "cfg_key", "assist_tag", "preview", "action"]

## Settings property name (ACTION rows: the property they show, may be empty).
@export var key: StringName = &""
## settings.cfg section. Existing keys keep the section they had in M8.
@export var section: String = ""
## settings.cfg key when it differs from `key` (the M4 playtest keys).
@export var cfg_key: String = ""
@export var kind: Kind = Kind.TOGGLE
## CHOICE labels (index = value); TOGGLE: optional [off, on] labels.
@export var choices: PackedStringArray = []
## STEPS values in order (e.g. 0, 0.1 .. 1.0).
@export var steps: PackedFloat32Array = []
## English source text; Loc.t() translates it at display.
@export var label: String = ""
## At most 90 characters; shown pinned under the list while the row has focus.
@export_multiline var description: String = ""
## Non-empty: Settings.active_assists() may report it (the neutral "assist"
## tag, D-149). Documentation only: active_assists() owns the rules.
@export var assist_tag: StringName = &""
## Row hidden unless DevActions.available().
@export var dev_only: bool = false
## Emit settings_changed as soon as the value changes (rows that restyle
## visible UI); every row still emits it when Settings closes.
@export var emits_settings_changed: bool = true
## &"shake" pulses the camera, &"sfx" plays ui_tick after a change.
@export var preview: StringName = &""
## ACTION rows: which handler SettingsMenu runs (&"variant", &"language",
## &"device", ...).
@export var action: StringName = &""
## Whether the Settings load/save loop stores this row's key.
@export var persisted: bool = true


## The key written to settings.cfg.
func cfg_name() -> String:
	return cfg_key if cfg_key != "" else String(key)


## True for rows the Settings load/save loop reads and writes.
func is_stored() -> bool:
	return persisted and key != &"" and section != ""


## How many values a CHOICE/STEPS/TOGGLE row cycles through.
func value_count() -> int:
	match kind:
		Kind.TOGGLE:
			return 2
		Kind.CHOICE:
			return choices.size()
		Kind.STEPS:
			return steps.size()
	return 0


## The step index nearest to `v` (STEPS rows; stored values off the grid,
## e.g. an old 0.5 hitstop, still land on a step).
func step_index(v: float) -> int:
	var best := 0
	for i in steps.size():
		if absf(steps[i] - v) < absf(steps[best] - v):
			best = i
	return best


## Display text of a value in the source language (the menu wraps it in Loc.t).
func value_text(v: Variant) -> String:
	match kind:
		Kind.TOGGLE:
			if choices.size() == 2:
				return choices[1] if bool(v) else choices[0]
			return "On" if bool(v) else "Off"
		Kind.CHOICE:
			var i := int(v)
			return choices[i] if i >= 0 and i < choices.size() else str(v)
		Kind.STEPS:
			return "%d%%" % roundi(float(v) * 100.0)
	return str(v)
