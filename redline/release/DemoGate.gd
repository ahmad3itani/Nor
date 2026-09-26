class_name DemoGate
extends Node
## Demo builds only (M9 D6 §2.4, D-165): Main adds one when
## BuildInfo.is_demo() (the dev Demo page adds one for a demo session). On
## every room load it plugs each border exit (an exit into a room outside the
## demo) with a DemoBarrier, whose trigger opens the demo end card. The
## SceneRouter refusal is the second line of defence for every other route
## (teleports, fast travel, saves, boss restarts).

## Dev: let the dev console walk past the demo boundary (no barriers either).
static var dev_bypass: bool = false


func _ready() -> void:
	name = "DemoGate"
	add_to_group(&"demo_gate")
	EventBus.room_loaded.connect(_on_room_loaded)
	if is_instance_valid(SceneRouter.current_room):
		_on_room_loaded(SceneRouter.current_room)


## Idle in the full game, under the dev bypass and during a challenge run:
## a challenge's FinishLine owns its exit (EscapeTunnel Exit2 would otherwise
## be walled off and open the card mid-run, R05.1).
func _on_room_loaded(room: Node) -> void:
	if not BuildInfo.is_demo() or dev_bypass or Challenges.active() or room == null:
		return
	var c := BuildInfo.config()
	var depth: float = c.barrier_depth if c else 12.0
	for exit in border_exits(room):
		if exit.get_parent().has_node(NodePath("DemoBarrier_%s" % exit.name)):
			continue
		exit.set_deferred("monitoring", false)
		exit.get_parent().add_child(DemoBarrier.new().setup(exit, depth))


## Exits of `room` that lead outside the demo (DM-2 reads the same rule).
static func border_exits(room: Node) -> Array[RoomExit]:
	var out: Array[RoomExit] = []
	for n in room.find_children("*", "RoomExit", true, false):
		var e := n as RoomExit
		if e.target_room != "" and not BuildInfo.room_allowed(e.target_room):
			out.append(e)
	return out


## Adds a gate to the tree if none exists (a demo session started from the
## dev console in a full build). Deferred: callers may be mid-physics.
static func ensure(tree: SceneTree) -> void:
	if tree == null or not tree.get_nodes_in_group(&"demo_gate").is_empty():
		return
	tree.root.add_child.call_deferred(DemoGate.new())


## Frees every gate and the current room's barriers (their exits work again).
static func remove_all(tree: SceneTree) -> void:
	if tree == null:
		return
	for g in tree.get_nodes_in_group(&"demo_gate"):
		g.queue_free()
	clear_barriers(tree)


static func clear_barriers(tree: SceneTree) -> void:
	if tree == null:
		return
	for b in tree.get_nodes_in_group(&"demo_barrier"):
		(b as DemoBarrier).remove()


## Dev: the bypass takes effect in the current room at once (on: the barriers
## go; off: they come back through the gate), not from the next room load.
static func set_dev_bypass(on: bool) -> void:
	dev_bypass = on
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	if on:
		clear_barriers(tree)
	elif is_instance_valid(SceneRouter.current_room):
		for g in tree.get_nodes_in_group(&"demo_gate"):
			(g as DemoGate)._on_room_loaded(SceneRouter.current_room)
