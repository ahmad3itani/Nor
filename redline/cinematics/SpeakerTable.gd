class_name SpeakerTable
extends Resource
## Voices in scripted lines that are not NPCs (the ward PA, C-00, Krail, the
## city band). SeqLine.speaker_id resolves an NpcProfile.npc_id first (its
## display_name and color), then this table; "" is narration (no label).
## The label carries the speaker (§24 colorblind-safe): color is secondary.

const PATH := "res://data/sequences/speakers.tres"
const NPC_DIR := "res://data/npcs"

@export var ids: PackedStringArray = []
@export var labels: PackedStringArray = []
@export var colors: PackedColorArray = []

static var _shared: SpeakerTable = null
static var _npcs: Dictionary = {}
static var _npcs_loaded: bool = false


static func shared() -> SpeakerTable:
	if _shared == null:
		_shared = load(PATH) as SpeakerTable
		if _shared == null:
			_shared = SpeakerTable.new()
	return _shared


## {label, color, narration} for a speaker id, or {} when nobody has that id.
static func lookup(speaker_id: String) -> Dictionary:
	if speaker_id == "":
		return {"label": "", "color": Color.WHITE, "narration": true}
	var npc := npc_profile(speaker_id)
	if npc:
		return {"label": npc.display_name, "color": npc.color, "narration": false}
	var t := shared()
	var i := t.ids.find(speaker_id)
	if i < 0:
		return {}
	return {"label": t.labels[i], "color": t.colors[i] if i < t.colors.size() else Color.WHITE, "narration": false}


static func exists(speaker_id: String) -> bool:
	return not lookup(speaker_id).is_empty()


## NpcProfile by npc_id under data/npcs (DataDir: exported builds list
## .tres.remap files).
static func npc_profile(npc_id: String) -> NpcProfile:
	if not _npcs_loaded:
		_npcs_loaded = true
		for path in DataDir.list(NPC_DIR):
			var p := load(path) as NpcProfile
			if p and p.npc_id != "":
				_npcs[p.npc_id] = p
	return _npcs.get(npc_id) as NpcProfile


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if labels.size() != ids.size() or colors.size() != ids.size():
		errors.append("speakers: ids, labels and colors must have the same length")
	var seen := {}
	for i in ids.size():
		var id := ids[i]
		if id == "":
			errors.append("speakers: empty id at %d" % i)
		elif seen.has(id):
			errors.append("speakers: duplicate id '%s'" % id)
		seen[id] = true
		if i < labels.size() and labels[i].strip_edges() == "":
			errors.append("speakers: '%s' has an empty label" % id)
	return errors
