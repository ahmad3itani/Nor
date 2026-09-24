class_name PlayerInteractor
extends Node
## Finds the nearest usable Interactable overlapping Rook, publishes its
## prompt, and triggers it on the interact button.

var current: Interactable
var _last_prompt: String = ""

@onready var player: Player = get_parent()


func tick(input: PlayerInputFrame) -> void:
	current = _find()
	var prompt := current.prompt_text() if current else ""
	if prompt != _last_prompt:
		_last_prompt = prompt
		EventBus.interact_prompt_changed.emit(prompt)
	if current and input.interact_pressed and _can_act():
		current.interact(player)


func _can_act() -> bool:
	var state := player.current_state_id()
	return not player.combat.dead and state != &"hurt" and state != &"melee"


func _find() -> Interactable:
	var size := player.config.standing_size
	var rect := Rect2(player.global_position - Vector2(size.x * 0.5, size.y), size)
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, rect.get_center())
	params.collision_mask = CombatLayers.INTERACT
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var best: Interactable
	var best_d := INF
	for hit in player.get_world_2d().direct_space_state.intersect_shape(params, 8):
		var it := hit["collider"] as Interactable
		if it == null or not it.can_interact(player):
			continue
		var d := it.global_position.distance_squared_to(player.global_position)
		if d < best_d:
			best_d = d
			best = it
	return best
