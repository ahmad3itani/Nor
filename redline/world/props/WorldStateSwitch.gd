class_name WorldStateSwitch
extends Node2D
## World consequences (bible §13 "the Relay visibly evolves", §19): children
## show only while `visible_when` holds (Game.check_condition), and update
## live when flags change. Visual set dressing only; no collision children.

@export var visible_when: String = ""


func _ready() -> void:
	_refresh()
	if not Engine.is_editor_hint():
		EventBus.flag_changed.connect(func(_id: String, _v: Variant) -> void: _refresh())
		EventBus.game_state_reset.connect(_refresh)


func _refresh() -> void:
	visible = Engine.is_editor_hint() or Game.check_condition(visible_when)
