class_name SequenceStep
extends Resource
## One beat of a scripted sequence (M8, D-106). Subclasses live in
## cinematics/steps/, one small script per kind.
##
## Contract:
## - run() plays the beat in real time. It may await p.wait()/p.wait_tween()
##   and must return promptly once p.interrupted() (skip or abort).
## - finish() puts the beat in its end state at once. It runs on a skip (for
##   this and every later eligible step) and in INSTANT mode, never on an
##   abort, and must be idempotent. Effects that matter (flags, facing,
##   music) are therefore never lost to a skip.
## - Steps are shared Resources: per-play state goes in p.memo(), never here.

@export var label: String = ""
## Which views play this step: a first view (seen flag unset or the context
## says first) or a repeat view.
@export_enum("Always", "First view", "Repeat view") var views: int = 0
## Game.check_condition expression; false = the step is skipped (and never
## finish()ed). Evaluated when the step is reached.
@export var only_when: String = ""
## false = the step starts and the next one starts at once (parallel).
@export var blocking: bool = true


func run(p: SequencePlayer) -> void:
	finish(p)


func finish(_p: SequencePlayer) -> void:
	pass


## Rules that need the sequence context (speakers, room, view). Errors only.
func validate(_v: SequenceValidation) -> PackedStringArray:
	return PackedStringArray()


## {produces, consumes, conditions}. Only SeqFlag produces flags.
func content_flags() -> Dictionary:
	return {"produces": [], "consumes": [], "conditions": [only_when] if only_when != "" else []}


## Authored length at subtitle speed x1.0 (budgets use it).
func nominal_seconds() -> float:
	return 0.0


## Steps that need the player locked (camera, pose, letterbox, fade): a
## non-locking play (barks, repeat boss intros) may not use them.
func locking_only() -> bool:
	return false


func plays_in_view(first_view: bool) -> bool:
	return views == 0 or (views == 1) == first_view


## Script basename ("SeqLine"), for messages, telemetry and the inspector.
func kind() -> String:
	var s := get_script() as Script
	return s.resource_path.get_file().get_basename() if s else "SequenceStep"
