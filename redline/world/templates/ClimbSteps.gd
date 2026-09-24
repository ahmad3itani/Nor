@tool
class_name ClimbSteps
extends RoomTemplate
## Zig-zag one-way steps up a shaft. `step_rise` is checked against the real
## jump peak (TraversalMetrics) so a climb can never be impossible by a pixel
## (the M3 route bot found 55 px steps against a 56 px jump). Origin = floor.

@export_range(1, 12) var steps: int = 4:
	set(v):
		steps = v
		_rebuild_later()
@export var step_rise: float = 48.0:
	set(v):
		step_rise = v
		_rebuild_later()
@export var step_width: float = 60.0:
	set(v):
		step_width = v
		_rebuild_later()
## Horizontal offset between alternating steps.
@export var zig: float = 70.0:
	set(v):
		zig = v
		_rebuild_later()
## Required head-room under the jump peak (px).
@export var safety: float = 6.0


func max_rise() -> float:
	return metrics().peak("run_jump") - safety


func step_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in steps:
		out.append(Vector2((zig if i % 2 == 1 else 0.0), -step_rise * (i + 1)))
	return out


func _generate() -> void:
	var i := 0
	for p in step_positions():
		add_block(Rect2(p, Vector2(step_width, 8)), true, "Step%d" % (i + 1))
		i += 1


func _get_configuration_warnings() -> PackedStringArray:
	if step_rise > max_rise():
		return PackedStringArray(["step_rise %d px is more than a jump can climb safely (%d px)." % [step_rise, max_rise()]])
	return PackedStringArray()
