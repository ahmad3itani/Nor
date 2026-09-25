class_name WorldStateSwitch
extends Node2D
## World consequences (bible §13 "the Relay visibly evolves", §19): children
## show only while `visible_when` holds (Game.check_condition), and update
## live when flags change. Visual set dressing only; no collision children
## (the validator enforces it: a hidden wall or pickup would still act).

@export var visible_when: String = ""


func _ready() -> void:
	_refresh()
	if not Engine.is_editor_hint():
		EventBus.flag_changed.connect(func(_id: String, _v: Variant) -> void: _refresh())
		EventBus.game_state_reset.connect(_refresh)


func _refresh() -> void:
	visible = Engine.is_editor_hint() or Game.check_condition(visible_when)
	# Hidden sets stop processing too (animated lamps and signs cost nothing
	# while off). Our own signal callbacks still run: they are not _process.
	if not Engine.is_editor_hint():
		process_mode = Node.PROCESS_MODE_INHERIT if visible else Node.PROCESS_MODE_DISABLED


## Content protocol: anything that collides, rewards or reacts must not sit
## under a switch, because hiding it would not remove it from play.
func content_errors(_room: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for n in find_children("*", "", true, false):
		if n is CollisionObject2D or n is Interactable or n is Enemy or n is Collectible or n is BreakableWall:
			out.append("%s under a WorldStateSwitch (visual only)" % n.name)
	return out
