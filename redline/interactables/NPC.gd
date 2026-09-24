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
	var d := profile.pick_dialogue()
	if d:
		EventBus.dialogue_requested.emit(d, profile.display_name)


func _draw() -> void:
	if profile == null:
		return
	var color := profile.color
	var display_name := profile.display_name
	# Placeholder figure: body, head, a facing mark, and a name tag.
	draw_rect(Rect2(-6, -height, 12, height - 8), color)
	draw_rect(Rect2(-5, -height - 7, 10, 8), color.lightened(0.2))
	draw_rect(Rect2(1 if facing > 0 else -4, -height - 4, 3, 2), Color("1a1320"))
	draw_rect(Rect2(-5, -8, 4, 8), color.darkened(0.3))
	draw_rect(Rect2(1, -8, 4, 8), color.darkened(0.3))
	if display_name != "":
		var font := ThemeDB.fallback_font
		var w := font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x
		draw_string(font, Vector2(-w * 0.5, -height - 11), display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(1, 1, 1, 0.7))
