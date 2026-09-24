class_name ClampTiming
extends Resource
## Cycle of a GridClamp (M7 Warden Krail boss test, D-071). Seconds.

## Telegraph from the breaker hit to the drop (lamps count down, the floor
## stripe pulses). Never shorter than the 0.3 s telegraph floor.
@export var warn: float = 1.0
## The slab falls from its raised bottom to the 24 px slot.
@export var drop: float = 0.15
## Down: a low Rook fits under it; whatever else stood there was hit.
@export var hold: float = 1.0
## Back up to the raised bottom.
@export var rise: float = 0.5
## Seconds from the breaker hit until the clamp can be tripped again: one
## drop per `rearm`, so it is a punish tool, not a loop. The breaker lamps
## show the recharge.
@export var rearm: float = 8.0


func cycle() -> float:
	return warn + drop + hold + rise


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if warn < 0.3:
		errors.append("clamp timing: warn must be >= 0.3 s (readable telegraph)")
	if drop <= 0.0 or hold <= 0.0 or rise <= 0.0:
		errors.append("clamp timing: drop, hold and rise must be > 0")
	if rearm < cycle():
		errors.append("clamp timing: rearm (%.2f) is shorter than one cycle (%.2f)" % [rearm, cycle()])
	return errors
