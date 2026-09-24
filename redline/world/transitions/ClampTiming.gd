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
## Arm hint (the one-time teaching line): shown `hint_delay` s after the
## arena starts, or earlier when the boss first walks under the clamp, but
## never before `hint_min` s (the boss intro card owns that moment).
@export var hint_delay: float = 4.0
@export var hint_min: float = 1.0
## How long the line and the breaker lamp pulse stay up.
@export var hint_seconds: float = 3.5
## Push given to a standing Rook who is already invulnerable at the slam (no
## pip to take, but he still leaves the press). px/s, +x = away from centre.
@export var shove: Vector2 = Vector2(120, -60)


func cycle() -> float:
	return warn + drop + hold + rise


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if warn < 0.3:
		errors.append("clamp timing: warn must be >= 0.3 s (readable telegraph)")
	if drop <= 0.0 or hold <= 0.0 or rise <= 0.0:
		errors.append("clamp timing: drop, hold and rise must be > 0")
	if hint_min < 0.0 or hint_min > hint_delay or hint_seconds <= 0.0:
		errors.append("clamp timing: need 0 <= hint_min <= hint_delay and hint_seconds > 0")
	if rearm < cycle():
		errors.append("clamp timing: rearm (%.2f) is shorter than one cycle (%.2f)" % [rearm, cycle()])
	return errors
