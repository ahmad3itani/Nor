class_name GuardModule
extends Resource
## Defense: decides whether a hit is stopped (bible §32 "shield").

## Presentation (T05): this block is about to break the guard (the enemy's
## poise runs out on it, so Enemy.receive_hit falls through to a stagger).
## Modules are shared resources, so the enemy rides along; EnemyVisual
## listens and plays guard_break. Visual only: nothing gameplay listens.
signal guard_broken(enemy: Enemy)


## Emits guard_broken when this block will empty the enemy's poise (the same
## rule Enemy.receive_hit applies: half poise damage on a block).
func note_block(b: ModularBehavior, hit: HitInfo) -> void:
	var e := b.enemy
	if e.poise - e._poise_damage_of(hit) * 0.5 <= 0.0:
		guard_broken.emit(e)


func guard_up(_b: ModularBehavior) -> bool:
	return false


func blocks(_b: ModularBehavior, _hit: HitInfo) -> bool:
	return false
