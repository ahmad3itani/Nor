class_name MemoryFragmentData
extends Resource
## A recovered piece of Rook's memory (bible §18, §21). Short, specific,
## and always adding to a central mystery rather than explaining it.

## Localization (D5 §4.1): player-visible text fields -> max source chars
## (0 = none). The source stays English here; Loc translates at display.
const LOC_FIELDS := {"title": 40, "text": 240}

@export var id: String = ""
@export var title: String = ""
@export_multiline var text: String = ""


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == "" or title == "" or text == "":
		errors.append("memory fragment %s is incomplete" % id)
	if text.length() > 280:
		errors.append("memory fragment %s is too long for the on-screen card (%d chars)" % [id, text.length()])
	return errors
