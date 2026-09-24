class_name TrackerConfig
extends Resource
## Tuning for a CeilingTracker (the Collector eye, D-069). The eye exists to
## say "keep moving": it is slower than a running Rook, only fires after he
## has stood in its cone for lock_time, and telegraphs for windup before the
## shot. validate() guards those promises so a data tweak cannot turn it into
## a cheap hit.

## Rail speed in px/s. Must stay below Rook's run speed (150) so running
## always outpaces it.
@export var speed: float = 110.0
## Half-width of the cone where it meets the floor (px). Rook is "in the cone"
## when his x is within this of the eye's x.
@export var cone_half_width: float = 32.0
## Floor height (room y) the cone is drawn down to.
@export var floor_y: float = 0.0
## Seconds Rook must stay in the cone (with line of sight) before it locks.
@export var lock_time: float = 1.0
## Telegraph: the cone is solid red with a "!" this long before the bolt.
@export var windup: float = 0.6
## After a shot it keeps tracking but cannot lock for this long.
@export var cooldown: float = 1.6
## Hatch-drop time before it starts tracking.
@export var emerge_time: float = 0.8
## Time to pull back into the ceiling once Rook is past lost_x.
@export var retract_time: float = 0.8
## One sweep across the rail before retracting (a readable "it lost you").
@export var sweep_time: float = 0.6
## The bolt: an enemy AttackData with a ProjectileData (hurts Rook only).
@export var attack: AttackData

## Rook's run speed; the eye must never keep up with a running player.
const RUN_SPEED := 150.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if lock_time < 0.6:
		errors.append("tracker lock_time must be >= 0.6 s (got %.2f)" % lock_time)
	if windup < 0.3:
		errors.append("tracker windup must be >= 0.3 s: the telegraph rule (got %.2f)" % windup)
	if speed >= RUN_SPEED:
		errors.append("tracker speed must be < run speed %d px/s (got %.1f)" % [int(RUN_SPEED), speed])
	if cooldown < 1.0:
		errors.append("tracker cooldown must be >= 1.0 s (got %.2f)" % cooldown)
	if cone_half_width <= 0.0:
		errors.append("tracker cone_half_width must be > 0")
	if emerge_time < 0.0 or retract_time < 0.0 or sweep_time < 0.0:
		errors.append("tracker emerge/retract/sweep times must be >= 0")
	if attack == null:
		errors.append("tracker has no attack")
	elif attack.projectile == null:
		errors.append("tracker attack %s has no projectile" % attack.id)
	return errors
