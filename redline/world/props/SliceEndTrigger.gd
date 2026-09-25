@tool
class_name SliceEndTrigger
extends Area2D
## Shown once when the player returns to the Relay after beating Warden
## Krail: marks the end of Act I's Lowlight arc and points at the Dash gates.

@export var size: Vector2 = Vector2(200, 100)


func _ready() -> void:
	collision_layer = 0
	collision_mask = CombatLayers.PLAYER_BODY
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = size * 0.5
	add_child(shape)
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body is Player or not Game.has_flag("warden_krail_defeated") or Game.has_flag("slice_end_seen"):
		return
	Game.set_flag("slice_end_seen")
	EventBus.slice_completed.emit()
