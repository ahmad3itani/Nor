class_name NpcDialogueRule
extends Resource
## "Say this when these flags are set and those are not." NPCs pick the
## first matching rule, so order rules from most to least specific.

@export var requires_flags: PackedStringArray = []
@export var forbids_flags: PackedStringArray = []
## Extra Game.check_condition expressions (M5), e.g. "atleast:talks_orr:3"
## for relationship lines, "ability:dash", "collected:cs_market".
@export var requires_conditions: PackedStringArray = []
@export var dialogue: DialogueData


func matches() -> bool:
	for f in requires_flags:
		if not Game.has_flag(f):
			return false
	for f in forbids_flags:
		if Game.has_flag(f):
			return false
	for c in requires_conditions:
		if not Game.check_condition(c):
			return false
	return true
