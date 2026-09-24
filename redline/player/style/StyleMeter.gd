class_name StyleMeter
extends RefCounted
## Pure style logic (no nodes) so it can be unit-tested and reused for
## challenge scoring later.

var config: StyleConfig
var points: float = 0.0
var history: Array[StringName] = []
var time_since_gain: float = 0.0


func _init(p_config: StyleConfig) -> void:
	config = p_config


## Returns the points actually gained after variety and context multipliers.
func add_hit(tag: StringName, base_points: float, tags: Array[StringName]) -> float:
	var mult := pow(config.repeat_penalty, history.count(tag))
	if tags.has(&"aerial"):
		mult *= config.aerial_multiplier
	if tags.has(&"after_movement"):
		mult *= config.movement_multiplier
	if tags.has(&"ranged"):
		mult *= config.ranged_multiplier
	history.append(tag)
	while history.size() > config.history_size:
		history.pop_front()
	return _gain(base_points * mult)


func add_bonus(amount: float) -> float:
	return _gain(amount)


func take_damage() -> void:
	points *= config.damage_keep


func reset() -> void:
	points = 0.0
	history.clear()
	time_since_gain = 0.0


func tick(delta: float) -> void:
	time_since_gain += delta
	if time_since_gain > config.decay_delay and points > 0.0:
		points = maxf(points - (config.decay_base + config.decay_per_rank * rank_index()) * delta, 0.0)


func rank_index() -> int:
	var idx := 0
	for i in config.rank_thresholds.size():
		if points >= config.rank_thresholds[i]:
			idx = i
	return idx


func rank_name() -> String:
	return config.rank_names[rank_index()]


## 0..1 progress from the current rank's threshold to the next.
func rank_progress() -> float:
	var i := rank_index()
	if i >= config.rank_thresholds.size() - 1:
		return 1.0
	var lo := config.rank_thresholds[i]
	var hi := config.rank_thresholds[i + 1]
	return clampf((points - lo) / (hi - lo), 0.0, 1.0)


func _gain(amount: float) -> float:
	var before := points
	points = minf(points + amount, config.max_points)
	time_since_gain = 0.0
	return points - before
