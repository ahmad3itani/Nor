class_name MemoryFragmentData
extends Resource
## A recovered piece of Rook's memory (bible §18, §21). Short, specific,
## and always adding to a central mystery rather than explaining it.

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
