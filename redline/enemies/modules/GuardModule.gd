class_name GuardModule
extends Resource
## Defense: decides whether a hit is stopped (bible §32 "shield").


func guard_up(_b: ModularBehavior) -> bool:
	return false


func blocks(_b: ModularBehavior, _hit: HitInfo) -> bool:
	return false
