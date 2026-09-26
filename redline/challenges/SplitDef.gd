class_name SplitDef
extends Resource
## One campaign speedrun split (M9 D2 §2.4): reached the first time `when`
## holds (Game.check_condition, checked on flag_changed and room entry) or the
## first time the player enters `room`. Each split fires once per profile.

const LOC_FIELDS := {"label": 24}
const LOC_EXEMPT := ["id"]

@export var id: String = ""
@export var label: String = ""
@export var when: String = ""
## Alternatively: the first entry into this room path.
@export_file("*.tscn") var room: String = ""


func validate() -> PackedStringArray:
	var out := PackedStringArray()
	if id == "" or id.begins_with("room:"):
		out.append("split id '%s' must be set and must not start with 'room:' (auto room splits)" % id)
	if label == "":
		out.append("split %s has no label" % id)
	if (when == "") == (room == ""):
		out.append("split %s needs exactly one of when/room" % id)
	if when != "" and not ContentValidator.is_valid_condition(when):
		out.append("split %s: invalid condition '%s'" % [id, when])
	if room != "" and not ResourceLoader.exists(room):
		out.append("split %s: room '%s' does not exist" % [id, room])
	return out
