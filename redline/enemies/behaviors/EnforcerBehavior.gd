extends EnemyBehavior
## Enforcer (elite Needle): armored, two-hit baton combo up close, a long
## lunge from mid range. First "you must dodge twice" enemy.

@export var combo_range: float = 38.0
@export var lunge_range: float = 110.0


func engage_velocity(_delta: float) -> Vector2:
	face_target()
	var dx := enemy.target.global_position.x - enemy.global_position.x
	if absf(dx) > combo_range - 8.0:
		return Vector2(signf(dx) * enemy.data.move_speed, 0.0)
	return Vector2.ZERO


func choose_attack() -> AttackData:
	var d := distance_to_target()
	var dy := absf(enemy.target.global_position.y - enemy.global_position.y)
	if dy > 30.0:
		return null
	face_target()
	if d <= combo_range:
		return enemy.data.attacks[0]
	if d <= lunge_range:
		return enemy.data.attacks[1]
	return null
