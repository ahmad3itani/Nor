class_name SpriteActor
extends AnimatedSprite2D
## Plays a SpriteSheetSpec with its origin (feet) on this node, picking the
## first animation that exists from a fallback list, so partial art sets work
## (e.g. no "windup" yet -> "attack" -> "idle").

var spec: SpriteSheetSpec


static func create(p_spec: SpriteSheetSpec) -> SpriteActor:
	var frames := p_spec.build_frames()
	if frames == null:
		return null
	var a := SpriteActor.new()
	a.spec = p_spec
	a.sprite_frames = frames
	a.centered = true
	a.offset = Vector2(p_spec.cell_size) * 0.5 - Vector2(p_spec.origin)
	a.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return a


## Plays the first of `names` that the sheet has. Returns the one playing.
func play_first(names: Array) -> StringName:
	for item in names:
		var n := StringName(item)
		if sprite_frames.has_animation(n):
			if animation != n or not is_playing():
				play(n)
			return n
	return &""


func face(dir: int) -> void:
	flip_h = dir < 0
