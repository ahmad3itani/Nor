class_name CombatResult
extends RefCounted
## Outcome of delivering a hit to a receiver. Style, reactor and feedback
## systems branch on this, so every receiver must return one.

enum { IGNORED, BLOCKED, HIT, KILLED, EVADED, PERFECT_EVADE }


static func name_of(result: int) -> String:
	return ["ignored", "blocked", "hit", "killed", "evaded", "perfect_evade"][result]
