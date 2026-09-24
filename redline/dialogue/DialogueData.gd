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


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == "":
		errors.append("dialogue without id")
	if lines.is_empty():
		errors.append("%s: no lines" % id)
	for l in lines:
		if l.text.length() > 200:
			errors.append("%s: line longer than 200 chars (keep dialogue short, bible §42)" % id)
	return errors
