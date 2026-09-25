class_name SeqShake
extends SequenceStep
## Camera trauma (already scaled by Settings.screen_shake_scale). None on skip.

@export_range(0.0, 1.0) var trauma: float = 0.3


func run(_p: SequencePlayer) -> void:
	EventBus.camera_shake_requested.emit(trauma)
