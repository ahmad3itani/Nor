@tool
class_name Doorway
extends RoomTemplate
## A room edge exit plus its matching entry spawn, always placed the same way
## (exit flush with the edge, spawn 36 px inside, facing in), so doorways line
## up on the world map and never spawn Rook inside the exit.
## Origin = floor point at the room edge.

@export_enum("Left:-1", "Right:1") var side: int = 1:
	set(v):
		side = v
		_rebuild_later()
@export var entry_id: StringName = &"from_x":
	set(v):
		entry_id = v
		_rebuild_later()
@export_file("*.tscn") var target_room: String = "":
	set(v):
		target_room = v
		_rebuild_later()
@export var target_entry: StringName = &"":
	set(v):
		target_entry = v
		_rebuild_later()
@export var requires_flag: String = "":
	set(v):
		requires_flag = v
		_rebuild_later()
@export var height: float = 96.0

const SPAWN_INSET := 36.0


func _generate() -> void:
	var exit := RoomExit.new()
	exit.name = "Exit"
	exit.size = Vector2(16, height)
	exit.position = Vector2(0.0 if side > 0 else -16.0, -height)
	exit.target_room = target_room
	exit.target_entry = target_entry
	exit.requires_flag = requires_flag
	_add(exit)
	var spawn := SpawnMarker.new()
	spawn.name = "Spawn_%s" % entry_id
	spawn.spawn_id = entry_id
	spawn.facing = -side
	spawn.position = Vector2(-side * SPAWN_INSET, 0)
	_add(spawn)
