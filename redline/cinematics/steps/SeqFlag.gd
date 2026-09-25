class_name SeqFlag
extends SequenceStep
## Sets flags. The same in run and finish, so a skip never loses a
## consequence (the DialogueData rule). Values are bool or int only.

@export var flags: PackedStringArray = []
@export var value: Variant = true


func finish(_p: SequencePlayer) -> void:
	for f in flags:
		Game.set_flag(f, value)


func validate(_v: SequenceValidation) -> PackedStringArray:
	var out := PackedStringArray()
	if flags.is_empty():
		out.append("no flags")
	if typeof(value) != TYPE_BOOL and typeof(value) != TYPE_INT:
		out.append("value must be bool or int (got %s)" % type_string(typeof(value)))
	return out


func content_flags() -> Dictionary:
	var d := super()
	d["produces"] = Array(flags)
	return d
