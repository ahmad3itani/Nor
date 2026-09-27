class_name NpcProfile
extends Resource
## Who an NPC is and what they say when (ordered rules, first match wins).

## Localization (D5 §4.1): player-visible text fields -> max source chars
## (0 = none). The source stays English here; Loc translates at display.
const LOC_FIELDS := {"display_name": 24, "map_label": 24, "verb": 16}

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
## Presentation overhaul: the NPC's sprite sheet (idle, talk and a signature
## animation). Null keeps the placeholder figure; bodiless voices stay null.
@export var sprite: SpriteSheetSpec
## The idle-life animation NPC plays now and then (tune_radio, work, ...).
@export var signature_anim: StringName = &""
## Dialogue portrait strip (48x48 cells: frame 0 neutral, frame 1 talk); null = none.
@export var portrait: Texture2D

## display name -> NpcProfile (every profile in data/npcs, loaded once).
static var _by_name: Dictionary = {}
static var _by_name_loaded: bool = false


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
	# collected: and count: changes emit no flag_changed; catch up first.
	Game.arcs.evaluate()
	var d := arc.pending_beat()
	if d == null:
		d = arc.idle()
	if d:
		return d
	var fb := rules[rules.size() - 1]
	return fb.dialogue if fb.dialogue and fb.matches() else null


## The profile whose display_name is `n` (the speaker of a dialogue line),
## or null. Profiles come from DataDir.list (export-safe), cached.
static func find_by_display_name(n: String) -> NpcProfile:
	if not _by_name_loaded:
		_by_name_loaded = true
		for path in DataDir.list("res://data/npcs"):
			var p := load(path) as NpcProfile
			if p and p.display_name != "" and not _by_name.has(p.display_name):
				_by_name[p.display_name] = p
	return _by_name.get(n) as NpcProfile


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
	if sprite:
		for e in sprite.validate():
			errors.append("%s sprite: %s" % [npc_id, e])
		for a in [&"idle", &"talk", signature_anim]:
			if a != &"" and not sprite.animations.any(func(s: SpriteAnim) -> bool: return s != null and s.name == a):
				errors.append("%s sprite has no '%s' animation" % [npc_id, a])
	elif signature_anim != &"":
		errors.append("%s: signature_anim without a sprite" % npc_id)
	return errors
