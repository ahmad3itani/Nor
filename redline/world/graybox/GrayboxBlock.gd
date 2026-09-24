@tool
class_name GrayboxBlock
extends StaticBody2D
## Rectangle of solid (or one-way) graybox geometry. Size is authored in the
## scene; the collision shape is rebuilt from it so the tscn stays pure data.
## Origin is the top-left corner, matching how level designers think in tiles.

const COLOR_SOLID := Color("3a3548")
const COLOR_EDGE := Color("6b6380")
const COLOR_ONE_WAY := Color("5c7a8a")

@export var size: Vector2 = Vector2(64, 16):
	set(v):
		size = v.snapped(Vector2.ONE)
		_rebuild()
@export var one_way: bool = false:
	set(v):
		one_way = v
		_rebuild()

var _shape_node: CollisionShape2D
var _theme: DistrictTheme


func _ready() -> void:
	var n := get_parent()
	while n and not _theme:
		if n is Room:
			_theme = (n as Room).theme
		n = n.get_parent()
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
	_shape_node.one_way_collision = one_way
	# Layer 1 = world, layer 3 = one-way (the player's stand check ignores one-way).
	collision_layer = 4 if one_way else 1
	collision_mask = 0
	queue_redraw()


func _draw() -> void:
	var solid := _theme.solid_color if _theme else COLOR_SOLID
	var edge := _theme.edge_color if _theme else COLOR_EDGE
	if one_way:
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, 3)), _theme.one_way_color if _theme else COLOR_ONE_WAY)
		return
	draw_rect(Rect2(Vector2.ZERO, size), solid)
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, 1)), edge)
	if _theme and size.y > 24.0:
		# Subtle vertical banding: reads as masonry/concrete rather than a flat box.
		var x := 8.0
		while x < size.x:
			draw_rect(Rect2(x, 2, 1, size.y - 2), solid.darkened(0.12))
			x += 24.0
