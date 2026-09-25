class_name SeqActorFlash
extends SequenceStep
## Pulses an actor's modulate (the Core stirs, an eye opens). With
## Settings.flash_reduction: one steady tint instead of pulses (§24).

@export var actor: String = ""
@export var color: Color = Color(0.9, 0.95, 1.0)
@export var seconds: float = 0.6
@export var pulses: int = 2


func run(p: SequencePlayer) -> void:
	var n := p.ctx.resolve(actor) as CanvasItem if p.ctx else null
	if n == null:
		return
	var base: Color = p.memo(self, "base", n.modulate)
	var t := p.adopt(p.create_tween())
	if Settings.flash_reduction or pulses <= 0:
		n.modulate = base.lerp(color, 0.5)
		t.tween_interval(seconds)
		t.tween_property(n, "modulate", base, 0.0)
	else:
		var half := seconds / float(pulses * 2)
		for i in pulses:
			t.tween_property(n, "modulate", color, half)
			t.tween_property(n, "modulate", base, half)
	await p.wait_tween(t)


func finish(p: SequencePlayer) -> void:
	var n := p.ctx.resolve(actor) as CanvasItem if p.ctx else null
	var base: Variant = p.memo(self, "base")
	if n and base != null:
		n.modulate = base


func validate(v: SequenceValidation) -> PackedStringArray:
	return v.actor_errors(actor)


func nominal_seconds() -> float:
	return seconds
