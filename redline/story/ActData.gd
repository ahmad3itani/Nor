class_name ActData
extends Resource
## One act of the story (bible §18 "Acts"). Its close sequence sets
## complete_flag; the act card (SliceEndMenu for Act I) reads the rest.

const MAX_STANDING_CAP := 6

@export var act: int = 1
## "RUN" (bible §18).
@export var name: String = ""
## Set by close_sequence (a SeqFlag).
@export var complete_flag: String = ""
@export var close_sequence: SequenceData
## "Where things stand", in order. The last one has condition "" and always
## shows (ActLibrary.standing_lines); the passing lines before it fill the
## other max_standing - 1 slots.
@export var standing: Array[ActStandingLine] = []
## Act I: 3, so the card fits the 270 px canvas with the playtest survey row
## (MenuScreen does not scroll).
@export var max_standing: int = 3


## "I", "II", ... for the card header (acts 1..5).
static func roman(n: int) -> String:
	var numerals := ["", "I", "II", "III", "IV", "V"]
	return numerals[n] if n >= 0 and n < numerals.size() else str(n)


func content_flags() -> Dictionary:
	var conditions: Array = []
	for l in standing:
		if l != null and l.condition != "":
			conditions.append(l.condition)
	return {"produces": [], "consumes": [], "conditions": conditions}


func content_check() -> PackedStringArray:
	var errors := PackedStringArray()
	if name.strip_edges() == "":
		errors.append("act %d has no name" % act)
	if complete_flag == "":
		errors.append("act %d has no complete_flag" % act)
	if close_sequence == null:
		errors.append("act %d has no close_sequence" % act)
	elif not Array(close_sequence.content_flags().get("produces", [])).has(complete_flag):
		errors.append("act %d: close sequence %s does not set %s" % [act, close_sequence.id, complete_flag])
	if max_standing < 1 or max_standing > MAX_STANDING_CAP:
		errors.append("act %d: max_standing must be 1..%d" % [act, MAX_STANDING_CAP])
	if standing.is_empty() or standing[-1] == null or standing[-1].condition != "":
		errors.append("act %d: the last standing line must have condition \"\" (the card is never empty)" % act)
	for i in standing.size():
		var l := standing[i]
		if l == null:
			errors.append("act %d: standing line %d is empty" % [act, i])
			continue
		if l.text.strip_edges() == "":
			errors.append("act %d: standing line %d has no text" % [act, i])
		elif l.text.length() > ActStandingLine.TEXT_MAX:
			errors.append("act %d: standing line %d is %d chars (max %d)" % [act, i, l.text.length(), ActStandingLine.TEXT_MAX])
		if not ContentValidator.is_valid_condition(l.condition):
			errors.append("act %d: standing line %d has an invalid condition '%s'" % [act, i, l.condition])
	return errors
