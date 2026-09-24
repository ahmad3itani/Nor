class_name EnemyBehavior
extends Node
## Archetype-specific decisions for an Enemy (composition, bible §32). The
## shared Enemy body owns physics, health, stagger, launch and attack
## execution; a behavior only answers "where do I want to be?", "which attack
## now?" and "does my guard stop this hit?".

var enemy: Enemy


func setup(owner_enemy: Enemy) -> void:
	enemy = owner_enemy


## Called every physics tick in any state (phase checks, timers).
func tick(_delta: float) -> void:
	pass


## Desired velocity while engaging the target. Also responsible for facing.
func engage_velocity(_delta: float) -> Vector2:
	return Vector2.ZERO


## Attack to start now, or null. Called only when the attack cooldown is over.
func choose_attack() -> AttackData:
	return null


## Return true if this hit is stopped by a guard.
func blocks(_hit: HitInfo) -> bool:
	return false


## Optional extra drawing (shield plate, eye) on the enemy's visual.
func draw_extras(_canvas: Node2D) -> void:
	pass


func distance_to_target() -> float:
	if enemy.target == null:
		return INF
	return enemy.global_position.distance_to(enemy.target.global_position)


func face_target() -> void:
	if enemy.target:
		var dx := enemy.target.global_position.x - enemy.global_position.x
		if absf(dx) > 2.0:
			enemy.facing = int(signf(dx))
