class_name SeqSfx
extends SequenceStep
## One sound. Not replayed by a skip (no sound on finish).

@export var id: StringName = &""
@export var volume: float = 1.0


func run(_p: SequencePlayer) -> void:
	AudioManager.play_sfx(id, volume)


func validate(_v: SequenceValidation) -> PackedStringArray:
	if id == &"" or not AudioManager.has_sfx(id):
		return PackedStringArray(["unknown sfx '%s'" % id])
	return PackedStringArray()
