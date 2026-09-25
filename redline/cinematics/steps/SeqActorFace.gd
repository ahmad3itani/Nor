class_name SeqActorFace
extends SequenceStep
## Turns an actor (NPC, boss, Rook) to face left (-1) or right (1).

@export var actor: String = ""
@export_enum("Left:-1", "Right:1") var facing: int = -1


func finish(p: SequencePlayer) -> void:
	var n := p.ctx.resolve(actor) if p.ctx else null
	if n == null or not ("facing" in n):
		return
	n.set("facing", facing)
	# NPC.facing has no setter redraw.
	if n is CanvasItem:
		(n as CanvasItem).queue_redraw()


func validate(v: SequenceValidation) -> PackedStringArray:
	var out := v.actor_errors(actor)
	if facing != -1 and facing != 1:
		out.append("facing must be -1 or 1")
	return out
