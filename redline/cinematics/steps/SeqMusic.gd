class_name SeqMusic
extends SequenceStep
## Music override for the scene (a hush before a roar), or its clear. The
## restore contract clears any override the scene set.

## MusicDirector.State value (SILENT 0 .. MEMORY 7).
@export var state: int = 0
@export var clear: bool = false


func finish(p: SequencePlayer) -> void:
	if clear:
		p.clear_music()
	else:
		p.set_music(state)


func validate(_v: SequenceValidation) -> PackedStringArray:
	if not clear and (state < 0 or state >= MusicDirector.State.size()):
		return PackedStringArray(["music state %d out of range" % state])
	return PackedStringArray()
