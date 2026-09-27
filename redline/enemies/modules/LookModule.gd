class_name LookModule
extends Resource
## Placeholder silhouette extras drawn on the enemy (readable at speed until
## real sprites arrive; see Docs/ART_BIBLE.md).


func draw(_b: ModularBehavior, _canvas: Node2D) -> void:
	pass


## True when the canvas (EnemyVisual) shows a sprite: looks then skip their
## placeholder body parts and keep only the code-drawn readability cues
## (guard rim, eye pupil). Visual only (T05).
static func sprite_mode(canvas: Node2D) -> bool:
	return canvas != null and canvas.has_method(&"uses_sprite") and bool(canvas.call(&"uses_sprite"))
