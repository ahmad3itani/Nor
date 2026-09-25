class_name DialogueData
extends Resource
## One conversation (bible §19). Effects apply when the last line closes, so
## skipping or mashing never loses a reward or a flag.

@export var id: String = ""
@export var lines: Array[DialogueLine] = []

@export_group("On finish")
@export var set_flags: PackedStringArray = []
@export var give_scrap: int = 0
@export var give_circuit: String = ""
@export var give_weapon: String = ""
## Menu to open after the conversation (e.g. "shop_vell", "shop_mara").
@export var open_menu: StringName = &""

## M8: answers offered after the last line (bible §19 "meaningful choice").
## Empty = a plain linear conversation (every M7 dialogue). The picked
## choice's set_flags apply on close with the rest of the effects.
@export var choices: Array[DialogueChoice] = []

const CHOICE_LABEL_MAX := 28
const LINE_MAX := 200


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == "":
		errors.append("dialogue without id")
	if lines.is_empty():
		errors.append("%s: no lines" % id)
	for l in lines:
		if l.text.length() > LINE_MAX:
			errors.append("%s: line longer than 200 chars (keep dialogue short, bible §42)" % id)
	errors.append_array(_validate_choices())
	return errors


## 0 or 2-3 choices (one option is not a choice; four do not fit the box),
## unique ids, short labels, non-empty and disjoint flags, short replies.
func _validate_choices() -> PackedStringArray:
	var errors := PackedStringArray()
	if choices.is_empty():
		return errors
	if choices.size() < 2 or choices.size() > 3:
		errors.append("%s: a choice needs 2-3 options (has %d)" % [id, choices.size()])
	var ids := {}
	var owner := {}
	for c in choices:
		if c == null:
			errors.append("%s: empty choice slot" % id)
			continue
		if c.id == "" or ids.has(c.id):
			errors.append("%s: choice id '%s' missing or duplicated" % [id, c.id])
		ids[c.id] = true
		if c.label.strip_edges() == "" or c.label.length() > CHOICE_LABEL_MAX:
			errors.append("%s: choice '%s' label must be 1-%d chars" % [id, c.id, CHOICE_LABEL_MAX])
		if c.set_flags.is_empty():
			errors.append("%s: choice '%s' sets no flags (the answer would be lost)" % [id, c.id])
		for f in c.set_flags:
			if owner.has(f) and owner[f] != c.id:
				errors.append("%s: choices '%s' and '%s' both set '%s'" % [id, owner[f], c.id, f])
			owner[f] = c.id
		for l in c.reply:
			if l.text.length() > LINE_MAX:
				errors.append("%s: choice '%s' reply line longer than 200 chars" % [id, c.id])
	return errors
