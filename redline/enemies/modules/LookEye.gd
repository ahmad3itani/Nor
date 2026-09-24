class_name LookEye
extends LookModule
## An eye that tracks the target (sentries: "it sees you").

@export var color: Color = Color("ff3b4f")


func draw(b: ModularBehavior, canvas: Node2D) -> void:
	var e := b.enemy
	var c := Vector2(0, -e.data.body_size.y * 0.5)
	var look := Vector2.ZERO
	if is_instance_valid(e.target):
		look = (e.target.global_position + Vector2(0, -16) - e.global_position - c).normalized() * 2.0
	canvas.draw_rect(Rect2(c + look - Vector2(2, 2), Vector2(4, 4)), color)
