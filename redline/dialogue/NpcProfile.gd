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
## M8 character arc (D-117). Null for voices without one (radios, terminals,
## notes, test fixtures): their picking is exactly the M7 rule list.
@export var arc: NpcArc
## M8 "new lines" cue for arc-less voices (the Relay radio board): the NPC
## shows the pending tick while the dialogue it would play now has not been
## heard (NPC sets the code flag heard_<dialogue id> when it closes).
@export var cue_new_lines: bool = false


## Pick order with an arc: story rules (every rule but the fallback: intros,
## one-shots, quest turn-ins) > the arc's oldest pending beat > the current
## stage's idle lines > the fallback. Without an arc: first matching rule.
func pick_dialogue() -> DialogueData:
	var story_end := rules.size() - 1 if arc else rules.size()
	for i in story_end:
		var r := rules[i]
		if r.dialogue and r.matches():
			return r.dialogue
	if arc == null or rules.is_empty():
		return null
	var d := arc.pending_beat()
	if d == null:
		d = arc.idle()
	if d:
		return d
	var fb := rules[rules.size() - 1]
	return fb.dialogue if fb.dialogue and fb.matches() else null


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
	if arc and arc.npc_id != npc_id:
		errors.append("%s: arc belongs to '%s'" % [npc_id, arc.npc_id])
	return errors
