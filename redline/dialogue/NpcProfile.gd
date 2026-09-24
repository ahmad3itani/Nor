class_name NpcProfile
extends Resource
## Who an NPC is and what they say when (ordered rules, first match wins).

@export var npc_id: String = ""
@export var display_name: String = ""
@export var color: Color = Color("9a8fb5")
## Role shown on the map's NPC pins ("Mechanic"); empty = no pin.
@export var map_label: String = ""
## False for voices without a body (radios, terminals, notes): NPC skips the
## placeholder figure and the room draws the object itself (decor + a small
## cyan LED neon), so the prop reads as a thing, not a person (M7).
@export var figure: bool = true
## Verb on the interact prompt: "Talk" for people, "Listen" for a radio,
## "Read" for a terminal or note.
@export var verb: String = "Talk"
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
	if verb.strip_edges() == "":
		errors.append("%s: empty prompt verb" % npc_id)
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
