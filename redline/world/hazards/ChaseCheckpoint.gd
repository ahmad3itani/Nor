@tool
class_name ChaseCheckpoint
extends Marker2D
## A chase restart point (M7). Child of a ChaseDirector, placed bottom-centre
## on the floor (a block top, >= 20 px from its edges: the director's content
## lint checks). After a catch or a chase pit, Rook restarts at the highest
## checkpoint he has passed. CP1 (the first child) is index 0 and counts as
## reached from the moment the chase arms.
##
## The node itself is only a position; all behaviour lives in the director.

const COLOR := Color(1.0, 0.81, 0.35, 0.8)


func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	# Authoring view only: a small flag on the floor.
	if not Engine.is_editor_hint():
		return
	draw_line(Vector2.ZERO, Vector2(0, -20), COLOR, 1.0)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -20), Vector2(8, -16), Vector2(0, -12)]), COLOR)
