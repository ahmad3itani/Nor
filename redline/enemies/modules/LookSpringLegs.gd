class_name LookSpringLegs
extends LookModule
## Spring legs that compress during the wind-up ("jumper" at a glance).

@export var color: Color = Color("d9d4e6")


func draw(b: ModularBehavior, canvas: Node2D) -> void:
	var squat := 3.0 if b.enemy.ai == Enemy.AI.WINDUP else 0.0
	var w := b.enemy.data.body_size.x
	canvas.draw_rect(Rect2(-w * 0.5 - 2, -3 + squat, 3, 3), color)
	canvas.draw_rect(Rect2(w * 0.5 - 1, -3 + squat, 3, 3), color)
