class_name NpcDialogueRule
extends Resource
## "Say this when these flags are set and those are not." NPCs pick the
## first matching rule, so order rules from most to least specific.

@export var requires_flags: PackedStringArray = []
@export var forbids_flags: PackedStringArray = []
@export var dialogue: DialogueData


func matches() -> bool:
	for f in requires_flags:
		if not Game.has_flag(f):
			return false
	for f in forbids_flags:
		if Game.has_flag(f):
			return false
	return true
