class_name EncounterDirector
extends Node
## Limits how many enemies may attack at once so fights stay readable
## (bible §32). Enemies must hold a token to start a wind-up.

@export var max_attackers: int = 2

var _holders: Array[Node] = []


func _ready() -> void:
	add_to_group(&"encounter_director")


func request_token(enemy: Node) -> bool:
	_prune()
	if _holders.has(enemy):
		return true
	if _holders.size() >= max_attackers:
		return false
	_holders.append(enemy)
	return true


func release_token(enemy: Node) -> void:
	_holders.erase(enemy)


func active_attackers() -> int:
	_prune()
	return _holders.size()


func _prune() -> void:
	_holders.assign(_holders.filter(func(e: Node) -> bool: return is_instance_valid(e) and not e.is_queued_for_deletion()))
