class_name AbilityPickup
extends Area2D
## Traversal unlock dropped by a boss (bible §15: Warden Krail -> Dash).
## Grants the ability, sets a flag, and teaches it in one short line.

@export var ability: StringName = &"dash"
@export var flag_id: String = "unlocked_dash"
@export var hint_text: String = "DASH UNLOCKED  —  press [%s] to dash"
@export var hint_action: StringName = &"dodge"

var _t: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = CombatLayers.PLAYER_BODY
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 20)
	shape.shape = rect
	shape.position = Vector2(0, -12)
	add_child(shape)
	if Game.has_flag(flag_id):
		queue_free()
		return
	body_entered.connect(_on_body_entered)


## ContentValidator protocol (a BossArena reward reports it too).
func content_flags() -> Dictionary:
	return {"produces": [flag_id]}


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if not body is Player:
		return
	Game.set_ability(ability, true)
	Game.set_flag(flag_id)
	AudioManager.play_sfx(&"ability_unlock")
	EventBus.camera_shake_requested.emit(0.3)
	HitSpark.spawn(get_parent(), global_position + Vector2(0, -12), Vector2.UP, Color("e8283c"), 24, 160.0)
	EventBus.hint_requested.emit(hint_text % InputGlyphs.label(hint_action), 5.0)
	queue_free()


func _draw() -> void:
	var bob := sin(_t * 3.0) * 3.0
	draw_rect(Rect2(-5, -20 + bob, 10, 10), Color("e8283c"))
	draw_rect(Rect2(-2, -17 + bob, 4, 4), Color.WHITE)
	draw_arc(Vector2(0, -15 + bob), 9.0 + sin(_t * 5.0), 0, TAU, 16, Color("e8283c", 0.5), 1.0)
