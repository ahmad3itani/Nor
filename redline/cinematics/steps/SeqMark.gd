class_name SeqMark
extends SequenceStep
## Emits Cinematics.marked (CaptureTour shots, tests). Also on skip/INSTANT,
## so tests see marks in every mode.

@export var mark: String = ""


func finish(_p: SequencePlayer) -> void:
	Cinematics.marked.emit(mark)


func validate(_v: SequenceValidation) -> PackedStringArray:
	return PackedStringArray() if mark != "" else PackedStringArray(["empty mark"])
