class_name QuestTracker
extends Node
## Watches flags and announces quest starts, progress and completion; pays
## rewards exactly once. Lives under the Game autoload.

const QUEST_DIR := "res://data/quests"

var quests: Array[QuestData] = []
var _last_stage: Dictionary = {}


func _ready() -> void:
	for f in DirAccess.get_files_at(QUEST_DIR):
		if f.ends_with(".tres") or f.ends_with(".tres.remap"):
			var q := load("%s/%s" % [QUEST_DIR, f.trim_suffix(".remap")]) as QuestData
			if q:
				quests.append(q)
	EventBus.flag_changed.connect(func(id: String, _v: Variant) -> void: evaluate(id))
	EventBus.game_state_reset.connect(_snapshot)
	_snapshot()


func _snapshot() -> void:
	_last_stage.clear()
	for q in quests:
		_last_stage[q.id] = q.current_stage() if q.is_started() else -1


func active_quests() -> Array[QuestData]:
	var out: Array[QuestData] = []
	for q in quests:
		if q.is_started() and not Game.has_flag(q.complete_flag):
			out.append(q)
	return out


func completed_quests() -> Array[QuestData]:
	var out: Array[QuestData] = []
	for q in quests:
		if Game.has_flag(q.complete_flag):
			out.append(q)
	return out


## changed_flag limits "n/total" progress hints to the flag that just changed.
func evaluate(changed_flag: String = "") -> void:
	for q in quests:
		if not q.is_started():
			continue
		var stage := q.current_stage()
		var previous: int = _last_stage.get(q.id, -1)
		if previous == -1:
			EventBus.hint_requested.emit("NEW QUEST  —  %s" % q.title, 3.0)
		if stage >= q.stages.size():
			if not Game.has_flag(q.complete_flag):
				_complete(q)
		elif stage != previous and previous != -1:
			EventBus.hint_requested.emit("%s  —  %s" % [q.title, q.stages[stage].description], 3.0)
		elif stage == previous and q.stages[stage].complete_flags.has(changed_flag):
			var prog := q.stage_progress(stage)
			if prog.y > 1 and prog.x > 0:
				EventBus.hint_requested.emit("%s  %d/%d" % [q.title, prog.x, prog.y], 2.0)
		_last_stage[q.id] = stage
		EventBus.quest_updated.emit(q)


func _complete(q: QuestData) -> void:
	Game.add_scrap(q.reward_scrap)
	if q.reward_circuit != "":
		Game.grant_circuit(q.reward_circuit)
	Game.set_flag(q.complete_flag)
	AudioManager.play_sfx(&"quest_complete")
	EventBus.hint_requested.emit("QUEST COMPLETE  —  %s" % q.title, 3.5)
