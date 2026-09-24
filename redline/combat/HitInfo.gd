class_name HitInfo
extends RefCounted
## Everything a receiver needs to resolve one hit. Created by whoever delivers
## the hit (melee query, projectile, hazard, launched-body impact).

var attacker: Node2D
var attack: AttackData
## World-space knockback velocity before the receiver's mass is applied.
var knockback: Vector2
## World-space direction the hit travels (used for guards and effects).
var direction: Vector2 = Vector2.RIGHT
var source_position: Vector2
## Context tags for style/reactor: &"aerial", &"ranged", &"environmental",
## &"after_movement", &"launcher".
var tags: Array[StringName] = []


static func create(p_attacker: Node2D, p_attack: AttackData, p_knockback: Vector2,
		p_direction: Vector2, p_tags: Array[StringName] = []) -> HitInfo:
	var h := HitInfo.new()
	h.attacker = p_attacker
	h.attack = p_attack
	h.knockback = p_knockback
	h.direction = p_direction.normalized() if p_direction != Vector2.ZERO else Vector2.RIGHT
	h.source_position = p_attacker.global_position if p_attacker else Vector2.ZERO
	h.tags = p_tags.duplicate()
	return h


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)
