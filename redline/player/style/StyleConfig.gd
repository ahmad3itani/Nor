class_name StyleConfig
extends Resource
## Style/combo tuning (bible §10): variety, movement transitions, aerial
## play, environmental kills and perfect dodges raise the rank; repeating
## the same attack gives diminishing returns; getting hit costs rank.

@export var rank_names: PackedStringArray = ["D", "C", "B", "A", "S", "SS", "SSS", "REDLINE"]
## Points needed for each rank (same length as rank_names, ascending, first = 0).
@export var rank_thresholds: PackedFloat32Array = [0, 80, 200, 360, 560, 800, 1080, 1400]
@export var max_points: float = 1800.0

@export_group("Decay")
## Seconds after the last gain before points start draining.
@export var decay_delay: float = 1.2
@export var decay_base: float = 25.0
## Extra drain per rank, so high ranks need constant expression to hold.
@export var decay_per_rank: float = 14.0

@export_group("Variety")
## Each identical tag in recent history multiplies the gain by this.
@export_range(0.0, 1.0) var repeat_penalty: float = 0.55
@export var history_size: int = 5

@export_group("Multipliers")
@export var aerial_multiplier: float = 1.3
@export var movement_multiplier: float = 1.35
@export var ranged_multiplier: float = 1.0

@export_group("Bonuses")
## Kills add EnemyData.style_value x this.
@export var kill_multiplier: float = 1.0
## Extra multiplier on environmental kills (launched impacts, hazards).
@export var environmental_multiplier: float = 1.6
@export var perfect_dodge_points: float = 70.0
@export var blocked_points: float = 2.0
## Fraction of points kept after taking damage.
@export_range(0.0, 1.0) var damage_keep: float = 0.4


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if rank_names.size() != rank_thresholds.size():
		errors.append("rank_names and rank_thresholds differ in length")
	for i in range(1, rank_thresholds.size()):
		if rank_thresholds[i] <= rank_thresholds[i - 1]:
			errors.append("rank_thresholds must be ascending")
			break
	if rank_thresholds.size() > 0 and rank_thresholds[rank_thresholds.size() - 1] > max_points:
		errors.append("top rank unreachable (threshold above max_points)")
	return errors
