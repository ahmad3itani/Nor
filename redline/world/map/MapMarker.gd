@tool
class_name MapMarker
extends Node2D
## Something the map should show that other nodes don't already imply
## (bible §20 "unresolved gate symbols"): e.g. a gap only Dash can cross.
## The symbol disappears once `resolved_when` holds (see Game.check_condition).

enum Kind { ABILITY_GATE, LANDMARK }

@export var kind: Kind = Kind.ABILITY_GATE
@export var label: String = ""
@export var resolved_when: String = ""


func _draw() -> void:
	if Engine.is_editor_hint():
		draw_circle(Vector2.ZERO, 6.0, Color(0.4, 0.8, 1.0, 0.5))
