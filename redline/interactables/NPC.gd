@tool
class_name NPC
extends Interactable
## A person (bible §13, §19). Picks a conversation from ordered rules so
## lines react to world state; rules are data (NpcDialogueRule resources).
## Also used for bodiless voices (a radio, a terminal): the profile's
## `figure` and `verb` decide how it is drawn and prompted (M7).

@export var profile: NpcProfile:
	set(v):
		profile = v
		queue_redraw()
@export var height: float = 30.0
@export_enum("Right:1", "Left:-1") var facing: int = -1
## World-state presence (M7): when non-empty, the NPC is here only while any
## entry passes Game.check_condition ("flag:met_iko", "!flag:x"...). Lets one
## character move between rooms as the story advances, with no scene swaps.
## Absent = hidden and not interactable; the map pin follows the same rule
## (WorldMapIndex.npc_present).
@export var present_when: PackedStringArray = []


func _ready() -> void:
	prompt_verb = profile.verb if profile else "Talk"
	super._ready()
	if Engine.is_editor_hint():
		return
	EventBus.flag_changed.connect(_on_flag_changed)
	EventBus.game_state_reset.connect(_refresh_presence)
	_refresh_presence()


## Same rule as the map pin, so the room and the map never disagree.
static func conditions_pass(conditions: PackedStringArray) -> bool:
	if conditions.is_empty():
		return true
	for c in conditions:
		if Game.check_condition(c):
			return true
	return false


func is_present() -> bool:
	return conditions_pass(present_when)


func can_interact(_player: Player) -> bool:
	return is_present()


func prompt_text() -> String:
	return "%s  —  %s" % [prompt_verb, profile.display_name]


func interact(_player: Player) -> void:
	if not is_present():
		return
	# NPC state (bible §19): how often you've talked is a flag rules can use.
	var talks := "talks_%s" % profile.npc_id
	Game.set_flag(talks, Game.flag_int(talks) + 1)
	var d := profile.pick_dialogue()
	if d:
		EventBus.dialogue_requested.emit(d, profile.display_name)


## ContentValidator protocol: presence conditions read flags.
func content_flags() -> Dictionary:
	return {"conditions": present_when}


## Whether _draw paints the placeholder body (false for radios/terminals).
func draws_figure() -> bool:
	return profile != null and profile.figure


func _on_flag_changed(_id: String, _value: Variant) -> void:
	_refresh_presence()


func _refresh_presence() -> void:
	visible = is_present()


func _draw() -> void:
	if not draws_figure():
		return
	var color := profile.color
	# Placeholder figure: body, head and a facing mark. The prompt names them.
	draw_rect(Rect2(-6, -height, 12, height - 8), color)
	draw_rect(Rect2(-5, -height - 7, 10, 8), color.lightened(0.2))
	draw_rect(Rect2(1 if facing > 0 else -4, -height - 4, 3, 2), Color("1a1320"))
	draw_rect(Rect2(-5, -8, 4, 8), color.darkened(0.3))
	draw_rect(Rect2(1, -8, 4, 8), color.darkened(0.3))
