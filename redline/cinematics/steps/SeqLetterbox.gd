class_name SeqLetterbox
extends SequenceStep
## Mid-sequence letterbox toggle (the start/end slides are automatic).

@export var show: bool = true
@export var seconds: float = 0.35


func run(p: SequencePlayer) -> void:
	var ov := p.overlay()
	if not is_instance_valid(ov):
		return
	await p.wait_tween(p.adopt(ov.letterbox(show, seconds)))


func finish(p: SequencePlayer) -> void:
	var ov := p.overlay()
	if is_instance_valid(ov):
		ov.letterbox(show, 0.0)


func nominal_seconds() -> float:
	return seconds


func locking_only() -> bool:
	return true
