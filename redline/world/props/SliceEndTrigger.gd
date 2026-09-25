@tool
class_name SliceEndTrigger
extends Area2D
## Shown once when the player returns to the Relay after beating Warden
## Krail: marks the end of Act I's Lowlight arc and points at the Dash gates.

@export var size: Vector2 = Vector2(200, 100)
## M8: the Act I close (data/sequences/act1_close.tres) plays before the card.
## null = the M7 behaviour (the card at once).
@export var sequence: SequenceData

## True while the close plays (no re-entry).
var _busy: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = CombatLayers.PLAYER_BODY
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = size * 0.5
	add_child(shape)
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body is Player or _busy or not Game.has_flag("warden_krail_defeated") or Game.has_flag("slice_end_seen"):
		return
	_busy = true
	if sequence:
		var res := await Cinematics.play(sequence, SequenceContext.for_room(_room()))
		# Refused (another play owns Cinematics) or aborted (Save & Quit runs
		# CinematicMode.abort_all() before it saves; a room leave aborts too):
		# nothing is marked, so the close replays from its start next time.
		if res.refused or res.aborted() or not is_inside_tree():
			_busy = false
			return
	# Set after the scene, not before: a quit mid-scene must replay it.
	Game.set_flag("slice_end_seen")
	EventBus.slice_completed.emit()
	_busy = false


func _room() -> Room:
	var n: Node = get_parent()
	while n != null and not (n is Room):
		n = n.get_parent()
	return n as Room if n else SceneRouter.current_room as Room


## ContentValidator protocol: the close's flags (act1_complete, its seen
## flag, the lines' conditions).
func content_flags() -> Dictionary:
	return sequence.content_flags() if sequence else {}


func content_errors(room: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if sequence and sequence.room != room.scene_file_path:
		out.append("sequence %s is authored for %s, not this room" % [sequence.id, sequence.room if sequence.room != "" else "no room"])
	return out
