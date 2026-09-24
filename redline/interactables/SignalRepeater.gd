@tool
class_name SignalRepeater
extends Interactable
## Quest switch: realigning it sets `flag_id` (Orr's "Dead Air" quest).
## Reads as dead (grey, flickering) until aligned (steady cyan pulse).

@export var flag_id: String = ""

var _t: float = 0.0


func _ready() -> void:
	prompt_verb = "Realign repeater"
	super._ready()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func is_aligned() -> bool:
	return not Engine.is_editor_hint() and Game.has_flag(flag_id)


func can_interact(_player: Player) -> bool:
	return not is_aligned()


func interact(_player: Player) -> void:
	Game.set_flag(flag_id)
	AudioManager.play_sfx(&"repeater")
	HitSpark.spawn(get_parent(), global_position + Vector2(0, -30), Vector2.UP, Color("58e0e8"), 14, 90.0)


func _draw() -> void:
	draw_rect(Rect2(-2, -28, 4, 28), Color("4a4458"))
	draw_rect(Rect2(-7, -30, 14, 3), Color("6b6380"))
	var on := is_aligned()
	var c := Color("58e0e8") if on else Color("6b6380")
	if not on and fmod(_t, 1.3) < 0.08:
		c = Color("c9d6ff")
	c.a = 0.6 + 0.4 * sin(_t * 4.0) if on else 1.0
	draw_rect(Rect2(-3, -36, 6, 6), c)
