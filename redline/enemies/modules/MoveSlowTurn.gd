class_name MoveSlowTurn
extends MoveModule
## Heavy units: turning around takes `turn_delay`, so getting behind them
## is a real opening (Shield). Advances until `approach_until`.

@export var turn_delay: float = 0.5
@export var approach_until: float = 28.0


func engage_velocity(b: ModularBehavior, delta: float) -> Vector2:
	var e := b.enemy
	var dx := e.target.global_position.x - e.global_position.x
	var side := int(signf(dx)) if absf(dx) > 2.0 else e.facing
	if side != e.facing:
		var behind: float = b.mem(self, "behind", 0.0) + delta
		if behind >= turn_delay:
			e.facing = side
			behind = 0.0
		b.remember(self, "behind", behind)
		return Vector2.ZERO
	b.remember(self, "behind", 0.0)
	if absf(dx) > approach_until:
		return Vector2(e.facing * e.data.move_speed, 0.0)
	return Vector2.ZERO
