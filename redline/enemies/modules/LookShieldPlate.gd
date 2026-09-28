class_name LookShieldPlate
extends LookModule
## The shield plate on the facing side, shown while the brain's guard is up.

@export var color: Color = Color("7fb6d9")

## Fallback rim when the sheet cannot be measured: shield_sheet's idle plate
## relative to the sheet origin (facing right), the outer outline column and
## the slab's top and bottom rows (bottom exclusive).
const SPRITE_RIM_X := 15.0
const SPRITE_RIM_TOP := -36.0
const SPRITE_RIM_BOTTOM := -8.0
## A row whose outer edge steps in by this much or more below the one above
## it ends the slab (the legs start well inside the plate).
const SLAB_END_STEP := 3

## "texture_path|anim|frame" -> PackedInt32Array [top_row, edge_x...],
## relative to the anim's origin, facing right; empty when not measurable.
static var _edge_cache := {}


func draw(b: ModularBehavior, canvas: Node2D) -> void:
	var guard := b.brain().guard
	if guard == null or not guard.guard_up(b):
		return
	var e := b.enemy
	var h := e.data.body_size.y
	var x := e.data.body_size.x * 0.5 if e.facing > 0 else -e.data.body_size.x * 0.5 - 4.0
	if sprite_mode(canvas):
		# Sprite: the sheet draws a plain steel slab; the guard-up cue stays a
		# code rim in guard blue on the slab's outer outline, row by row, for
		# the pose and frame on screen (the slab tilts in windup and attack),
		# moved with the sprite (knock, hitstop shake, sprite offset).
		var actor := canvas.get(&"actor") as SpriteActor
		var at := actor.position if actor else Vector2.ZERO
		var edges := PackedInt32Array()
		if actor and actor.spec:
			edges = plate_edges(actor.spec, actor.animation, actor.frame)
		for r in rim_rects(edges, e.facing > 0):
			canvas.draw_rect(Rect2(r.position + at, r.size), color)
		return
	canvas.draw_rect(Rect2(x, -h + 2.0, 4.0, h - 4.0), color)


## The rim as 1 px wide rects (runs of rows on the same column), relative to
## the sprite's origin; mirrored when facing left (a flipped pixel column c
## lands on [-c-1, -c)). `edges` from plate_edges; empty -> the fallback.
static func rim_rects(edges: PackedInt32Array, facing_right: bool) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if edges.size() < 2:
		var fx := SPRITE_RIM_X if facing_right else -SPRITE_RIM_X - 1.0
		out.append(Rect2(fx, SPRITE_RIM_TOP, 1.0, SPRITE_RIM_BOTTOM - SPRITE_RIM_TOP))
		return out
	var top := edges[0]
	var i := 1
	while i < edges.size():
		var j := i
		while j + 1 < edges.size() and edges[j + 1] == edges[i]:
			j += 1
		var c := float(edges[i])
		var rx := c if facing_right else -c - 1.0
		out.append(Rect2(rx, float(top + i - 1), 1.0, float(j - i + 1)))
		i = j + 1
	return out


## The slab's outer edge in `anim` frame `frame` of `spec`: [top_row,
## edge_x per row from the top down], relative to the anim's origin, facing
## right. The slab is the front-most part from the top of the figure down
## until the edge steps in by SLAB_END_STEP (the legs). Measured once from
## the sheet and cached; empty when the sheet or frame is missing.
static func plate_edges(spec: SpriteSheetSpec, anim: StringName, frame: int) -> PackedInt32Array:
	var k := "%s|%s|%d" % [spec.texture_path, anim, frame]
	if _edge_cache.has(k):
		return _edge_cache[k]
	var out := PackedInt32Array()
	var a: SpriteAnim = null
	for item in spec.animations:
		if item != null and item.name == anim:
			a = item
	var tex := spec.load_texture() if a != null and frame >= 0 and frame < a.frame_count else null
	var img := tex.get_image() if tex else null
	if img:
		if img.is_compressed():
			img.decompress()
		var cell := spec.cell_size
		var o := spec.origin_for(anim)
		var x0 := (a.first_frame + frame) * cell.x
		var y0 := a.row * cell.y
		var prev := -1
		for y in cell.y:
			var edge := -1
			if x0 + cell.x <= img.get_width() and y0 + y < img.get_height():
				for x in range(cell.x - 1, -1, -1):
					if img.get_pixel(x0 + x, y0 + y).a > 0.5:
						edge = x
						break
			if out.is_empty():
				if edge >= 0:
					out.append(y - o.y)
					out.append(edge - o.x)
					prev = edge
				continue
			if edge < 0 or prev - edge >= SLAB_END_STEP:
				break
			out.append(edge - o.x)
			prev = edge
	_edge_cache[k] = out
	return out
