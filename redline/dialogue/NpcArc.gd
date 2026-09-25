class_name NpcArc
extends Resource
## A character arc (bible §19 "multi-district character arc"; D-050 left
## branching arcs to M8; D-117). Spine = story-order stages; reactions =
## things the player may do in any order (memories, secrets, spending), so a
## sequence break never strands an arc. Progress is derived from flags and
## made sticky by ArcTracker; nothing but flags is saved (D-087/D-090).
## Relationships are named facts (bond_*), never a score (§18 "no morality
## meter"). Owned by exactly one NpcProfile (profile.arc).
##
## Pick order (NpcProfile.pick_dialogue): story rules > oldest pending beat
## (spine first, then reactions) > current stage idle (walking back) >
## the profile's fallback.

const NPC_DIR := "res://data/npcs"
const JOURNAL_NOTE_MAX := 80

@export var npc_id: String = ""
@export var stages: Array[NpcArcStage] = []
@export var reactions: Array[NpcArcStage] = []
## Later-act hooks this arc sets in Act I (thread_<npc>_<name>). Each must be
## set by one of this arc's beats or choices. Nothing in Act I reads them.
@export var threads: PackedStringArray = []

## Test hook: when set, content_check uses this profile as the owner instead
## of scanning data/npcs (in-memory arcs have no owning file).
var lint_owner: NpcProfile = null


func stage_flag(id: String) -> String:
	return "arc_%s_%s" % [npc_id, id]


## Int flag: spine index reached (0 = none, 1 = first stage...).
func index_flag() -> String:
	return "arc_%s_stage" % npc_id


func heard_flag(id: String) -> String:
	return "arcbeat_%s_%s" % [npc_id, id]


func current_index() -> int:
	return Game.flag_int(index_flag())


func is_reached(s: NpcArcStage) -> bool:
	return Game.has_flag(stage_flag(s.id))


## Spine stages then reactions (the pending-beat order).
func all_stages() -> Array[NpcArcStage]:
	var out: Array[NpcArcStage] = []
	out.append_array(stages)
	out.append_array(reactions)
	return out


func stage(id: String) -> NpcArcStage:
	for s: NpcArcStage in all_stages():
		if s.id == id:
			return s
	return null


## Reached spine stages in order, then reactions in list order: the first
## one whose beat is unheard and matches.
func pending_beat() -> DialogueData:
	for s: NpcArcStage in all_stages():
		if s.beat_rules.is_empty() or not is_reached(s) or Game.has_flag(heard_flag(s.id)):
			continue
		var d := s.beat()
		if d:
			return d
	return null


func has_pending_beat() -> bool:
	return pending_beat() != null


## Idle lines of the latest reached stage, walking back to the first.
func idle() -> DialogueData:
	var i := mini(current_index(), stages.size()) - 1
	while i >= 0:
		var d := stages[i].idle()
		if d:
			return d
		i -= 1
	return null


## The latest reached spine stage's note ("" before the first stage).
func journal_note() -> String:
	for i in range(stages.size() - 1, -1, -1):
		if is_reached(stages[i]) and stages[i].journal_note != "":
			return stages[i].journal_note
	return ""


func has_reached_any() -> bool:
	for s: NpcArcStage in stages:
		if is_reached(s):
			return true
	return false


## Every dialogue the arc can play: beats, idles (choice replies live inside
## their dialogue).
func dialogues() -> Array[DialogueData]:
	var out: Array[DialogueData] = []
	for s: NpcArcStage in all_stages():
		for r: NpcDialogueRule in s.beat_rules + s.idle_rules:
			if r and r.dialogue and not out.has(r.dialogue):
				out.append(r.dialogue)
	return out


