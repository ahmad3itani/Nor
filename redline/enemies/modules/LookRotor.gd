class_name LookRotor
extends LookModule
## Rotor bar so the silhouette reads as "flying".

@export var color: Color = Color("d9d4e6")


func draw(b: ModularBehavior, canvas: Node2D) -> void:
	var w := b.enemy.data.body_size.x + 6.0
	canvas.draw_rect(Rect2(-w * 0.5, -b.enemy.data.body_size.y - 3.0, w, 1.0), color)
