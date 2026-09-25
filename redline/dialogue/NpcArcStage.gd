class_name NpcArcStage
extends Resource
## One step of a character arc (D-117): a spine stage (ordered, story order)
## or a reaction (unordered, one-shot). ArcTracker enters it once its
## conditions pass, then it is sticky: later flag changes never un-enter it
## (a boss restart that erases <boss>_defeated keeps the stage).
## World consequences are not listed here: props and switches key on the
## stage flag arc_<npc>_<id> directly (WorldStateSwitch, T08).

## snake_case, unique in the arc; names the flags arc_<npc>_<id> (reached)
## and arcbeat_<npc>_<id> (beat heard).
@export var id: String = ""
## Game.check_condition expressions, all must pass (AND).
@export var enter_all: PackedStringArray = []
## Any one must pass (OR); empty = pass.
@export var enter_any: PackedStringArray = []
## Reactions only: spine index that must be reached first (1 = first stage).
@export var min_stage: int = 0
## Applied once on entry. Act I stages set nothing (bonds and threads come
## from beats so they mean "the player heard it"); kept for later acts.
@export var set_flags: PackedStringArray = []
## One-shot beat: the first matching rule plays on the next talk and its
## dialogue sets arcbeat_<npc>_<id> (validator), so skipping still counts.
## Last rule unconditional. Empty = no beat (the intro rule already played).
@export var beat_rules: Array[NpcDialogueRule] = []
## Spine only: repeatable lines while this is the latest stage (they set
## nothing). NpcArc.idle walks back to earlier stages when none match.
@export var idle_rules: Array[NpcDialogueRule] = []
## Spine only, <= 80 chars: the journal PEOPLE line while this is the latest
## reached stage.
@export var journal_note: String = ""
## Not on the Act I main path (docs + test_act1_main_path_reaches_spine).
@export var optional: bool = false


func conditions_pass() -> bool:
	for c in enter_all:
		if not Game.check_condition(c):
			return false
	if enter_any.is_empty():
		return true
	for c in enter_any:
		if Game.check_condition(c):
			return true
	return false


## The first beat rule that matches now (null when there is no beat).
func beat() -> DialogueData:
	for r in beat_rules:
		if r.dialogue and r.matches():
			return r.dialogue
	return null


func idle() -> DialogueData:
	for r in idle_rules:
		if r.dialogue and r.matches():
			return r.dialogue
	return null
