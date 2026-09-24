class_name QuestStage
extends Resource

@export_multiline var description: String = ""
## The stage is done when every flag here is set. Progress shows as n/total.
@export var complete_flags: PackedStringArray = []
## Optional map note while this stage is active (bible §19/§20: "map notes"
## rather than objective markers). Room id + room-local position + text.
@export var map_room: String = ""
@export var map_pos: Vector2 = Vector2.ZERO
@export var map_note: String = ""
