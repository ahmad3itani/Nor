class_name MapRoomData
extends Resource
## Where one room sits on the world map (bible §20). Offsets are in world
## pixels, so a room's own coordinates + offset = its place in the city;
## tests check that every exit meets its target room's entry on the map.

@export_file("*.tscn") var room_path: String = ""
@export var district: String = "lowlight"
@export var offset: Vector2 = Vector2.ZERO


func room_id() -> String:
	return room_path.get_file().get_basename()
