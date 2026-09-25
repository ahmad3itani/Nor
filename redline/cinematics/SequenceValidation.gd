class_name SequenceValidation
extends RefCounted
## What a step's validate() sees: built once per view pass by
## SequenceData.content_check(). Steps return errors; the sequence tags them.

const ACTOR_IDS: PackedStringArray = ["@rook", "@camera", "@boss", "@arena"]
const NPC_PREFIX := "Interactables/NPC_"

var seq: SequenceData
## The sequence's room, instantiated (not in the tree), or null.
var room: Node
var first_view: bool = true
var speakers: SpeakerTable
var index: int = 0


## Actor rules: '@' ids, or "Interactables/NPC_<id>" for a data/npcs/<id>.tres
## profile (the stable names roomgen.npc() gives). Numbered generator names
## (Neon1, Decor22) shift on regeneration and post nodes (NPC_mara_door) are
## world-state copies, so both are refused. Paths must resolve in the room.
func actor_errors(actor: String) -> PackedStringArray:
	var out := PackedStringArray()
	if actor == "":
		out.append("no actor")
		return out
	if actor.begins_with("@"):
		if not ACTOR_IDS.has(actor):
			out.append("unknown actor id '%s'" % actor)
		elif (actor == "@boss" or actor == "@arena") and not _room_has_arena():
			out.append("%s needs a room with a BossArena" % actor)
		return out
	if not actor.begins_with(NPC_PREFIX):
		out.append("actor '%s' is not an '@' id or %s<id>" % [actor, NPC_PREFIX])
		return out
	var npc := actor.trim_prefix(NPC_PREFIX)
	if npc == "" or npc.contains("/") or not ResourceLoader.exists("res://data/npcs/%s.tres" % npc):
		out.append("actor '%s' names no data/npcs profile" % actor)
		return out
	if seq == null or seq.room == "":
		out.append("actor '%s' needs the sequence's room" % actor)
	elif room != null and room.get_node_or_null(NodePath(actor)) == null:
		out.append("actor '%s' not found in %s" % [actor, seq.room.get_file()])
	return out


func _room_has_arena() -> bool:
	if room == null:
		return false
	return not room.find_children("*", "BossArena", true, false).is_empty()
