class_name Hurtbox
extends Area2D
## Marks a region that can receive hits and forwards them to its receiver
## (parent by default), which must implement `receive_hit(hit: HitInfo) -> int`.
## Hurtboxes are passive: attackers find them with shape/ray queries, which is
## deterministic within the tick (no Area2D overlap signal latency).

@export var receiver: Node


func _ready() -> void:
	monitoring = false
	monitorable = true
	collision_mask = 0
	if receiver == null:
		receiver = get_parent()


func receive(hit: HitInfo) -> int:
	return receiver.receive_hit(hit)


func owner_entity() -> Node2D:
	return receiver as Node2D
