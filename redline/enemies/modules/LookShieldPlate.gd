class_name LookShieldPlate
extends LookModule
## The shield plate on the facing side, shown while the brain's guard is up.

@export var color: Color = Color("7fb6d9")


func draw(b: ModularBehavior, canvas: Node2D) -> void:
	var guard := b.brain().guard
	if guard == null or not guard.guard_up(b):
		return
	var e := b.enemy
	var h := e.data.body_size.y
	var x := e.data.body_size.x * 0.5 if e.facing > 0 else -e.data.body_size.x * 0.5 - 4.0
	canvas.draw_rect(Rect2(x, -h + 2.0, 4.0, h - 4.0), color)
