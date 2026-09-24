class_name CombatQuery
extends RefCounted
## Physics queries used to deliver hits.


## Hurtboxes overlapping a world-space rect, filtered by collision mask.
static func hurtboxes_in_rect(world: World2D, rect: Rect2, mask: int) -> Array[Hurtbox]:
	var out: Array[Hurtbox] = []
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, rect.get_center())
	params.collision_mask = mask
	params.collide_with_areas = true
	params.collide_with_bodies = false
	for result in world.direct_space_state.intersect_shape(params, 32):
		var box := result["collider"] as Hurtbox
		if box and not out.has(box):
			out.append(box)
	return out


## True if the rect overlaps any area on the given mask (hazards).
static func rect_touches_areas(world: World2D, rect: Rect2, mask: int) -> bool:
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, rect.get_center())
	params.collision_mask = mask
	params.collide_with_areas = true
	params.collide_with_bodies = false
	return not world.direct_space_state.intersect_shape(params, 1).is_empty()
