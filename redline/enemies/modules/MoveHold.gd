class_name MoveHold
extends MoveModule
## Stay put and track the target (sentries, turrets).


func engage_velocity(b: ModularBehavior, _delta: float) -> Vector2:
	b.face_target()
	return Vector2.ZERO
