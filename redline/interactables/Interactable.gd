@tool
class_name Interactable
extends Area2D
## Something Rook can use with the interact button (bible §22): anchors,
## NPCs, switches, doors. The PlayerInteractor picks the nearest enabled one
## and shows its prompt; subclasses implement interact().

@export var size: Vector2 = Vector2(24, 32):
	set(v):
		size = v
		_rebuild()
## Verb shown in the prompt, e.g. "Rest", "Talk", "Use".
@export var prompt_verb: String = "Use"

var _shape_node: CollisionShape2D


func _ready() -> void:
	monitoring = false
	monitorable = true
	collision_layer = CombatLayers.INTERACT
	collision_mask = 0
	_rebuild()


## Origin is bottom-centre (like characters), so markers sit on the floor.
func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _shape_node == null:
		_shape_node = CollisionShape2D.new()
		add_child(_shape_node)
	var rect := RectangleShape2D.new()
	rect.size = size
	_shape_node.shape = rect
	_shape_node.position = Vector2(0, -size.y * 0.5)
	queue_redraw()


func can_interact(_player: Player) -> bool:
	return true


func prompt_text() -> String:
	return prompt_verb


func interact(_player: Player) -> void:
	pass
