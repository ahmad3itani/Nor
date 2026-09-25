class_name SeqFade
extends SequenceStep
## Fades the overlay to/from a colour (default: the Main.tscn fade colour).

@export_range(0.0, 1.0) var to_alpha: float = 1.0
@export var seconds: float = 0.5
@export var color: Color = Color(0.03, 0.02, 0.05)


func run(p: SequencePlayer) -> void:
	var ov := p.overlay()
	if not is_instance_valid(ov):
		return
	await p.wait_tween(p.adopt(ov.fade(to_alpha, seconds, color)))


func finish(p: SequencePlayer) -> void:
	var ov := p.overlay()
	if is_instance_valid(ov):
		ov.fade(to_alpha, 0.0, color)


func validate(_v: SequenceValidation) -> PackedStringArray:
	return PackedStringArray() if seconds >= 0.0 else PackedStringArray(["negative seconds"])


func nominal_seconds() -> float:
	return seconds


func locking_only() -> bool:
	return true
