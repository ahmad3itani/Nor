extends EnemyBehavior
## Hopper: squats (telegraph), then leaps at you in an arc. Teaches dodging
## under/through and punishing the landing. Keeps a little distance.

@export var preferred_distance: float = 70.0
@export var leap_range: float = 130.0


func engage_velocity(_delta: float) -> Vector2:
	face_target()
	var dx := enemy.target.global_position.x - enemy.global_position.x
	if absf(dx) > preferred_distance:
		return Vector2(signf(dx) * enemy.data.move_speed, 0.0)
	if absf(dx) < preferred_distance * 0.5:
		return Vector2(-signf(dx) * enemy.data.move_speed * 0.6, 0.0)
	return Vector2.ZERO


func choose_attack() -> AttackData:
	if enemy.is_on_floor() and distance_to_target() <= leap_range:
		face_target()
		return enemy.data.attacks[0]
	return null


func draw_extras(canvas: Node2D) -> void:
	# Spring legs read as "jumper" at a glance; they compress during the wind-up.
	var squat := 3.0 if enemy.ai == Enemy.AI.WINDUP else 0.0
	var w := enemy.data.body_size.x
	canvas.draw_rect(Rect2(-w * 0.5 - 2, -3 + squat, 3, 3), Color("d9d4e6"))
	canvas.draw_rect(Rect2(w * 0.5 - 1, -3 + squat, 3, 3), Color("d9d4e6"))
