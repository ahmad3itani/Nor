@tool
class_name NPC
extends Interactable
## A person (bible §13, §19). Picks a conversation from ordered rules so
## lines react to world state; rules are data (NpcDialogueRule resources).

@export var profile: NpcProfile:
	set(v):
		profile = v
		queue_redraw()
@export var height: float = 30.0
@export_enum("Right:1", "Left:-1") var facing: int = -1


func _ready() -> void:
	prompt_verb = "Talk"
	super._ready()


func prompt_text() -> String:
	return "Talk  —  %s" % profile.display_name


func interact(_player: Player) -> void:
	# NPC state (bible §19): how often you've talked is a flag rules can use.
	var talks := "talks_%s" % profile.npc_id
	Game.set_flag(talks, Game.flag_int(talks) + 1)
	var d := profile.pick_dialogue()
	if d:
		EventBus.dialogue_requested.emit(d, profile.display_name)


func _draw() -> void:
	if profile == null:
		return
	var color := profile.color
	# Placeholder figure: body, head and a facing mark. The prompt names them.
	draw_rect(Rect2(-6, -height, 12, height - 8), color)
	draw_rect(Rect2(-5, -height - 7, 10, 8), color.lightened(0.2))
	draw_rect(Rect2(1 if facing > 0 else -4, -height - 4, 3, 2), Color("1a1320"))
	draw_rect(Rect2(-5, -8, 4, 8), color.darkened(0.3))
	draw_rect(Rect2(1, -8, 4, 8), color.darkened(0.3))
