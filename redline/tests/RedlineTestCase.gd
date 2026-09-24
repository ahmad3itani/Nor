class_name RedlineTestCase
extends Node
## Minimal test base (no third-party dependency). Methods named test_* are run
## in order; they may await physics frames. Use check()/check_near() to assert.

var failures: PackedStringArray = []
var _current_test: String = ""


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append("%s: %s" % [_current_test, message])


func check_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	check(absf(actual - expected) <= tolerance,
		"%s (expected %.3f +/- %.3f, got %.3f)" % [message, expected, tolerance, actual])


func physics_frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
