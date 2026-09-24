class_name MoveHover
extends MoveModule
## Flying: hold a spot beside and above the target, bobbing (Scout Drone).

@export var hover_offset: Vector2 = Vector2(96, -70)
@export var bob_amplitude: float = 6.0
@export var bob_speed: float = 3.0


func engage_velocity(b: ModularBehavior, delta: float) -> Vector2:
	var t: float = b.mem(self, "t", 0.0) + delta
	b.remember(self, "t", t)
	b.face_target()
	var e := b.enemy
	var side := signf(e.global_position.x - e.target.global_position.x)
	if is_zero_approx(side):
		side = 1.0
	var goal := e.target.global_position + Vector2(side * hover_offset.x, hover_offset.y + sin(t * bob_speed) * bob_amplitude)
	var to := goal - e.global_position
	return to.normalized() * minf(e.data.move_speed, to.length() * 3.0)
