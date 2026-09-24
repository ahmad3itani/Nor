class_name AttackRule
extends Resource
## "Use attack N when ..." (bible §32 attack selection + preferred range).
## A brain checks its rules in order; the first one whose conditions hold
## starts its attack.

@export var attack_index: int = 0
@export var min_range: float = 0.0
@export var max_range: float = 40.0
## Max vertical distance to the target (px); negative = no limit.
@export var max_height_difference: float = -1.0
@export var needs_line_of_sight: bool = false
@export var needs_floor: bool = false
## Only when the target is on the side the enemy faces (slow turners).
@export var needs_target_in_front: bool = false
## Snap to face the target when the attack starts.
@export var face_target: bool = true


func choose(b: ModularBehavior) -> AttackData:
	var e := b.enemy
	var d := b.distance_to_target()
	if d > max_range or d < min_range:
		return null
	if max_height_difference >= 0.0 and absf(e.target.global_position.y - e.global_position.y) > max_height_difference:
		return null
	if needs_floor and not e.is_on_floor():
		return null
	if needs_target_in_front and signf(e.target.global_position.x - e.global_position.x) != e.facing:
		return null
	if needs_line_of_sight and not e.has_line_of_sight():
		return null
	if face_target:
		b.face_target()
	return e.data.attacks[attack_index]
