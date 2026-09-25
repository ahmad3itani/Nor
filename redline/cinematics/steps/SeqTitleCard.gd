class_name SeqTitleCard
extends SequenceStep
## Title card. use_arena_title reads BossArena.boss_title/boss_subtitle, so
## the arena stays the one source of truth for a boss's name.

@export var title: String = ""
@export var subtitle: String = ""
@export var use_arena_title: bool = false
@export var seconds: float = 1.6


func run(p: SequencePlayer) -> void:
	var ov := p.overlay()
	if not is_instance_valid(ov):
		return
	var t := _texts(p)
	ov.show_title(t[0], t[1])
	await p.wait(seconds)
	ov.clear_title()


func finish(p: SequencePlayer) -> void:
	var ov := p.overlay()
	if is_instance_valid(ov):
		ov.clear_title()


func _texts(p: SequencePlayer) -> PackedStringArray:
	if use_arena_title and p.ctx and is_instance_valid(p.ctx.arena):
		return PackedStringArray([p.ctx.arena.boss_title, p.ctx.arena.boss_subtitle])
	return PackedStringArray([title, subtitle])


func validate(v: SequenceValidation) -> PackedStringArray:
	var out := PackedStringArray()
	if use_arena_title:
		out.append_array(v.actor_errors("@arena"))
	elif title.strip_edges() == "":
		out.append("empty title")
	return out


func nominal_seconds() -> float:
	return seconds
