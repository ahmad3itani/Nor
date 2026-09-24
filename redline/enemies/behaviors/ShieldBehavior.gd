extends EnemyBehavior
## Shield: armored bruiser with a frontal guard. Hits from the front are
## blocked unless they break guards (heavy, air heavy), come from above,
## or land while it's staggered/launched. It turns slowly, so dodging or
## jumping past it opens its back (teaches positioning, bible §23 "one concept").

@export var turn_delay: float = 0.5
@export var attack_range: float = 36.0
@export var shield_color: Color = Color("7fb6d9")

var _behind_time: float = 0.0


func engage_velocity(delta: float) -> Vector2:
	var dx := enemy.target.global_position.x - enemy.global_position.x
	var side := int(signf(dx)) if absf(dx) > 2.0 else enemy.facing
	if side != enemy.facing:
		_behind_time += delta
		if _behind_time >= turn_delay:
			enemy.facing = side
			_behind_time = 0.0
		return Vector2.ZERO
	_behind_time = 0.0
	if absf(dx) > attack_range - 8.0:
		return Vector2(enemy.facing * enemy.data.move_speed, 0.0)
	return Vector2.ZERO


func choose_attack() -> AttackData:
	var dx := enemy.target.global_position.x - enemy.global_position.x
	if signf(dx) == enemy.facing and distance_to_target() <= attack_range:
		return enemy.data.attacks[0]
	return null


func guard_up() -> bool:
	return enemy.ai != Enemy.AI.STAGGER and enemy.ai != Enemy.AI.LAUNCHED and not enemy.is_dead()


func blocks(hit: HitInfo) -> bool:
	if not guard_up() or hit.attack.breaks_guard or hit.has_tag(&"environmental"):
		return false
	var from := hit.source_position
	# Attacks from clearly above the shield's top edge go over the guard.
	if from.y < enemy.global_position.y - enemy.data.body_size.y - 6.0:
		return false
	var incoming_side := signf(from.x - enemy.global_position.x)
	return incoming_side == enemy.facing or is_zero_approx(incoming_side)


func draw_extras(canvas: Node2D) -> void:
	if not guard_up():
		return
	var h := enemy.data.body_size.y
	var x := enemy.data.body_size.x * 0.5 if enemy.facing > 0 else -enemy.data.body_size.x * 0.5 - 4.0
	canvas.draw_rect(Rect2(x, -h + 2.0, 4.0, h - 4.0), shield_color)
