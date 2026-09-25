class_name SeqCamera
extends SequenceStep
## Frames an actor or a point (zoom 1.0..1.5, §26), or releases to Rook.

## Actor id to frame, or "" = the room-local point (generator coordinates).
@export var target: String = ""
@export var point: Vector2 = Vector2.ZERO
@export var offset: Vector2 = Vector2.ZERO
@export var seconds: float = 1.0
@export_range(1.0, 1.5) var zoom: float = 1.0
@export var ease_type: Tween.EaseType = Tween.EASE_IN_OUT
@export var release: bool = false


func run(p: SequencePlayer) -> void:
	_apply(p, seconds / p.speed())
	await p.wait(seconds)


func finish(p: SequencePlayer) -> void:
	_apply(p, 0.0)


## The camera eases on its own physics clock; `s` is already AUTO-scaled.
func _apply(p: SequencePlayer, s: float) -> void:
	var cam := p.ctx.camera if p.ctx else null
	if not is_instance_valid(cam):
		return
	p.note_camera()
	if release:
		cam.release(s)
		if s <= 0.0:
			cam.snap_to_target()
		return
	if target == "":
		var room := p.ctx.room as Node2D
		cam.direct((room.to_global(point) if is_instance_valid(room) else point) + offset, s, zoom, ease_type)
		return
	var n := p.ctx.resolve(target) as Node2D
	if n and offset == Vector2.ZERO and s > 0.0:
		cam.direct_node(n, s, zoom)  # keeps tracking a moving actor
	elif n:
		cam.direct(n.global_position + offset, s, zoom, ease_type)


func validate(v: SequenceValidation) -> PackedStringArray:
	var out := PackedStringArray() if zoom >= 1.0 and zoom <= 1.5 else PackedStringArray(["zoom %.2f outside 1.0..1.5" % zoom])
	if target != "" and not release:
		out.append_array(v.actor_errors(target))
	return out


func nominal_seconds() -> float:
	return seconds


func locking_only() -> bool:
	return true