## Structural rules (no other files needed).
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if npc_id == "":
		errors.append("arc without npc_id")
	var ids := {}
	for s: NpcArcStage in all_stages():
		if s == null:
			errors.append("%s: empty stage slot" % npc_id)
			continue
		if s.id == "" or ids.has(s.id):
			errors.append("%s: stage id '%s' missing or duplicated" % [npc_id, s.id])
		ids[s.id] = true
	for s: NpcArcStage in stages:
		if s and s.min_stage != 0:
			errors.append("%s: spine stage %s has min_stage (reactions only)" % [npc_id, s.id])
	for s: NpcArcStage in reactions:
		if s == null:
			continue
		if not s.idle_rules.is_empty() or s.journal_note != "":
			errors.append("%s: reaction %s has idle lines or a journal note (spine only)" % [npc_id, s.id])
		if s.min_stage < 0 or s.min_stage > stages.size():
			errors.append("%s: reaction %s min_stage %d outside 0..%d" % [npc_id, s.id, s.min_stage, stages.size()])
	var produced := {}
	for s: NpcArcStage in all_stages():
		if s == null:
			continue
		if s.journal_note.length() > JOURNAL_NOTE_MAX:
			errors.append("%s: stage %s journal note over %d chars" % [npc_id, s.id, JOURNAL_NOTE_MAX])
		if not s.beat_rules.is_empty():
			var last := s.beat_rules[s.beat_rules.size() - 1]
			if last and (not last.requires_flags.is_empty() or not last.forbids_flags.is_empty() or not last.requires_conditions.is_empty()):
				errors.append("%s: stage %s beat rules must end with an unconditional rule" % [npc_id, s.id])
		for r in s.beat_rules:
			if r == null or r.dialogue == null:
				errors.append("%s: stage %s beat rule without dialogue" % [npc_id, s.id])
				continue
			if not r.dialogue.set_flags.has(heard_flag(s.id)):
				errors.append("%s: beat %s must set %s (skipping still counts)" % [npc_id, r.dialogue.id, heard_flag(s.id)])
			_note_produced(r.dialogue, produced)
		for r in s.idle_rules:
			if r == null or r.dialogue == null:
				errors.append("%s: stage %s idle rule without dialogue" % [npc_id, s.id])
				continue
			if not r.dialogue.set_flags.is_empty() or not r.dialogue.choices.is_empty():
				errors.append("%s: idle %s must set nothing and offer no choice" % [npc_id, r.dialogue.id])
	for d in dialogues():
		if d.give_scrap != 0 or d.give_circuit != "" or d.give_weapon != "":
			errors.append("%s: dialogue %s gives items (arcs are economy-neutral, D-122)" % [npc_id, d.id])
	for t in threads:
		if not produced.has(t):
			errors.append("%s: thread %s is not set by any beat or choice" % [npc_id, t])
	return errors


func _note_produced(d: DialogueData, into: Dictionary) -> void:
	for f in d.set_flags:
		into[f] = true
	for c in d.choices:
		if c:
			for f in c.set_flags:
				into[f] = true


## ContentValidator resource protocol: stage flags, the index flag and every
## beat/idle/choice flag are produced; rule flags and stage conditions are read.
func content_flags() -> Dictionary:
	var produces: Array[String] = [index_flag()]
	var consumes: Array[String] = []
	var conditions: Array[String] = []
	for s: NpcArcStage in all_stages():
		if s == null:
			continue
		produces.append(stage_flag(s.id))
		produces.append_array(Array(s.set_flags))
		conditions.append_array(Array(s.enter_all))
		conditions.append_array(Array(s.enter_any))
		for r: NpcDialogueRule in s.beat_rules + s.idle_rules:
			if r == null:
				continue
			consumes.append_array(Array(r.requires_flags))
			consumes.append_array(Array(r.forbids_flags))
			conditions.append_array(Array(r.requires_conditions))
			if r.dialogue:
				var p := {}
				_note_produced(r.dialogue, p)
				for f: String in p:
					produces.append(f)
	return {"produces": produces, "consumes": consumes, "conditions": conditions}


## Cross-file rules: exactly one owning profile (npc_id matches), speakers
## are "" or the owner, a shopkeeper's beats and idles open their shop
## (choice beats exempt), every embedded dialogue passes its own validate()
## (the validator only validates top-level resources), and every open_menu
## is a known menu or shop.
func content_check() -> PackedStringArray:
	var errors := PackedStringArray()
	var owner := lint_owner
	if owner == null:
		var owners := _owners()
		if owners.size() != 1:
			errors.append("arc %s must be owned by exactly one NpcProfile (found %d)" % [npc_id, owners.size()])
		else:
			owner = owners[0]
	if owner and owner.npc_id != npc_id:
		errors.append("arc %s is owned by profile %s (npc_id mismatch)" % [npc_id, owner.npc_id])
	var shop := StringName()
	if owner and not owner.rules.is_empty():
		var fb := owner.rules[owner.rules.size() - 1]
		if fb and fb.dialogue:
			shop = fb.dialogue.open_menu
	for d in dialogues():
		for e: String in d.validate():
			errors.append("%s: %s" % [d.id, e])
		if owner:
			var lines: Array[DialogueLine] = d.lines.duplicate()
			for c in d.choices:
				if c:
					lines.append_array(c.reply)
			for l in lines:
				if l.speaker != "" and l.speaker != owner.display_name:
					errors.append("%s: speaker '%s' is not %s" % [d.id, l.speaker, owner.display_name])
			if shop != &"" and d.choices.is_empty() and d.open_menu != shop:
				errors.append("%s: %s's arc lines must open %s like the fallback (a beat never costs a shop visit)" % [d.id, owner.display_name, shop])
		var menu := String(d.open_menu)
		if menu != "" and not ContentValidator.MENU_IDS.has(menu) and not ResourceLoader.exists("res://data/shops/%s.tres" % menu):
			errors.append("%s: opens unknown menu '%s'" % [d.id, menu])
	return errors


func _owners() -> Array[NpcProfile]:
	var out: Array[NpcProfile] = []
	for path in DataDir.list(NPC_DIR):
		var p := load(path) as NpcProfile
		if p and p.arc == self:
			out.append(p)
	return out
