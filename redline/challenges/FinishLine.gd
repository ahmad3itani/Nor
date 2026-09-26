class_name FinishLine
extends Area2D
## Replaces a RoomExit at runtime in an EXIT challenge (M9 D2 §3.4): Challenges
## turns the exit's monitoring off and adds this with the same rect, so
## touching the door ends the run and the next room never loads. No RoomExit
## or room scene changes.

var size: Vector2 = Vector2(16, 64)
## Called once with no arguments when the player's body enters.
var on_reached: Callable
var _fired: bool = false


func _init(p_size: Vector2 = Vector2(16, 64), p_on_reached: Callable = Callable()) -> void:
	size = p_size
	on_reached = p_on_reached


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = CombatLayers.PLAYER_BODY
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = size * 0.5
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	var p := body as Player
	if _fired or p == null or p.combat.dead:
		return
	_fired = true
	if on_reached.is_valid():
		on_reached.call()


func _draw() -> void:
	# A thin checkered strip: the finish reads without colour (§24).
	var h := int(size.y / 4.0)
	for i in h:
		var c := Color(1, 1, 1, 0.55) if i % 2 == 0 else Color(0.05, 0.05, 0.08, 0.55)
		draw_rect(Rect2(size.x * 0.5 - 2.0, i * 4.0, 4.0, 4.0), c)
