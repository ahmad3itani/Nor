class_name SeqCredits
extends SequenceStep
## The credits roll (the last blocking step of every ending). A CreditsRoll
## goes on the cinematic overlay through add_layer_child, rises at
## pixels_per_second on the sequence clock (so pause and AUTO speed apply),
## holds the closing line, and is freed by finish() (the restore contract's
## clear_all frees it on an abort). INSTANT and a skip add nothing.

const MAX_SECONDS := 60.0
## Canvas height (project viewport); the column starts just below it.
const VIEW_HEIGHT := 270.0

@export var credits: CreditsData
@export var pixels_per_second: float = 20.0
@export var hold_end_seconds: float = 2.5
## Optional mark emitted mark_after_seconds into the roll (CaptureTour shoots
## the roll mid-scroll; a SeqMark before the step would shoot an empty frame).
## Also emitted by finish(), once per play, like SeqMark.
@export var mark: String = ""
@export var mark_after_seconds: float = 5.0


## Row height for a subtitle font size (the roll follows the setting).
static func row_height(font_size: int) -> float:
	return float(font_size + 4)


## Roll length at a font size: every row passes the whole screen, then the
## hold. Budgets use the default size (nominal_seconds).
func seconds_for(font_size: int) -> float:
	if credits == null or pixels_per_second <= 0.0:
		return hold_end_seconds
	return (credits.rows().size() * row_height(font_size) + VIEW_HEIGHT) / pixels_per_second + hold_end_seconds


func run(p: SequencePlayer) -> void:
	var ov := p.overlay()
	var roll: CreditsRoll = null
	if is_instance_valid(ov) and credits:
		roll = CreditsRoll.new()
		roll.name = "CreditsRoll"
		roll.setup(credits, row_height(SubtitleStyle.font_size()))
		ov.add_layer_child(roll)
		p.memo(self, "roll", roll)
	var duration := seconds_for(SubtitleStyle.font_size())
	var start := p.clock()
	while not p.interrupted():
		var t := p.clock() - start
		if is_instance_valid(roll):
			roll.scroll = t * pixels_per_second
		if mark != "" and t >= mark_after_seconds:
			_emit_mark(p)
		if t >= duration:
			break
		await p.ticked
	if not p.aborted():
		finish(p)


func finish(p: SequencePlayer) -> void:
	var roll: Variant = p.memo(self, "roll")
	if roll is Node and is_instance_valid(roll):
		(roll as Node).queue_free()
	if mark != "":
		_emit_mark(p)


func _emit_mark(p: SequencePlayer) -> void:
	if p.memo(self, "marked") != null:
		return
	p.memo(self, "marked", true)
	Cinematics.marked.emit(mark)


func validate(_v: SequenceValidation) -> PackedStringArray:
	var out := PackedStringArray()
	if credits == null:
		out.append("no credits")
	if pixels_per_second <= 0.0:
		out.append("pixels_per_second must be > 0")
	if hold_end_seconds < 0.0:
		out.append("negative hold_end_seconds")
	if nominal_seconds() > MAX_SECONDS + 0.001:
		out.append("credits run %.1f s (max %.0f)" % [nominal_seconds(), MAX_SECONDS])
	return out


func nominal_seconds() -> float:
	return seconds_for(SubtitleStyle.SIZES[0])
