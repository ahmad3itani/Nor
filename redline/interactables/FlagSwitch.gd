@tool
class_name FlagSwitch
extends Interactable
## One-way switch that sets a flag (shortcut levers, lifts).

@export var flag_id: String = ""
@export var used_text: String = ""


func _ready() -> void:
	prompt_verb = "Pull lever"
	super._ready()


func can_interact(_player: Player) -> bool:
	return not Engine.is_editor_hint() and not Game.has_flag(flag_id)


func interact(_player: Player) -> void:
	Game.set_flag(flag_id)
	AudioManager.play_sfx(&"gate")
	if used_text != "":
		EventBus.hint_requested.emit(used_text, 3.0)
	queue_redraw()


func _draw() -> void:
	var on := not Engine.is_editor_hint() and Game.has_flag(flag_id)
	draw_rect(Rect2(-6, -6, 12, 6), Color("4a4458"))
	var tip := Vector2(6, -20) if on else Vector2(-6, -20)
	draw_line(Vector2(0, -6), tip, Color("c9c3d6"), 2.0)
	draw_rect(Rect2(tip - Vector2(2, 2), Vector2(4, 4)), Color("7dff9a") if on else Color("e8283c"))
