class_name PursuerData
extends Resource
## Tuning for a ChaseDirector's pursuer (M7 chase set pieces, D-073). The chase
## says "keep moving": the pursuer is slower than a running Rook, it waits a
## readable warn_time before it moves, a catch costs at most one pip and never
## kills (nonlethal), and a catch returns Rook to his last checkpoint with a
## regroup grace. validate() guards those promises so a data tweak cannot turn
## the set piece into a cheap death trap.
##
## Distances are path progress in px (arc length along the director's path);
## lead = Rook's progress - the pursuer's progress.

enum Look {
	## A railcar hanging from an overhead rail (Rainline): body 64x146 below rail_y.
	SWEEPER,
}

## Rook's run speed (data/movement/default_movement.tres max_run_speed). The
## pursuer's base speed must stay below it so running always gains ground.
const RUN_SPEED := 150.0
## Catch-up may reach 1.2x run: fast enough that stalling far ahead still
## feels hunted, slow enough that a clean run keeps its lead.
const MAX_CATCHUP := 180.0
## The catch-up speed blends in linearly over this many px past far_lead.
const CATCHUP_BLEND := 64.0

@export var id: String = ""
@export var look: Look = Look.SWEEPER
## Room y of the overhead rail, relative to the path's y (negative = above).
@export var rail_y: float = -150.0
## px/s along the path, before the director's per-segment speed_scale.
@export var base_speed: float = 125.0
## px/s used while the lead is above far_lead (blended in over 64 px).
@export var catchup_speed: float = 165.0
@export var far_lead: float = 380.0
## Below this lead the telegraphs turn to danger (red chevron, fast ticks).
@export var near_lead: float = 96.0
## The pursuer starts this far behind Rook when the chase arms.
@export var start_lead: float = 380.0
## Lights, then siren; the pursuer is still for this long (the telegraph).
@export var warn_time: float = 1.2
## After a catch the pursuer restarts this far behind the checkpoint.
@export var respawn_lead: float = 260.0
## Seconds after a catch with no catches (3-blink countdown on the pursuer).
@export var regroup_time: float = 1.0
## Size of the catch rect (px), centred on the pursuer's path x.
@export var catch_size: Vector2 = Vector2(56, 116)
## The catch rect's bottom sits at path y + catch_bottom. The Sweeper's is
## -4, so a Rook on a lower road below the deck is never caught.
@export var catch_bottom: float = -4.0
## Also a catch when Rook is this far behind the pursuer (lead < -catch_behind).
@export var catch_behind: float = 24.0
## Pips per catch; always applied nonlethal (Rook keeps at least one).
@export var catch_damage: int = 1
@export var catch_hitstop: float = 0.12
@export var catch_shake: float = 0.4
## Rook's progress is searched within [last - project_back, last + project_fwd]
## so a switchback path never snaps him onto another leg.
@export var project_back: float = 160.0
@export var project_fwd: float = 400.0
## Shown once per room load when the chase arms (rooms add no HintTrigger
## with the same text).
@export var warn_hint: String = "Something on the line just woke up. Run east."
## Shown once per room load, after the 2nd catch.
@export var repeat_hint: String = "Keep moving — it catches you when you slow down."
## After the end area: harmless run-out speed (px/s) to the derail point.
@export var runout_speed: float = 160.0
## The derail point (buffer stop): the first path point, in travel order,
## whose x reaches derail_x. The default is past any room: the path end.
@export var derail_x: float = 100000.0
## Cosmetic derail animation length (s), then the pursuer frees itself.
@export var derail_time: float = 1.6


## Speed (px/s) at a given lead on a segment with speed scale `scale`: the
## scaled base speed up to far_lead, catchup_speed from far_lead + 64, linear
## in between.
func speed_at(lead: float, scale: float = 1.0) -> float:
	var t := clampf((lead - far_lead) / CATCHUP_BLEND, 0.0, 1.0)
	return lerpf(base_speed * scale, catchup_speed, t)


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == "":
		errors.append("pursuer has no id")
	if base_speed >= RUN_SPEED:
		errors.append("pursuer base_speed must be < run speed %d px/s (got %.1f)" % [int(RUN_SPEED), base_speed])
	if catchup_speed > MAX_CATCHUP:
		errors.append("pursuer catchup_speed must be <= %d px/s (got %.1f)" % [int(MAX_CATCHUP), catchup_speed])
	if warn_time < 0.3:
		errors.append("pursuer warn_time must be >= 0.3 s: the telegraph rule (got %.2f)" % warn_time)
	if start_lead < near_lead + 64.0:
		errors.append("pursuer start_lead must be >= near_lead + 64 (got %.0f, near_lead %.0f)" % [start_lead, near_lead])
	if respawn_lead < 160.0:
		errors.append("pursuer respawn_lead must be >= 160 px (got %.0f)" % respawn_lead)
	if regroup_time < 0.5:
		errors.append("pursuer regroup_time must be >= 0.5 s (got %.2f)" % regroup_time)
	if catch_size.x <= 0.0 or catch_size.y <= 0.0:
		errors.append("pursuer catch_size must be positive (got %s)" % catch_size)
	if catch_damage < 0:
		errors.append("pursuer catch_damage must be >= 0")
	if runout_speed <= 0.0 or derail_time < 0.0:
		errors.append("pursuer runout_speed must be > 0 and derail_time >= 0")
	return errors
