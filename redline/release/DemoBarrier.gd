class_name DemoBarrier
extends StaticBody2D
## Demo builds (M9 D6 §2.4 B): a wall over one border exit (an exit into a
## room outside the demo) plus a trigger a little larger than the exit. The
## wall plugs the gap, so the player can never walk past the room's bounds
## into a pit (EscapeTunnel's east gap), and the trigger opens the demo end
## card before the wall is touched. Built at runtime by DemoGate: room scenes
## and door contracts are never edited (D-092).
## Origin: the exit's top-left, like RoomExit.

## Dev console "Barriers: shown" draws every barrier and trigger rect.
static var debug_draw: bool = false

var size: Vector2 = Vector2(16, 64)
var target_room: String = ""
var depth: float = 12.0
var trigger: Area2D
## The exit this barrier covers (its monitoring comes back on remove()).
var exit: RoomExit


func setup(p_exit: RoomExit, p_depth: float) -> DemoBarrier:
	exit = p_exit
	name = "DemoBarrier_%s" % exit.name
	position = exit.position
	size = exit.size
	target_room = exit.target_room
	depth = p_depth
	return self


## Takes the wall down and hands the gap back to its exit (the demo session
## turned off, or the dev bypass turned on, inside this room).
func remove() -> void:
	remove_from_group(&"demo_barrier")
	name = "DemoBarrierRemoved"  # DemoGate skips an exit whose barrier name is still taken
	if is_instance_valid(exit):
		exit.set_deferred("monitoring", true)
	queue_free()


func _ready() -> void:
	add_to_group(&"demo_barrier")
	collision_layer = CombatLayers.WORLD
	collision_mask = 0
	var wall := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	wall.shape = rect
	wall.position = size * 0.5
	add_child(wall)
	trigger = Area2D.new()
	trigger.name = "Trigger"
	trigger.collision_layer = 0
	trigger.collision_mask = CombatLayers.PLAYER_BODY
	trigger.monitorable = false
	var zone := CollisionShape2D.new()
	var grown := RectangleShape2D.new()
	grown.size = size + Vector2.ONE * depth * 2.0
	zone.shape = grown
	zone.position = size * 0.5
	trigger.add_child(zone)
	add_child(trigger)
	trigger.body_entered.connect(_on_body_entered)


## The card opens on each new entry (walking back into the gap reopens it),
## never under a locking scene or another menu (the tree is paused then).
func _on_body_entered(body: Node2D) -> void:
	var player := body as Player
	if player == null or player.combat.dead or Cinematics.locks_input() or get_tree().paused:
		return
	EventBus.demo_boundary_reached.emit(SceneRouter.current_room_path, target_room)


## Trigger rect in the barrier's space (tests and the dev overlay).
func trigger_rect() -> Rect2:
	return Rect2(-Vector2.ONE * depth, size + Vector2.ONE * depth * 2.0)


func _draw() -> void:
	if debug_draw:
		draw_rect(trigger_rect(), Color(1.0, 0.8, 0.2, 0.25))
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.25, 0.2, 0.6))


static func set_debug_draw(on: bool) -> void:
	debug_draw = on
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		for b in tree.get_nodes_in_group(&"demo_barrier"):
			(b as CanvasItem).queue_redraw()
