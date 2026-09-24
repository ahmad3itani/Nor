class_name NpcProfile
extends Resource
## Who an NPC is and what they say when (ordered rules, first match wins).

@export var npc_id: String = ""
@export var display_name: String = ""
@export var color: Color = Color("9a8fb5")
@export var rules: Array[NpcDialogueRule] = []


func pick_dialogue() -> DialogueData:
	for r in rules:
		if r.dialogue and r.matches():
			return r.dialogue
	return null


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if npc_id == "" or display_name == "":
		errors.append("npc profile missing id/name")
	if rules.is_empty():
		errors.append("%s has no dialogue rules" % npc_id)
	elif not rules[rules.size() - 1].requires_flags.is_empty():
		errors.append("%s: last rule should be an unconditional fallback" % npc_id)
	for r in rules:
		if r.dialogue == null:
			errors.append("%s: rule without dialogue" % npc_id)
		else:
			errors.append_array(r.dialogue.validate())
	return errors
