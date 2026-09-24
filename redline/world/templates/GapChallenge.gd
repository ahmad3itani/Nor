@tool
class_name GapChallenge
extends RoomTemplate
## A traversal gap sized from recorded movement (TraversalMetrics), so it is
## exactly as hard as intended: clearable with `technique` taken at the lip
## with `margin` px to spare. Origin = top of the near lip. Optional catch
## well under the gap (miss = climb back, no pip; see D-036).
## The editor warns when a weaker technique also clears it (not a real gate).

@export_enum("run_jump", "slide_jump", "dodge_jump", "dash_jump") var technique: String = "slide_jump":
	set(v):
		technique = v
		_rebuild_later()
@export var margin: float = 6.0:
	set(v):
		margin = v
		_rebuild_later()
## Height of the far side relative to the near lip (px, positive = higher).
@export var rise: float = 0.0:
	set(v):
		rise = v
		_rebuild_later()
@export var platform_width: float = 160.0:
	set(v):
		platform_width = v
		_rebuild_later()
@export var catch_well: bool = true:
	set(v):
		catch_well = v
		_rebuild_later()


func gap_width() -> float:
	return floorf(metrics().max_gap(technique, rise, margin))


## The strongest weaker technique that still clears this gap (with no margin
## and a little coyote help), or "" when the gap is a real gate.
func leaks_to() -> String:
	var order := Array(TraversalMetrics.TECHNIQUES)
	var m := metrics()
	for i in range(order.find(technique) - 1, -1, -1):
		if m.max_gap(order[i], rise, -4.0) >= gap_width():
			return order[i]
	return ""


func _generate() -> void:
	var g := gap_width()
	add_block(Rect2(-platform_width, 0, platform_width, 96), false, "NearLip")
	add_block(Rect2(g, -rise, platform_width, 96 + rise), false, "FarLip")
	if catch_well:
		add_block(Rect2(0, 140, g, 40), false, "WellFloor")
		add_block(Rect2(g * 0.45, 92, maxf(24.0, g * 0.4), 8), true, "WellStep1")
		add_block(Rect2(4, 44, maxf(24.0, g * 0.3), 8), true, "WellStep2")


func _get_configuration_warnings() -> PackedStringArray:
	var leak := leaks_to()
	return PackedStringArray() if leak == "" else PackedStringArray(["A %s also clears this %d px gap: it teaches %s but doesn't gate it." % [leak, gap_width(), technique]])
