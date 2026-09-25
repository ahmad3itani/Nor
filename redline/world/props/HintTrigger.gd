@tool
class_name HintTrigger
extends Area2D
## Shows a short contextual tip once (bible §42: short, contextual, taught by
## geometry first). `{action}` in the text becomes the player's binding.

@export var size: Vector2 = Vector2(48, 96)
@export var hint_id: String = ""
@export_multiline var text: String = ""
@export var action: StringName = &""
@export var seconds: float = 3.5
## Stays silent while this condition holds (Game.check_condition), e.g. a
## "bolted" door hint that is moot once the door is open. Not marked as shown,
## so it can still fire if the condition stops holding.
@export var skip_when: String = ""


func _ready() -> void:
	collision_layer = 0
	collision_mask = CombatLayers.PLAYER_BODY
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = size * 0.5
	add_child(shape)
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body is Player or Game.has_flag("hint_" + hint_id):
		return
	if skip_when != "" and Game.check_condition(skip_when):
		return
	Game.set_flag("hint_" + hint_id)
	var t := text
	if action != &"":
		t = t.replace("{action}", InputGlyphs.label(action))
	EventBus.hint_requested.emit(t, seconds)


## ContentValidator protocol: skip_when reads flags.
func content_flags() -> Dictionary:
	return {"conditions": [skip_when] if skip_when != "" else []}
