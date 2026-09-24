@tool
class_name FlowZone
extends Area2D
## Authored combat/Flow sector (bible §6): the Redline Core only drains while
## the player is inside one. Outside = safe exploration, no pressure.
## Origin is the top-left corner.

@export var size: Vector2 = Vector2(320, 200):
	set(v):
		size = v.snapped(Vector2.ONE)
		_rebuild()
@export var label: String = "FLOW ZONE"
## Shown the first time the player ever enters any Flow Zone (onboarding).
@export var first_entry_hint: String = "HOSTILE ZONE  —  your Core drains here. Fight and move to refill it."

var _shape_node: CollisionShape2D


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = CombatLayers.PLAYER_BODY
	_rebuild()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)


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


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		(body as Player).reactor.enter_flow()
		if first_entry_hint != "" and not Game.has_flag("hint_first_flow"):
			Game.set_flag("hint_first_flow")
			EventBus.hint_requested.emit(first_entry_hint, 4.0)


func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		(body as Player).reactor.exit_flow()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.91, 0.16, 0.24, 0.05))
	# Dashed top edge reads as a "sector boundary" without hiding geometry.
	var x := 0.0
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(minf(x + 6.0, size.x), 0), Color(0.91, 0.16, 0.24, 0.5), 1.0)
		x += 10.0
