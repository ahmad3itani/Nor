class_name AimAssist
extends RefCounted
## Aim assist (bible §24, D4 §8.1): bends a shot toward the enemy nearest the
## aimed direction, inside a cone and a range that AccessibilityConfig gives
## per Settings.aim_assist (Off / Light / Strong). It never turns Rook around
## (PlayerCombat updates facing before asking) and reads no RNG, so a shot is
## deterministic given positions. Off (cone or range 0) returns `aim` as is.


## candidates: [{pos: Vector2 (body centre), visible: bool}]. Picks the
## smallest angle inside the cone, the nearest on a tie; nothing in the cone
## or in range leaves the aim untouched.
static func adjust(aim: Vector2, from: Vector2, candidates: Array[Dictionary], cone_deg: float, range_px: float) -> Vector2:
	if cone_deg <= 0.0 or range_px <= 0.0 or aim == Vector2.ZERO:
		return aim
	var best := Vector2.ZERO
	var best_angle := INF
	var best_dist := INF
	var cone := deg_to_rad(cone_deg)
	for c in candidates:
		if not bool(c.get("visible", true)):
			continue
		var to: Vector2 = (c.get("pos", from) as Vector2) - from
		var dist := to.length()
		if dist <= 0.001 or dist > range_px:
			continue
		var angle := absf(aim.angle_to(to))
		if angle > cone:
			continue
		if angle < best_angle - 0.0001 or (absf(angle - best_angle) <= 0.0001 and dist < best_dist):
			best_angle = angle
			best_dist = dist
			best = to
	return aim if best == Vector2.ZERO else best.normalized()


## The cone and range for a Settings.aim_assist index ([0, 0] when Off or the
## config is missing).
static func cone_and_range(index: int, cfg: AccessibilityConfig) -> Vector2:
	if cfg == null or index <= 0 or cfg.aim_cone_deg.is_empty() or cfg.aim_range_px.is_empty():
		return Vector2.ZERO
	var i := clampi(index, 0, mini(cfg.aim_cone_deg.size(), cfg.aim_range_px.size()) - 1)
	return Vector2(cfg.aim_cone_deg[i], cfg.aim_range_px[i])


## Live targets from the "enemies" group: the dead are skipped, an off-screen
## body is skipped when the config asks for it, and one hidden behind WORLD
## geometry is marked not visible (a ray from the muzzle, excluding Rook).
static func candidates_for(player: Node2D, from: Vector2, range_px: float, require_on_screen: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if player == null or not player.is_inside_tree():
		return out
	var screen := Rect2()
	var vp := player.get_viewport()
	if require_on_screen and vp != null:
		screen = vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()
	var space := player.get_world_2d().direct_space_state
	var exclude: Array[RID] = []
	if player is CollisionObject2D:
		exclude.append((player as CollisionObject2D).get_rid())
	for n in player.get_tree().get_nodes_in_group(&"enemies"):
		var e := n as Enemy
		if e == null or not is_instance_valid(e) or not e.is_inside_tree() or e.is_dead() or e.data == null:
			continue
		var pos := e.body_rect().get_center()
		if from.distance_to(pos) > range_px:
			continue
		if require_on_screen and vp != null and not screen.has_point(pos):
			continue
		var q := PhysicsRayQueryParameters2D.create(from, pos, CombatLayers.WORLD, exclude)
		var hit := space.intersect_ray(q)
		out.append({"pos": pos, "visible": hit.is_empty()})
	return out
