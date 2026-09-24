@tool
class_name RoomExit
extends Area2D
## Edge/doorway trigger that moves Rook to another room's entry marker,
## carrying velocity and facing (speed survives the cut). Origin: top-left.

@export var size: Vector2 = Vector2(16, 64):
	set(v):
		size = v
		_rebuild()
@export_file("*.tscn") var target_room: String = ""
@export var target_entry: StringName = &""
## Optional: exit only works once this flag is set (e.g. a shortcut unlocked from the far side).
@export var requires_flag: String = ""

var _shape_node: CollisionShape2D


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = CombatLayers.PLAYER_BODY
	_rebuild()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)


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


func is_open() -> bool:
	return requires_flag == "" or Game.has_flag(requires_flag)


func _on_body_entered(body: Node2D) -> void:
	var player := body as Player
	if player == null or player.combat.dead or not is_open() or target_room == "":
		return
	SceneRouter.transition_to(target_room, target_entry, {"velocity": player.velocity, "facing": player.facing})


func _draw() -> void:
	if Engine.is_editor_hint():
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.3, 0.8, 1.0, 0.25))
