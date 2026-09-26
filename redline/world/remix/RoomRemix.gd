class_name RoomRemix
extends Resource
## NG+ remix of one room (bible §30, D-154). Applied by SceneRouter to the
## fresh instance before it enters the tree, so Enemy._ready reads the new
## data. The room scene never changes: routes and door contracts stay pinned.
## One file per room, data/remix/<RoomBasename>.tres, written by
## tools/roomgen/remix_act1.py. RemixRules (RM-1..RM-8) checks every op
## against the base room; validate() covers this file alone.

## `intent` is a design note for the dev report, never shown to players.
const LOC_FIELDS := {}
const LOC_EXEMPT := ["intent"]

## res:// room path; the file name equals the room's basename (RM-1).
@export var room: String = ""
## When the ops run (Game.check_condition). The NG+ option writes ng_remix.
@export var active_when: String = "flag:ng_remix"
@export var ops: Array[RemixOp] = []
## Design note shown in the dev report.
@export_multiline var intent: String = ""


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if active_when == "":
		errors.append("RoomRemix %s: active_when is empty (a remix must never run in a first cycle)" % room.get_file())
	if room == "" or not room.begins_with("res://") or not room.ends_with(".tscn"):
		errors.append("RoomRemix: room '%s' must be a res:// .tscn path" % room)
	for i in ops.size():
		var op := ops[i]
		if op == null:
			errors.append("RoomRemix %s: op %d is empty" % [room.get_file(), i])
			continue
		if String(op.target) == "":
			errors.append("RoomRemix %s: op %d has no target" % [room.get_file(), i])
		match op.kind:
			RemixOp.Kind.ADD_ENEMY, RemixOp.Kind.SWAP_ENEMY:
				if not RemixOp.SCENES.has(op.scene_kind):
					errors.append("RoomRemix %s: op %d scene_kind '%s' is not a RoomGen enemy" % [room.get_file(), i, op.scene_kind])
				if op.data == null:
					errors.append("RoomRemix %s: op %d (%s) needs a *_remix EnemyData" % [room.get_file(), i, op.describe()])
			RemixOp.Kind.SET:
				if op.property == &"":
					errors.append("RoomRemix %s: op %d SET names no property" % [room.get_file(), i])
	return errors


## Content protocol: the activation condition reads a flag.
func content_flags() -> Dictionary:
	return {"conditions": [active_when] if active_when != "" else []}


func is_active() -> bool:
	return Game.check_condition(active_when)
