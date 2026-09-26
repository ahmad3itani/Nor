class_name WaveEntry
extends Resource
## One group of enemies inside a Pulse Pit wave (M9 D2 §2.3). A WaveSet lists
## its entries flat, each tagged with the 1-based wave it belongs to (a flat
## list keeps the .tres plain and lets the validator point at one entry).
## Spawns are deterministic: the i-th enemy of an entry stands on
## spawn_points[i % size] (round-robin, no RNG), so a record run replays the
## same pit every time.

const LOC_FIELDS := {}

## 1-based wave index inside the set.
@export var wave: int = 1
@export_file("*.tscn") var enemy_scene: String = ""
## Enemies in this entry (a looping set adds WaveSet.loop_count_bonus per loop).
@export var count: int = 1
## Indices of the room's WaveSpawn_<n> markers, used round-robin.
@export var spawn_points: PackedInt32Array = []
## Seconds after the wave starts before this entry spawns.
@export var delay_s: float = 0.0


func validate() -> PackedStringArray:
	var out := PackedStringArray()
	if wave < 1:
		out.append("wave entry wave must be >= 1 (has %d)" % wave)
	if enemy_scene == "" or not ResourceLoader.exists(enemy_scene):
		out.append("wave %d entry: enemy scene '%s' does not exist" % [wave, enemy_scene])
	if count < 1:
		out.append("wave %d entry: count must be >= 1" % wave)
	if spawn_points.is_empty():
		out.append("wave %d entry: needs at least one spawn point" % wave)
	for i in spawn_points:
		if i < 1:
			out.append("wave %d entry: spawn point %d must be >= 1 (WaveSpawn_1 is the first)" % [wave, i])
	if delay_s < 0.0:
		out.append("wave %d entry: delay_s must be >= 0" % wave)
	return out
