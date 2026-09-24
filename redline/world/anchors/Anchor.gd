@tool
class_name Anchor
extends Interactable
## Anchor (bible §7): rest to refill health, injectors and core, bank Scrap,
## set the respawn point and save. Opens the loadout menu (Circuits, weapons).
## The spawn marker with the same id must exist in the room (Room validates).

const CORE_COLOR := Color("e8283c")

@export var anchor_id: StringName = &"anchor"

var _pulse: float = 0.0


func _ready() -> void:
	prompt_verb = "Rest"
	super._ready()


func _process(delta: float) -> void:
	_pulse += delta
	queue_redraw()


func is_active_respawn() -> bool:
	if Engine.is_editor_hint():
		return false
	return Game.state.last_anchor_id == String(anchor_id) and Game.state.last_anchor_room == SceneRouter.current_room_path


func interact(player: Player) -> void:
	Game.rest_at_anchor(SceneRouter.current_room_path, String(anchor_id))
	player.combat.rest()
	player.reactor.charge = player.reactor.config.max_charge
	AudioManager.play_sfx(&"anchor")
	HitSpark.spawn(get_parent(), global_position + Vector2(0, -20), Vector2.UP, CORE_COLOR, 18, 120.0)
	EventBus.anchor_rested.emit(self)
	EventBus.menu_requested.emit(&"loadout")


func _draw() -> void:
	# Pedestal + floating core; brighter when it is the current respawn point.
	draw_rect(Rect2(-7, -6, 14, 6), Color("4a4458"))
	draw_rect(Rect2(-3, -22, 6, 16), Color("6b6380"))
	var glow := 0.55 + 0.45 * sin(_pulse * 3.0)
	var c := CORE_COLOR
	c.a = 0.5 + 0.5 * glow if is_active_respawn() else 0.35
	draw_rect(Rect2(-4, -34 + sin(_pulse * 2.0), 8, 8), c)
