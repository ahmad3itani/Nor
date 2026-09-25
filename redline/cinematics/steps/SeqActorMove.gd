class_name SeqActorMove
extends SequenceStep
## Moves an NPC, or only a boss's Visual child (visual_only: the body and the
## fight start stay put). Never Rook (R1: route positions stay valid).

@export var actor: String = ""
## Start offset from the rest position (e.g. (0,-48): drops from a hatch).
@export var from_offset: Vector2 = Vector2.ZERO
## End: room-local when not relative, else an offset from rest (always an
## offset when visual_only).
@export var to: Vector2 = Vector2.ZERO
@export var relative: bool = true
@export var seconds: float = 1.0
@export var visual_only: bool = false


func run(p: SequencePlayer) -> void:
	var n := _mover(p)
	if n == null:
		return
	p.note_abort_restore(n, &"position")
	var rest: Vector2 = p.memo(self, "rest", Vector2.ZERO if visual_only else n.position)
	n.position = rest + from_offset
	var t := p.adopt(p.create_tween())
	t.tween_property(n, "position", _end(rest), seconds)
	await p.wait_tween(t)


func finish(p: SequencePlayer) -> void:
	var n := _mover(p)
	if n:
		var rest: Variant = p.memo(self, "rest")
		n.position = _end(rest if rest != null else (Vector2.ZERO if visual_only else n.position))


func _end(rest: Vector2) -> Vector2:
	return rest + to if (relative or visual_only) else to


func _mover(p: SequencePlayer) -> Node2D:
	var n := p.ctx.resolve(actor) if p.ctx else null
	if n and visual_only:
		return n.get_node_or_null("Visual") as Node2D
	return n as Node2D


func validate(v: SequenceValidation) -> PackedStringArray:
	var out := v.actor_errors(actor)
	if actor == "@rook":
		out.append("SeqActorMove may not move @rook (R1; use SeqRookPose)")
	return out


func nominal_seconds() -> float:
	return seconds
