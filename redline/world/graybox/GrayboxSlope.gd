@tool
class_name GrayboxSlope
extends StaticBody2D
## Right-triangle slope. rise > 0 climbs to the right, rise < 0 descends.
## Origin is the bottom-left corner of the triangle's bounding box.

@export var run: float = 96.0:
	set(v):
		run = v
		_rebuild()
@export var rise: float = 48.0:
	set(v):
		rise = v
		_rebuild()

var _poly_node: CollisionPolygon2D


func _ready() -> void:
	_rebuild()


func _points() -> PackedVector2Array:
	if rise >= 0.0:
		return PackedVector2Array([Vector2(0, 0), Vector2(run, -rise), Vector2(run, 0)])
	return PackedVector2Array([Vector2(0, 0), Vector2(0, rise), Vector2(run, 0)])


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _poly_node == null:
		_poly_node = CollisionPolygon2D.new()
		add_child(_poly_node)
	_poly_node.polygon = _points()
	collision_layer = 1
	collision_mask = 0
	queue_redraw()


func _draw() -> void:
	draw_colored_polygon(_points(), GrayboxBlock.COLOR_SOLID)
