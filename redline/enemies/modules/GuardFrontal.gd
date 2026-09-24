class_name GuardFrontal
extends GuardModule
## Frontal shield: blocks hits from the side it faces unless they break
## guards, are environmental, come from clearly above, or land while the
## enemy is staggered/launched (Shield; teaches positioning).

@export var over_top_margin: float = 6.0


func guard_up(b: ModularBehavior) -> bool:
	var e := b.enemy
	return e.ai != Enemy.AI.STAGGER and e.ai != Enemy.AI.LAUNCHED and not e.is_dead()


func blocks(b: ModularBehavior, hit: HitInfo) -> bool:
	var e := b.enemy
	if not guard_up(b) or hit.attack.breaks_guard or hit.has_tag(&"environmental"):
		return false
	var from := hit.source_position
	if from.y < e.global_position.y - e.data.body_size.y - over_top_margin:
		return false
	var incoming_side := signf(from.x - e.global_position.x)
	return incoming_side == e.facing or is_zero_approx(incoming_side)
