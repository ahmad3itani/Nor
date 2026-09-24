extends EnemyBehavior
## Watcher: fixed sentry eye on walls/ceilings. Long, obvious aim line, then a
## fast bolt. Only fires with line of sight: breaking sight is the counterplay.

@export var fire_range: float = 300.0


func engage_velocity(_delta: float) -> Vector2:
	face_target()
	return Vector2.ZERO


func choose_attack() -> AttackData:
	if distance_to_target() <= fire_range and enemy.has_line_of_sight():
		return enemy.data.attacks[0]
	return null


func draw_extras(canvas: Node2D) -> void:
	# Eye that tracks the target.
	var c := Vector2(0, -enemy.data.body_size.y * 0.5)
	var look := (enemy.target.global_position + Vector2(0, -16) - enemy.global_position - c).normalized() * 2.0 if enemy.target else Vector2.ZERO
	canvas.draw_rect(Rect2(c + look - Vector2(2, 2), Vector2(4, 4)), Color("ff3b4f"))
