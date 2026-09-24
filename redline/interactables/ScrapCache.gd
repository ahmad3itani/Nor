class_name ScrapCache
extends Area2D
## The Scrap Rook dropped on death (bible §7). Touch it to recover everything.

var _t: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = CombatLayers.PLAYER_BODY
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 20)
	shape.shape = rect
	shape.position = Vector2(0, -10)
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if not body is Player:
		return
	var amount := Game.recover_dropped_scrap()
	AudioManager.play_sfx(&"scrap_recover")
	HitSpark.spawn(get_parent(), global_position + Vector2(0, -10), Vector2.UP, Color("ffd36b"), 16, 100.0)
	EventBus.hint_requested.emit("Recovered %d Scrap" % amount, 2.0)
	queue_free()


func _draw() -> void:
	var bob := sin(_t * 3.0) * 2.0
	for i in 5:
		var a := _t * 1.5 + i * TAU / 5.0
		draw_rect(Rect2(Vector2(cos(a) * 5.0 - 1.5, -12.0 + sin(a) * 3.0 + bob), Vector2(3, 3)), Color("ffd36b"))
	draw_rect(Rect2(-2, -14 + bob, 4, 4), Color("e8283c"))
