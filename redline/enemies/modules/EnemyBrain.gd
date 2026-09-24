class_name EnemyBrain
extends Resource
## An enemy's decision-making assembled from reusable modules (bible §32:
## "composable modules: sensing, movement, attack selection, preferred range,
## shield ..."). One movement module, attack rules checked in order (first
## match wins), an optional guard and any number of look extras. Modules are
## stateless and shareable; per-enemy memory lives in ModularBehavior.

@export var movement: MoveModule
@export var attacks: Array[AttackRule] = []
@export var guard: GuardModule
@export var looks: Array[LookModule] = []


func validate_for(data: EnemyData) -> PackedStringArray:
	var errors := PackedStringArray()
	if movement == null:
		errors.append("%s: brain has no movement module" % data.id)
	if attacks.is_empty():
		errors.append("%s: brain has no attack rules" % data.id)
	for rule in attacks:
		if rule == null or rule.attack_index < 0 or rule.attack_index >= data.attacks.size():
			errors.append("%s: attack rule points at a missing attack" % data.id)
	return errors
