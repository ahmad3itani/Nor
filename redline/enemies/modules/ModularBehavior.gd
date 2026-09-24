class_name ModularBehavior
extends EnemyBehavior
## Runs an EnemyBrain (the enemy data's `brain`, or `brain_override`). New
## enemies are data: an EnemyData with a brain made of existing modules, and
## a copy of a variant scene. Code is only needed for a genuinely new module.

@export var brain_override: EnemyBrain

## Per-enemy module memory: module -> {key: value}. Modules are shared
## resources, so anything that changes over time lives here.
var _mem: Dictionary = {}


func brain() -> EnemyBrain:
	return brain_override if brain_override else enemy.data.brain


func mem(module: Resource, key: String, default: Variant) -> Variant:
	return (_mem.get(module, {}) as Dictionary).get(key, default)


func remember(module: Resource, key: String, value: Variant) -> void:
	if not _mem.has(module):
		_mem[module] = {}
	(_mem[module] as Dictionary)[key] = value


func engage_velocity(delta: float) -> Vector2:
	var b := brain()
	return b.movement.engage_velocity(self, delta) if b and b.movement else Vector2.ZERO


func choose_attack() -> AttackData:
	var b := brain()
	if b == null:
		return null
	for rule in b.attacks:
		var a := rule.choose(self)
		if a:
			return a
	return null


func blocks(hit: HitInfo) -> bool:
	var b := brain()
	return b != null and b.guard != null and b.guard.blocks(self, hit)


func draw_extras(canvas: Node2D) -> void:
	var b := brain()
	if b == null:
		return
	for look in b.looks:
		look.draw(self, canvas)
