class_name SeqWait
extends SequenceStep
## A beat of nothing (the room breathes).

@export var seconds: float = 0.5


func run(p: SequencePlayer) -> void:
	await p.wait(seconds)


func finish(_p: SequencePlayer) -> void:
	pass


func validate(_v: SequenceValidation) -> PackedStringArray:
	return PackedStringArray() if seconds >= 0.0 else PackedStringArray(["negative seconds"])


func nominal_seconds() -> float:
	return seconds
