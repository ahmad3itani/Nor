class_name Projectile
extends Node2D
## Fast projectile moved by ray casts each tick so it can't tunnel through
## thin walls or small hurtboxes. Stops on the first world or hurtbox hit.
##
## M9 (T12, D4 §7.2/7.3): high contrast gives the tracer and head a 1 px dark
## outline, and with a colour-blind palette on, shots aimed at Rook take the
## palette's danger colour (the default palette keeps each weapon's colour).

signal impacted(result: int)

## High-contrast outline under the tracer and head.
const OUTLINE_COLOR := Color(0.02, 0.02, 0.04, 1.0)

var attack: AttackData
var attacker: Node2D
var velocity: Vector2
var target_mask: int = CombatLayers.ENEMY_HURTBOX
var tags: Array[StringName] = []
var damage_mult: float = 1.0
var bonus_vs_staggered: float = 0.0
## Hurtboxes the shot may still pass through (Heavy Revolver).
var pierce_left: int = 0
var _life: float = 0.0
var _excluded: Array[RID] = []
var _trail_from: Vector2
## First ray starts here (the shooter's body) instead of the muzzle, so
## point-blank shots hit an enemy the muzzle is already inside of.
var _first_ray_from: Vector2
var _first_tick: bool = true


static func spawn(parent: Node, p_attacker: Node2D, p_attack: AttackData, at: Vector2,
		direction: Vector2, p_target_mask: int, p_tags: Array[StringName] = [],
		ray_origin: Vector2 = Vector2.INF) -> Projectile:
	var p := Projectile.new()
	p.attack = p_attack
	p.attacker = p_attacker
	p.velocity = direction.normalized() * p_attack.projectile.speed
	p.target_mask = p_target_mask
	p.tags = p_tags.duplicate()
	p._life = p_attack.projectile.lifetime
	p.pierce_left = p_attack.projectile.pierce
	p.position = at
	p._trail_from = at
	p._first_ray_from = ray_origin if ray_origin != Vector2.INF else at
	parent.add_child(p)
	return p


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	var from := global_position
	var to := from + velocity * delta
	var params := PhysicsRayQueryParameters2D.create(from, to, CombatLayers.WORLD | target_mask)
	params.collide_with_areas = true
	params.collide_with_bodies = true
	params.exclude = _excluded
	if _first_tick:
		_first_tick = false
		params.from = _first_ray_from
		# The shooter may be standing inside the target (overlapping bodies).
		params.hit_from_inside = true
	var result := get_world_2d().direct_space_state.intersect_ray(params)
	_trail_from = from
	if result.is_empty():
		global_position = to
		queue_redraw()
		return
	global_position = result["position"]
	var outcome := CombatResult.IGNORED
	var box := result["collider"] as Hurtbox
	if box:
		var dir := velocity.normalized()
		var kb := dir * attack.knockback.x + Vector2(0.0, attack.knockback.y)
		# The shooter may have died while the shot was in flight; never hand a
		# freed object to receivers (calling into it crashes the engine).
		var source: Node2D = attacker if is_instance_valid(attacker) else null
		var hit := HitInfo.create(source, attack, kb, dir, tags)
		hit.source_position = from
		hit.damage_mult = damage_mult
		hit.bonus_vs_staggered = bonus_vs_staggered
		outcome = box.receive(hit)
		if pierce_left > 0 and outcome != CombatResult.BLOCKED:
			pierce_left -= 1
			_excluded.append(box.get_rid())
			HitSpark.spawn(get_parent(), global_position, velocity.normalized(), attack.projectile.color, 4)
			impacted.emit(outcome)
			return
	HitSpark.spawn(get_parent(), global_position, -velocity.normalized(), attack.projectile.color, 4)
	impacted.emit(outcome)
	queue_free()


func _draw() -> void:
	var tail := (_trail_from - global_position)
	if tail.length() > attack.projectile.tracer_length:
		tail = tail.normalized() * attack.projectile.tracer_length
	if UiTheme.high_contrast():
		draw_line(tail, Vector2.ZERO, OUTLINE_COLOR, 3.0)
		draw_rect(Rect2(-2, -2, 4, 4), OUTLINE_COLOR)
	draw_line(tail, Vector2.ZERO, shot_color(), 1.0)
	draw_rect(Rect2(-1, -1, 2, 2), Color.WHITE)


## The tracer colour: the weapon's own, or Palette danger for enemy shots when
## a colour-blind palette is chosen.
func shot_color() -> Color:
	if Palette.mode() != 0 and (target_mask & CombatLayers.PLAYER_HURTBOX) != 0:
		return Palette.color(&"danger")
	return attack.projectile.color
