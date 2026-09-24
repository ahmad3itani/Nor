extends Node
## Test node for the ContentValidator content protocol (test_scaffold): one
## warning and one error, through the binding one-argument signature.


func content_errors(_room: Node) -> PackedStringArray:
	return PackedStringArray(["WARN: x", "y"])
