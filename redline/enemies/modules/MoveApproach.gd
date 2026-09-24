class_name MoveApproach
extends MoveModule
## Walk toward the target until `keep_distance`; optionally back off when
## closer than `retreat_within` (Hopper keeps room to leap).

@export var keep_distance: float = 24.0
@export var retreat_within: float = 0.0
@export var retreat_speed_scale: float = 0.6


func engage_velocity(b: ModularBehavior, _delta: float) -> Vector2:
	b.face_target()
	var dx := b.enemy.target.global_position.x - b.enemy.global_position.x
	if absf(dx) > keep_distance:
		return Vector2(signf(dx) * b.enemy.data.move_speed, 0.0)
	if retreat_within > 0.0 and absf(dx) < retreat_within:
		return Vector2(-signf(dx) * b.enemy.data.move_speed * retreat_speed_scale, 0.0)
	return Vector2.ZERO
