class_name TraversalMetrics
extends Resource
## Level-design metrics recorded from the real player physics (not from
## formulas): one trajectory per technique, feet position per physics frame
## relative to the take-off point, moving right. Written by
## `MovementProbe.tscn -- --write-metrics`; test_level_metrics fails when the
## movement tuning changes and these go stale. Templates and the jump-arc
## preview read them, so gaps and steps always match how Rook really moves.

const TECHNIQUES: PackedStringArray = ["run_jump", "slide_jump", "dodge_jump", "dash_jump"]

@export var preset_name: String = "default"
## Collider width: a centre can sit half of it past a ledge and still stand.
@export var body_width: float = 12.0
@export var trajectories: Dictionary = {}


func trajectory(technique: String) -> PackedVector2Array:
	return trajectories.get(technique, PackedVector2Array())


## Highest point reached (px, positive = up).
func peak(technique: String) -> float:
	var best := 0.0
	for p in trajectory(technique):
		best = maxf(best, -p.y)
	return best


## Horizontal distance (centre) at which the arc comes back down to `rise`
## px above take-off height (negative = lower). 0 if it never gets there.
func reach(technique: String, rise: float = 0.0) -> float:
	var pts := trajectory(technique)
	var apex := false
	for i in range(1, pts.size()):
		if -pts[i].y >= peak(technique) - 0.01:
			apex = true
		if apex and -pts[i].y <= rise and -pts[i - 1].y > rise:
			var t := (-pts[i - 1].y - rise) / maxf(0.001, -pts[i - 1].y + pts[i].y)
			return lerpf(pts[i - 1].x, pts[i].x, t)
	return 0.0


## Widest gap (edge to edge) this technique clears, minus a safety margin.
## Conservative: assumes take-off with the centre *at* the lip (players and
## the route bot jump a few px early), landing half a body onto the far side.
func max_gap(technique: String, rise: float = 0.0, margin: float = 6.0) -> float:
	return reach(technique, rise) + body_width * 0.5 - margin
