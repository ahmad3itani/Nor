@tool
class_name Gate
extends StaticBody2D
## Solid barrier that opens/closes (boss arenas) or opens for good when a
## flag is set (shortcuts). Origin: top-left.

@export var size: Vector2 = Vector2(16, 64):
	set(v):
		size = v
		_rebuild()
@export var closed: bool = false:
	set(v):
		closed = v
		_apply()
## If set, the gate stays open once this flag is true (e.g. a shortcut lever).
@export var open_flag: String = ""

var _shape_node: CollisionShape2D


func _ready() -> void:
	collision_layer = CombatLayers.WORLD
	collision_mask = 0
	_rebuild()
	if not Engine.is_editor_hint() and open_flag != "":
		if Game.has_flag(open_flag):
			closed = false
		EventBus.flag_changed.connect(func(id: String, _v: Variant) -> void:
			if id == open_flag and Game.has_flag(open_flag):
				set_closed(false))


func set_closed(value: bool) -> void:
	if value == closed:
		return
	closed = value
	AudioManager.play_sfx(&"gate")
	EventBus.camera_shake_requested.emit(0.1)


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
	_apply()


func _apply() -> void:
	if _shape_node:
		_shape_node.set_deferred(&"disabled", not closed)
	queue_redraw()


func _draw() -> void:
	if not closed:
		draw_rect(Rect2(0, size.y - 3, size.x, 3), Color("4a4458"))
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("2d2838"))
	var x := 2.0
	while x < size.x:
		draw_rect(Rect2(x, 0, 2, size.y), Color("e8283c", 0.6))
		x += 5.0
