class_name QuestData
extends Resource
## A quest is derived entirely from world flags (bible §19): it starts when
## start_flag is set and advances as stage flags get set by dialogue,
## switches or pickups. Nothing but flags needs saving.

@export var id: String = ""
@export var title: String = ""
@export var giver: String = ""
@export var start_flag: String = ""
@export var stages: Array[QuestStage] = []

@export_group("Reward")
@export var reward_scrap: int = 0
@export var reward_circuit: String = ""
## Flags set on completion as a reward (e.g. a map upgrade).
@export var reward_flags: PackedStringArray = []
## Set when the quest completes (world changes key off this, e.g. the Relay radio).
@export var complete_flag: String = ""


func is_started() -> bool:
	return Game.has_flag(start_flag)


## Index of the first unfinished stage; stages.size() when complete.
func current_stage() -> int:
	for i in stages.size():
		if not Game.all_flags(stages[i].complete_flags):
			return i
	return stages.size()


func is_complete() -> bool:
	return is_started() and current_stage() >= stages.size()


func stage_progress(i: int) -> Vector2i:
	var done := 0
	for f in stages[i].complete_flags:
		if Game.has_flag(f):
			done += 1
	return Vector2i(done, stages[i].complete_flags.size())


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == "" or title == "" or start_flag == "" or complete_flag == "":
		errors.append("quest %s missing id/title/start_flag/complete_flag" % id)
	if stages.is_empty():
		errors.append("quest %s has no stages" % id)
	for s in stages:
		if s.complete_flags.is_empty():
			errors.append("quest %s has a stage with no completion flags" % id)
	return errors
