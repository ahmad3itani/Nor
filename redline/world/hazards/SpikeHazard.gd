@tool
class_name SpikeHazard
extends Area2D
## Spikes: kill enemies outright (environmental kill), hurt the player and
## bounce them out (bible §8, §22 environmental weapons). Origin is the
## top-left corner, like GrayboxBlock.

const COLOR := Color("b8b2c8")

@export var size: Vector2 = Vector2(64, 8):
	set(v):
		size = v.snapped(Vector2.ONE)
		_rebuild()

var _shape_node: CollisionShape2D


func _ready() -> void:
	monitoring = false
	monitorable = true
	collision_layer = CombatLayers.HAZARD
	collision_mask = 0
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _shape_node == null:
		_shape_node = CollisionShape2D.new()
		add_child(_shape_node)
	var rect := RectangleShape2D.new()
	rect.size = size
	_shape_node.shape = rect
	_shape_node.position = size * 0.5
	queue_redraw()


func _draw() -> void:
	var tooth := 6.0
	var x := 0.0
	while x < size.x:
		var w := minf(tooth, size.x - x)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, size.y), Vector2(x + w * 0.5, 0.0), Vector2(x + w, size.y)]), COLOR)
		x += tooth
