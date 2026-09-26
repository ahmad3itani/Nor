class_name FutureFlag
extends Resource
## One flag a later act will produce (an entry of FutureFlagSet). Nothing in
## the built acts sets it, so any condition reading it cannot pass yet.

const NOTE_MAX := 80
## Acts II..V, or 9 = the M9 postgame (The Null, bible §30).
const VALID_ACTS: Array[int] = [2, 3, 4, 5, 9]

@export var flag: String = ""
@export var act: int = 5
## Why the flag exists (<= 80 chars); the validator report shows it.
@export var note: String = ""


## "Act 3", or "M9 postgame" for 9 (a milestone, not one of §18's five acts),
## for the validator report and messages.
static func when_label(p_act: int) -> String:
	return "M9 postgame" if p_act == 9 else "Act %d" % p_act
