@tool
class_name NPC
extends Interactable
## A person (bible §13, §19). Picks a conversation from ordered rules so
## lines react to world state; rules are data (NpcDialogueRule resources).
## Also used for bodiless voices (a radio, a terminal): the profile's
## `figure` and `verb` decide how it is drawn and prompted (M7).

## Pending-beat tick (D-120): near-white with a dark outline, a shape (bar +
## dot), room-local, never on the map. Defined once here so a colourblind
## variant swaps it. Never amber #ffcf5a (ART_BIBLE §3 reserves it for the
## elite outline, and the Relay's sodium lights would hide it) and never
## UiTheme.ACCENT (Redline red is reserved).
const PENDING_TICK_COLOR := UiTheme.TEXT
const PENDING_TICK_OUTLINE := UiTheme.PANEL

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

## cue_new_lines profiles: the dialogue opened by the last interact, marked
## heard (heard_<id>) when it closes.
var _awaiting_heard: DialogueData = null


func _ready() -> void:
	prompt_verb = profile.verb if profile else "Talk"
	super._ready()
	if Engine.is_editor_hint():
		return
	EventBus.flag_changed.connect(_on_flag_changed)
	EventBus.game_state_reset.connect(_refresh_presence)
	EventBus.dialogue_finished.connect(_on_dialogue_finished)
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
		if profile.cue_new_lines:
			_awaiting_heard = d
		EventBus.dialogue_requested.emit(d, profile.display_name)


## Something new to hear: an arc beat is pending, or (cue_new_lines) the
## dialogue this NPC would play now has not been heard yet.
func has_pending_beat() -> bool:
	if profile == null or Engine.is_editor_hint():
		return false
	if profile.arc and profile.arc.has_pending_beat():
		return true
	if profile.cue_new_lines:
		var d := profile.pick_dialogue()
		return d != null and not Game.has_flag(heard_flag(d))
	return false


## Code flag (like talks_): no data reads it, so the validator never sees it.
static func heard_flag(d: DialogueData) -> String:
	return "heard_%s" % d.id


func _on_dialogue_finished(d: Resource) -> void:
	if _awaiting_heard == null or d != _awaiting_heard:
		return
	_awaiting_heard = null
	Game.set_flag(heard_flag(d as DialogueData))


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
	queue_redraw()


func _draw() -> void:
	if has_pending_beat():
		_draw_tick(Vector2(0, -height - 16) if draws_figure() else Vector2(0, -16))
	if not draws_figure():
		return
	var color := profile.color
	# Placeholder figure: body, head and a facing mark. The prompt names them.
	draw_rect(Rect2(-6, -height, 12, height - 8), color)
	draw_rect(Rect2(-5, -height - 7, 10, 8), color.lightened(0.2))
	draw_rect(Rect2(1 if facing > 0 else -4, -height - 4, 3, 2), Color("1a1320"))
	draw_rect(Rect2(-5, -8, 4, 8), color.darkened(0.3))
	draw_rect(Rect2(1, -8, 4, 8), color.darkened(0.3))


## A 2x5 bar over a 2x2 dot ("!"), top-centred at `top`, with a 1 px outline.
func _draw_tick(top: Vector2) -> void:
	var bar := Rect2(top + Vector2(-1, 0), Vector2(2, 5))
	var dot := Rect2(top + Vector2(-1, 6), Vector2(2, 2))
	draw_rect(bar.grow(1), PENDING_TICK_OUTLINE)
	draw_rect(dot.grow(1), PENDING_TICK_OUTLINE)
	draw_rect(bar, PENDING_TICK_COLOR)
	draw_rect(dot, PENDING_TICK_COLOR)
