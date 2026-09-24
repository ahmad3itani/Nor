class_name QuestStage
extends Resource

@export_multiline var description: String = ""
## The stage is done when every flag here is set. Progress shows as n/total.
@export var complete_flags: PackedStringArray = []
