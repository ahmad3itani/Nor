extends Node
## Loads rooms into the gameplay viewport owned by Main.tscn.
##
## Rooms live inside a low-resolution SubViewport (pixel gameplay) while UI
## renders at native resolution on top (bible §25: high-res UI over pixel play).
## Transitions carry the player's velocity and facing into the next room so
## running through a door never kills momentum (pillar §2.1).

const FADE_TIME := 0.12

var world_root: Node = null
var current_room: Node = null
var current_room_path: String = ""
## Entry marker the next room should spawn the player at (&"" = default spawn).
var pending_entry: StringName = &""
## {"velocity": Vector2, "facing": int} carried through a transition, or empty.
var pending_carry: Dictionary = {}
var transitioning: bool = false
var _fade: ColorRect


func register_world_root(root: Node) -> void:
	world_root = root


func register_fade(rect: ColorRect) -> void:
	_fade = rect


func goto_room(scene_path: String, entry: StringName = &"", carry: Dictionary = {}) -> Node:
	assert(world_root != null, "SceneRouter.world_root not registered")
	if not BuildInfo.room_allowed(scene_path) and not DemoGate.dev_bypass:
		push_error("SceneRouter: %s is outside the demo" % scene_path)
		return null
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("SceneRouter: cannot load room %s" % scene_path)
		return null
	if current_room and is_instance_valid(current_room):
		EventBus.room_leaving.emit(current_room)
		world_root.remove_child(current_room)
		current_room.queue_free()
	pending_entry = entry
	pending_carry = carry
	current_room_path = scene_path
	current_room = packed.instantiate()
	# D-153: NG+ remix ops (0 unless a remix is active), before _ready runs.
	RemixLibrary.apply(current_room, scene_path)
	world_root.add_child(current_room)
	pending_entry = &""
	pending_carry = {}
	EventBus.room_loaded.emit(current_room)
	return current_room


## Fade out, swap rooms, fade in. Safe to call from physics callbacks.
func transition_to(scene_path: String, entry: StringName = &"", carry: Dictionary = {}) -> void:
	# Demo builds: an exit into content outside the demo opens the end card
	# (MenuHost) instead of loading the room.
	if not BuildInfo.room_allowed(scene_path) and not DemoGate.dev_bypass:
		EventBus.demo_boundary_reached.emit(current_room_path, scene_path)
		return
	if transitioning:
		return
	transitioning = true
	await _fade_to(1.0)
	goto_room.call_deferred(scene_path, entry, carry)
	await get_tree().process_frame
	await get_tree().process_frame
	await _fade_to(0.0)
	transitioning = false


func _fade_to(alpha: float) -> void:
	if _fade == null:
		return
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", alpha, FADE_TIME)
	await tween.finished
