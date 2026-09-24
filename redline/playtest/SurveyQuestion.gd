class_name SurveyQuestion
extends Resource
## One post-slice survey question. Most map 1:1 to a bible §44 success
## criterion so the report can score the slice against it directly.

enum Kind { SCALE, YES_NO, CHOICE }

@export var id: String = ""
@export var text: String = ""
@export var kind: Kind = Kind.SCALE
## For CHOICE questions (e.g. "which enemy do you remember").
@export var choices: PackedStringArray = []
## The §44 line this answers ("" = informational only).
@export var criterion: String = ""
## SCALE answers at or above this count as a pass (1-5).
@export_range(1, 5) var pass_at: int = 4


## True when an answer satisfies the §44 criterion. CHOICE passes on any
## answer except the last choice (by convention "none / don't remember").
func passes(answer: Variant) -> bool:
	match kind:
		Kind.SCALE:
			return int(answer) >= pass_at
		Kind.YES_NO:
			return bool(answer)
		_:
			return int(answer) >= 0 and int(answer) < choices.size() - 1
