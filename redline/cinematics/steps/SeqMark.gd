class_name SeqMark
extends SequenceStep
## Emits Cinematics.marked (CaptureTour shots, tests). Also on skip/INSTANT,
## so tests see marks in every mode.

@export var mark: String = ""


## Idempotent per play: a mark is emitted once however often finish() runs.
func finish(p: SequencePlayer) -> void:
	if p.memo(self, "emitted") != null:
		return
	p.memo(self, "emitted", true)
	Cinematics.marked.emit(mark)


func validate(_v: SequenceValidation) -> PackedStringArray:
	return PackedStringArray() if mark != "" else PackedStringArray(["empty mark"])
