class_name RankTable
extends Resource
## How a RANK challenge (the Deep Rig strata, M9 D3 §3.3) turns a cleared
## stage into a score out of 1000 and a RankLadder tier (0 Clear .. 4 Redline;
## the names are data, R04.13, never style letters).
##
## score() and rank_of() are pure: they read only this table and their
## arguments (no Settings, no Game), so the Core mode or any assist never
## changes a rank (D-149) and the tests stay table-driven.

## Minimum score per tier, ascending, 5 values (tier 0 is any clear).
@export var thresholds: PackedInt32Array = [0, 450, 650, 820, 900]
## Time: 0 points at fail_mult × par, the full time_points at redline, linear.
@export var time_points: int = 500
@export var fail_mult: float = 2.0
## Damage: damage_points minus per_hit per hit and per_death per death, floor 0.
@export var damage_points: int = 300
@export var per_hit: int = 75
@export var per_death: int = 150
## Style: style_points × clamp(avg style rank × stage weight / full rank, 0, 1).
@export var style_points: int = 200
## StyleConfig.rank_names index worth the full style points (4 = S).
@export var full_style_rank: int = 4
## A run (descent) reaches the top tier only when every stage did.
@export var run_redline_needs_all: bool = true

const TOP_TIER := 4


## Score 0..1000 for one cleared stage.
func score(seconds: float, hits: int, deaths: int, avg_style_rank: float, stage: ChallengeStage) -> int:
	var par := stage.par_s if stage else 60.0
	var redline := stage.redline_s if stage else 40.0
	var weight := stage.style_weight if stage else 1.0
	var slow := fail_mult * par
	var t := 1.0 if slow <= redline else clampf((slow - seconds) / (slow - redline), 0.0, 1.0)
	var dmg := maxi(0, damage_points - per_hit * maxi(hits, 0) - per_death * maxi(deaths, 0))
	var sty := 0.0
	if full_style_rank > 0:
		sty = clampf(avg_style_rank * weight / float(full_style_rank), 0.0, 1.0)
	return clampi(roundi(t * time_points + dmg + sty * style_points), 0, 1000)


## The tier the score alone reaches.
func tier_for_score(value: int) -> int:
	if value < 0:
		return -1
	var tier := 0
	for i in thresholds.size():
		if value >= thresholds[i]:
			tier = i
	return mini(tier, TOP_TIER)


## The stage's tier: the top tier also needs no hits, no deaths and a time at
## or under the stage's redline.
func rank_of(value: int, seconds: float, hits: int, deaths: int, stage: ChallengeStage) -> int:
	var tier := tier_for_score(value)
	if tier == TOP_TIER:
		var redline := stage.redline_s if stage else 0.0
		if hits > 0 or deaths > 0 or seconds > redline:
			tier = TOP_TIER - 1
	return tier


## A run's score is the mean of its stage scores (rounded).
static func mean_score(scores: Array) -> int:
	if scores.is_empty():
		return 0
	var total := 0.0
	for s in scores:
		total += float(s)
	return roundi(total / scores.size())


## A run's tier from its stage results [{score, tier}, ...].
func run_rank(stage_results: Array) -> int:
	var scores: Array = []
	var all_top := true
	for r: Dictionary in stage_results:
		scores.append(int(r.get("score", 0)))
		if int(r.get("tier", -1)) < TOP_TIER:
			all_top = false
	if scores.is_empty():
		return -1
	var tier := tier_for_score(mean_score(scores))
	if tier == TOP_TIER and run_redline_needs_all and not all_top:
		tier = TOP_TIER - 1
	return tier


func validate() -> PackedStringArray:
	var out := PackedStringArray()
	if thresholds.size() != TOP_TIER + 1:
		out.append("rank table needs %d thresholds (has %d)" % [TOP_TIER + 1, thresholds.size()])
	else:
		if thresholds[0] != 0:
			out.append("rank table threshold 0 must be 0 (any clear earns the first tier)")
		for i in range(1, thresholds.size()):
			if thresholds[i] <= thresholds[i - 1]:
				out.append("rank table thresholds must be strictly ascending")
				break
	if time_points + damage_points + style_points != 1000:
		out.append("rank table points must sum to 1000 (time %d + damage %d + style %d)" % [time_points, damage_points, style_points])
	if fail_mult <= 1.0:
		out.append("rank table fail_mult must be > 1")
	if per_hit < 0 or per_death < 0 or full_style_rank <= 0:
		out.append("rank table per_hit/per_death must be >= 0 and full_style_rank > 0")
	return out
