extends Node
## Loads rooms into the gameplay viewport owned by Main.tscn.
##
## Rooms live inside a low-resolution SubViewport (pixel gameplay) while UI
## renders at native resolution on top (bible §25: high-res UI over pixel play).

var world_root: Node = null
var current_room: Node = null


func register_world_root(root: Node) -> void:
	world_root = root


func goto_room(scene_path: String) -> Node:
	assert(world_root != null, "SceneRouter.world_root not registered")
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("SceneRouter: cannot load room %s" % scene_path)
		return null
	if current_room:
		current_room.queue_free()
	current_room = packed.instantiate()
	world_root.add_child(current_room)
	EventBus.room_loaded.emit(current_room)
	return current_room
