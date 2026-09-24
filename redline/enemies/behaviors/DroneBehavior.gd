extends EnemyBehavior
## Scout Drone: flying ranged unit. Hovers above and to the side of the
## target, telegraphs with an aim line, fires a slow, dodgeable bolt.
## Teaches ranged weapons, air attacks and dodging projectiles.

@export var hover_offset: Vector2 = Vector2(96, -70)
@export var bob_amplitude: float = 6.0
@export var fire_range: float = 260.0

var _t: float = 0.0


func engage_velocity(delta: float) -> Vector2:
	_t += delta
	face_target()
	var side := signf(enemy.global_position.x - enemy.target.global_position.x)
	if is_zero_approx(side):
		side = 1.0
	var goal := enemy.target.global_position + Vector2(side * hover_offset.x, hover_offset.y + sin(_t * 3.0) * bob_amplitude)
	var to := goal - enemy.global_position
	return to.normalized() * minf(enemy.data.move_speed, to.length() * 3.0)


func choose_attack() -> AttackData:
	if distance_to_target() <= fire_range:
		return enemy.data.attacks[0]
	return null


func draw_extras(canvas: Node2D) -> void:
	# Rotor bar so the silhouette reads as "flying" at a glance.
	var w := enemy.data.body_size.x + 6.0
	canvas.draw_rect(Rect2(-w * 0.5, -enemy.data.body_size.y - 3.0, w, 1.0), Color("d9d4e6"))
