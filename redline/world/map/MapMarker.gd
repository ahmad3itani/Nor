@tool
class_name MapMarker
extends Node2D
## Something the map should show that other nodes don't already imply
## (bible §20 "unresolved gate symbols"): e.g. a gap only Dash can cross.
## The symbol disappears once `resolved_when` holds (see Game.check_condition).
##
## NOTE (M8) is the single map-note mechanism for rumours and arc hints: a
## short label shown while `shown_when` holds and until `resolved_when` does.
## Notes point at people and places, never at secrets (bible §20: the map
## says that something is left, never where), so the lint below keeps them
## away from fragments, shards and breakable walls.

enum Kind { ABILITY_GATE, LANDMARK, NOTE }

## A NOTE this close to a secret would give its position away.
const NOTE_SECRET_CLEARANCE := 96.0
const NOTE_LABEL_MAX := 40

@export var kind: Kind = Kind.ABILITY_GATE
@export var label: String = ""
@export var resolved_when: String = ""
## NOTE only: the note appears once this holds ("" = from the start).
@export var shown_when: String = ""


func _draw() -> void:
	if Engine.is_editor_hint():
		draw_circle(Vector2.ZERO, 6.0, Color(0.4, 0.8, 1.0, 0.5))


## resolved_when is read by the validator's MapMarker branch; shown_when here.
func content_flags() -> Dictionary:
	return {"conditions": [shown_when] if shown_when != "" else []}


func content_errors(room: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if kind != Kind.NOTE:
		return out
	if label.length() < 1 or label.length() > NOTE_LABEL_MAX:
		out.append("NOTE label must be 1..%d characters (has %d)" % [NOTE_LABEL_MAX, label.length()])
	var here := WorldMapIndex.local_pos(self, room)
	for n in room.find_children("*", "", true, false):
		var secret := n is BreakableWall or (n is Collectible and (n as Collectible).kind != Collectible.Kind.SCRAP_BUNDLE)
		if secret and WorldMapIndex.local_pos(n, room).distance_to(here) < NOTE_SECRET_CLEARANCE:
			out.append("NOTE '%s' is within %d px of secret %s (notes never say where)" % [label, int(NOTE_SECRET_CLEARANCE), n.name])
	return out
