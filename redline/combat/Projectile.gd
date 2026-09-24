class_name Projectile
extends Node2D
## Fast projectile moved by ray casts each tick so it can't tunnel through
## thin walls or small hurtboxes. Stops on the first world or hurtbox hit.

signal impacted(result: int)

var attack: AttackData
var attacker: Node2D
var velocity: Vector2
var target_mask: int = CombatLayers.ENEMY_HURTBOX
var tags: Array[StringName] = []
var _life: float = 0.0
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
		outcome = box.receive(hit)
	HitSpark.spawn(get_parent(), global_position, -velocity.normalized(), attack.projectile.color, 4)
	impacted.emit(outcome)
	queue_free()


func _draw() -> void:
	var tail := (_trail_from - global_position)
	if tail.length() > attack.projectile.tracer_length:
		tail = tail.normalized() * attack.projectile.tracer_length
	draw_line(tail, Vector2.ZERO, attack.projectile.color, 1.0)
	draw_rect(Rect2(-1, -1, 2, 2), Color.WHITE)
