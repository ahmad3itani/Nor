@tool
class_name EntryCheckpoint
extends Area2D
## Mid-room pre-Anchor respawn point (D-088). Long teaching rooms before the
## first Anchor (FirstPursuit) would otherwise send a dying newcomer back to
## the room's door; crossing this line moves the respawn to `spawn_id` instead.
## It only feeds Game.note_room_entry, which ignores it once any Anchor has
## been rested at, so Anchors always win. Invisible in play; debug_draw
## outlines it. Origin is the top-left corner.

@export var size: Vector2 = Vector2(16, 200):
	set(v):
		size = v.snapped(Vector2.ONE)
		_rebuild()
## The SpawnMarker (same room) a death returns to after crossing this.
@export var spawn_id: StringName = &""

var _shape_node: CollisionShape2D


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = CombatLayers.PLAYER_BODY
	_rebuild()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _shape_node == null:
		_shape_node = CollisionShape2D.new()
		add_child(_shape_node)
	var rect := RectangleShape2D.new()
	rect.size = size
	_shape_node.shape = rect
	_shape_node.position = size * 0.5
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		Game.note_room_entry(SceneRouter.current_room_path, spawn_id)


## Content protocol (ContentValidator._check_protocol): the spawn must exist,
## or a death after crossing would fall back to the room's default spawn.
func content_errors(room: Node) -> PackedStringArray:
	if spawn_id == &"":
		return PackedStringArray(["EntryCheckpoint has no spawn_id"])
	for n in room.find_children("*", "SpawnMarker", true, false):
		if (n as SpawnMarker).spawn_id == spawn_id:
			return PackedStringArray()
	return PackedStringArray(["EntryCheckpoint names spawn '%s' but no SpawnMarker has it" % spawn_id])


## HitboxView hook: an outline in global coordinates.
func debug_draw(canvas: CanvasItem) -> void:
	canvas.draw_rect(Rect2(global_position, size), Color(0.49, 1.0, 0.6, 0.8), false, 1.0)


func _draw() -> void:
	# Editor only: in play it is invisible (the debug view outlines it).
	if Engine.is_editor_hint():
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.49, 1.0, 0.6, 0.6), false, 1.0)
