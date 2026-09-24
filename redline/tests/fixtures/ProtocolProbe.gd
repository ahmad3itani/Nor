extends Node
## Test node for the ContentValidator content protocol (test_scaffold): one
## warning and one error, through the binding one-argument signature.


func content_errors(_room: Node) -> PackedStringArray:
	return PackedStringArray(["WARN: x", "y"])


## HitboxView hook (test_scaffold): counts the calls, draws nothing.
var debug_draw_calls: int = 0


func debug_draw(_canvas: CanvasItem) -> void:
	debug_draw_calls += 1
