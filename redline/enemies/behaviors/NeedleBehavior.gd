extends EnemyBehavior
## Needle: light melee grunt. Walks in, telegraphs, lunges with a stab.
## Light and launchable: the enemy that teaches combos and launchers.

## Stops approaching inside this distance.
@export var keep_distance: float = 24.0
@export var attack_range: float = 42.0
@export var max_height_difference: float = 28.0


func engage_velocity(_delta: float) -> Vector2:
	face_target()
	var dx := enemy.target.global_position.x - enemy.global_position.x
	if absf(dx) > keep_distance:
		return Vector2(signf(dx) * enemy.data.move_speed, 0.0)
	return Vector2.ZERO


func choose_attack() -> AttackData:
	var dy := absf(enemy.target.global_position.y - enemy.global_position.y)
	if distance_to_target() <= attack_range and dy <= max_height_difference:
		face_target()
		return enemy.data.attacks[0]
	return null
