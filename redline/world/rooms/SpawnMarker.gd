@tool
class_name SpawnMarker
extends Marker2D
## Where the player (re)appears. Rooms collect these; the reset hotkey returns
## to the active one and devtools can cycle through them (teleport).

@export var spawn_id: StringName = &"start"
@export var is_default: bool = false
@export_enum("Right:1", "Left:-1") var facing: int = 1
## Shown in the debug overlay so testers know which station they're at.
@export var label: String = ""


func _ready() -> void:
	add_to_group(&"spawn_markers")
	gizmo_extents = 8.0


func _draw() -> void:
	if Engine.is_editor_hint():
		draw_rect(Rect2(-6, -34, 12, 34), Color(0.3, 1.0, 0.5, 0.35))
