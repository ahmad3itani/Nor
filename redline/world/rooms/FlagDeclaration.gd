class_name FlagDeclaration
extends Node
## Stand-in flag producer for stub rooms (M7 world skeleton). A stub room that
## a later room task will build declares the flags that room will set, so the
## flag graph validates in the meantime. The validator reports each one as a
## warning, and the final gate asserts none remain.

@export var produces: PackedStringArray = []


## Content protocol (see ContentValidator._check_protocol).
func content_flags() -> Dictionary:
	return {"produces": produces}


func content_errors(_room: Node) -> PackedStringArray:
	# An empty declaration stands in for nothing: an authoring mistake.
	if produces.is_empty():
		return PackedStringArray(["FlagDeclaration declares no flags"])
	return PackedStringArray(["WARN: stub flag declaration: %s" % ", ".join(produces)])
