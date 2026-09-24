class_name Enemy
extends CharacterBody2D
## Shared enemy body (bible §16, §32): perception, attack execution with
## telegraphs, health/poise/stagger, knockback and launch physics, impacts
## with other bodies/walls, hazards, hitstop and death. Archetype decisions
## come from the EnemyBehavior child; numbers come from EnemyData.
##
## AI flow: IDLE -> ENGAGE -> WINDUP -> ACTIVE -> RECOVER -> ENGAGE
##          any -> STAGGER / LAUNCHED -> ENGAGE;  any -> DEAD

enum AI { IDLE, ENGAGE, WINDUP, ACTIVE, RECOVER, STAGGER, LAUNCHED, DEAD }

const IMPACT_ATTACK := preload("res://data/combat/impact_attack.tres")
const HAZARD_ATTACK := preload("res://data/combat/hazard_attack.tres")
## Upward knockback beyond this makes the enemy airborne ("launched").
const LAUNCH_THRESHOLD := 140.0
const DEATH_FLIGHT_TIME := 0.45
const SEPARATION_RADIUS := 14.0

signal died(enemy: Enemy)

@export var data: EnemyData
## False = practice dummy: takes hits and physics but never engages or attacks.
@export var ai_enabled: bool = true

var ai: AI = AI.IDLE
var ai_time: float = 0.0
var health: float
var poise: float
var facing: int = -1
var target: Player
var current_attack: AttackData
## Direction locked at the end of the wind-up (projectile attacks aim here).
var attack_aim: Vector2 = Vector2.LEFT
var attack_cooldown: float = 0.0
var hitstop_timer: float = 0.0
var flash_timer: float = 0.0
var last_hit: HitInfo
var _attack_hit_ids: Dictionary = {}
var _impacted: Dictionary = {}
var _wall_slammed: bool = false
var _has_token: bool = false
var _stagger_duration: float = 0.0
## Multiplies wind-up time (bosses speed up in later phases). Never below 0.6.
var telegraph_scale: float = 1.0

@onready var behavior: EnemyBehavior = $Behavior
@onready var hurtbox: Hurtbox = $Hurtbox


func _ready() -> void:
	add_to_group(&"enemies")
	health = data.max_health
	poise = data.max_poise
	collision_layer = CombatLayers.ENEMY_BODY
	collision_mask = CombatLayers.WORLD | CombatLayers.ONE_WAY
	floor_snap_length = 4.0
	var body := RectangleShape2D.new()
	body.size = data.body_size
	$Shape.shape = body
	$Shape.position = Vector2(0, -data.body_size.y * 0.5)
	var hb := RectangleShape2D.new()
	hb.size = data.body_size + Vector2(2, 2)
	$Hurtbox/Shape.shape = hb
	$Hurtbox/Shape.position = Vector2(0, -data.body_size.y * 0.5)
	hurtbox.collision_layer = CombatLayers.ENEMY_HURTBOX
	behavior.setup(self)


func is_dead() -> bool:
	return ai == AI.DEAD


func body_rect() -> Rect2:
	return Rect2(global_position - Vector2(data.body_size.x * 0.5, data.body_size.y), data.body_size)


func is_airborne_physics() -> bool:
	if data.anchored:
		return false
	return not data.flying or ai == AI.STAGGER or ai == AI.LAUNCHED or ai == AI.DEAD


func set_ai(next: AI) -> void:
	if next != AI.WINDUP and next != AI.ACTIVE and next != AI.RECOVER:
		_release_token()
		current_attack = null
	ai = next
	ai_time = 0.0
	if next == AI.LAUNCHED:
		_impacted.clear()
		_wall_slammed = false


func _physics_process(delta: float) -> void:
	if hitstop_timer > 0.0:
		hitstop_timer -= delta
		return
	ai_time += delta
	behavior.tick(delta)
	flash_timer = maxf(flash_timer - delta, 0.0)
	attack_cooldown = maxf(attack_cooldown - delta, 0.0)
	_acquire_target()

	match ai:
		AI.IDLE:
			_brake(delta)
			if ai_enabled and target and behavior.distance_to_target() <= data.aggro_range:
				set_ai(AI.ENGAGE)
		AI.ENGAGE:
			_engage(delta)
		AI.WINDUP:
			_brake(delta)
			if ai_time >= current_attack.startup * maxf(telegraph_scale, 0.6):
				_begin_active()
		AI.ACTIVE:
			_run_active(delta)
		AI.RECOVER:
			_brake(delta)
			if ai_time >= current_attack.recovery:
				attack_cooldown = data.attack_cooldown
				set_ai(AI.ENGAGE if ai_enabled else AI.IDLE)
		AI.STAGGER:
			_brake(delta)
			if ai_time >= _stagger_duration and (data.flying or is_on_floor()):
				set_ai(AI.ENGAGE if ai_enabled else AI.IDLE)
		AI.LAUNCHED:
			_check_body_impacts()
			if ai_time > 0.1 and is_on_floor() and velocity.y >= 0.0:
				_stagger_duration = data.stagger_time * 0.6
				set_ai(AI.STAGGER)
		AI.DEAD:
			_check_body_impacts()
			if ai_time >= data.death_time or (data.death_time <= DEATH_FLIGHT_TIME and ai_time > 0.1 and is_on_floor()):
				_pop()
				return

	if is_airborne_physics():
		velocity.y = minf(velocity.y + data.gravity * delta, data.max_fall_speed)
	var pre_velocity := velocity
	move_and_slide()
	_check_wall_slam(pre_velocity)
	_check_hazards()


# --- Behaviour glue -------------------------------------------------------------

func _acquire_target() -> void:
	if target and is_instance_valid(target):
		return
	target = get_tree().get_first_node_in_group(&"player") as Player


func _engage(delta: float) -> void:
	if target == null or target.combat.dead:
		_brake(delta)
		return
	var desired := behavior.engage_velocity(delta) + _separation()
	if data.flying:
		velocity = velocity.move_toward(desired, data.accel * delta)
	else:
		velocity.x = move_toward(velocity.x, desired.x, data.accel * delta)
	if attack_cooldown <= 0.0:
		var attack := behavior.choose_attack()
		if attack and _request_token():
			current_attack = attack
			_attack_hit_ids.clear()
			attack_aim = _aim_at_target()
			set_ai(AI.WINDUP)
			AudioManager.play_sfx(&"enemy_telegraph")


func _brake(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, data.friction * delta)
	if data.flying and not is_airborne_physics():
		velocity.y = move_toward(velocity.y, 0.0, data.friction * delta)


## Keeps enemies from stacking into one blob (group spacing, bible §32).
func _separation() -> Vector2:
	var push := Vector2.ZERO
	for other in get_tree().get_nodes_in_group(&"enemies"):
		if other == self or (other as Enemy).is_dead():
			continue
		var d: Vector2 = global_position - (other as Node2D).global_position
		if d.length() < SEPARATION_RADIUS:
			push += d.normalized() * 40.0 if d != Vector2.ZERO else Vector2(facing, 0) * 40.0
	if not data.flying:
		push.y = 0.0
	return push


## True if nothing solid blocks the straight line to the target (ranged units).
func has_line_of_sight() -> bool:
	if target == null:
		return false
	var from := global_position + Vector2(0, -data.body_size.y * 0.5)
	var to := target.global_position + Vector2(0, -16)
	var params := PhysicsRayQueryParameters2D.create(from, to, CombatLayers.WORLD)
	return get_world_2d().direct_space_state.intersect_ray(params).is_empty()


func _aim_at_target() -> Vector2:
	if target == null:
		return Vector2(facing, 0)
	var from := global_position + Vector2(0, -data.body_size.y * 0.5)
	return (target.global_position + Vector2(0, -16) - from).normalized()


func _begin_active() -> void:
	set_ai(AI.ACTIVE)
	var proj := current_attack.projectile
	if proj and proj.ground_wave:
		for dir in [-1, 1]:
			Projectile.spawn(get_parent(), self, current_attack, global_position + Vector2(dir * data.body_size.x * 0.5, -proj.wave_height),
				Vector2(dir, 0), CombatLayers.PLAYER_HURTBOX)
		EventBus.camera_shake_requested.emit(current_attack.camera_trauma)
	elif proj:
		attack_aim = _aim_at_target()
		var muzzle := global_position + Vector2(0, -data.body_size.y * 0.5)
		var spread := proj.spread_deg
		for i in proj.pellets:
			var offset := 0.0 if proj.pellets == 1 else lerpf(-spread * 0.5, spread * 0.5, float(i) / (proj.pellets - 1))
			Projectile.spawn(get_parent(), self, current_attack, muzzle, attack_aim.rotated(deg_to_rad(offset)), CombatLayers.PLAYER_HURTBOX)
	if not proj or proj.ground_wave:
		velocity.x = facing * current_attack.lunge_speed
		if current_attack.lunge_vertical != 0.0:
			velocity.y = current_attack.lunge_vertical
	AudioManager.play_sfx(current_attack.swing_sfx)


func _run_active(delta: float) -> void:
	# Zero-damage moves (Krail's backstep) are pure movement: no hit delivery.
	if current_attack.projectile == null and current_attack.damage > 0.0:
		var rect := current_attack.world_hitbox(global_position, facing)
		for box in CombatQuery.hurtboxes_in_rect(get_world_2d(), rect, CombatLayers.PLAYER_HURTBOX):
			var key := box.get_instance_id()
			if _attack_hit_ids.has(key):
				continue
			_attack_hit_ids[key] = true
			var hit := HitInfo.create(self, current_attack, current_attack.world_knockback(facing), Vector2(facing, 0))
			var result := box.receive(hit)
			if result == CombatResult.HIT or result == CombatResult.KILLED:
				hitstop_timer = current_attack.hitstop * Settings.hitstop_scale
		if is_on_floor() and current_attack.lunge_vertical == 0.0:
			velocity.x = move_toward(velocity.x, 0.0, current_attack.ground_friction * delta)
	if ai_time >= current_attack.active:
		if current_attack.follow_up:
			current_attack = current_attack.follow_up
			_attack_hit_ids.clear()
			facing = int(signf(target.global_position.x - global_position.x)) if target and absf(target.global_position.x - global_position.x) > 4.0 else facing
			attack_aim = _aim_at_target()
			ai = AI.WINDUP
			ai_time = 0.0
			AudioManager.play_sfx(&"enemy_telegraph")
		else:
			set_ai(AI.RECOVER)


func _request_token() -> bool:
	var director := get_tree().get_first_node_in_group(&"encounter_director") as EncounterDirector
	_has_token = director == null or director.request_token(self)
	return _has_token


func _release_token() -> void:
	if not _has_token:
		return
	_has_token = false
	var director := get_tree().get_first_node_in_group(&"encounter_director") as EncounterDirector
	if director:
		director.release_token(self)


# --- Receiving hits ---------------------------------------------------------------

func receive_hit(hit: HitInfo) -> int:
	if is_dead():
		return CombatResult.IGNORED
	last_hit = hit
	var scale_stop := Settings.hitstop_scale
	if behavior.blocks(hit):
		poise -= hit.attack.poise_damage * 0.5
		velocity.x = signf(hit.knockback.x) * 50.0 / data.mass
		flash_timer = 0.06
		hitstop_timer = hit.attack.hitstop * 0.5 * scale_stop
		if poise > 0.0:
			EventBus.enemy_damaged.emit(self, hit, CombatResult.BLOCKED)
			return CombatResult.BLOCKED
		# Guard broken: fall through as a staggering hit with no damage bonus.

	var dmg := hit.damage()
	if ai == AI.STAGGER or ai == AI.LAUNCHED:
		dmg *= 1.0 + hit.bonus_vs_staggered
	health -= dmg
	poise -= hit.attack.poise_damage
	var staggered := poise <= 0.0
	if staggered:
		poise = data.max_poise
	flash_timer = 0.1
	hitstop_timer = hit.attack.hitstop * scale_stop

	var kb := hit.knockback / data.mass
	if data.anchored:
		kb = Vector2.ZERO
	var resisting := data.anchored or (data.armored and not staggered and ai != AI.STAGGER and ai != AI.LAUNCHED)
	if resisting:
		# Armor: only a shove, and it stays planted.
		velocity.x = kb.x * data.armor_knockback_scale
	else:
		velocity = kb

	if health <= 0.0:
		_die(hit)
		return CombatResult.KILLED
	if not resisting and (kb.y < -LAUNCH_THRESHOLD or (not is_on_floor() and not data.flying) or (data.flying and staggered)):
		set_ai(AI.LAUNCHED)
	elif staggered:
		_stagger_duration = data.stagger_time
		set_ai(AI.STAGGER)
	elif ai == AI.IDLE and ai_enabled:
		set_ai(AI.ENGAGE)
	EventBus.enemy_damaged.emit(self, hit, CombatResult.HIT)
	return CombatResult.HIT


func _die(hit: HitInfo) -> void:
	set_ai(AI.DEAD)
	_impacted.clear()
	hurtbox.set_deferred(&"monitorable", false)
	hurtbox.collision_layer = 0
	AudioManager.play_sfx(&"enemy_die")
	if data.scrap_drop > 0:
		ScrapPickup.burst(get_parent(), global_position + Vector2(0, -data.body_size.y * 0.5), data.scrap_drop)
	EventBus.camera_shake_requested.emit(0.12)
	EventBus.enemy_killed.emit(self, hit)
	died.emit(self)


func _pop() -> void:
	var bursts := 4 if data.death_time > DEATH_FLIGHT_TIME else 1
	for i in bursts:
		HitSpark.spawn(get_parent(), global_position + Vector2(randf_range(-8, 8) * i, -data.body_size.y * 0.5), Vector2.UP, data.color, 16, 160.0 + 40.0 * i)
	queue_free()


# --- Launch physics: bodies, walls and hazards --------------------------------------

## A launched or dying enemy moving fast enough damages other enemies it
## crashes into (bible §8: launched enemies collide). Credit goes to whoever
## launched it, so these count as environmental kills for style/reactor.
func _check_body_impacts() -> void:
	if velocity.length() < data.impact_speed:
		return
	var rect := body_rect().grow(2.0)
	for box in CombatQuery.hurtboxes_in_rect(get_world_2d(), rect, CombatLayers.ENEMY_HURTBOX):
		var other := box.owner_entity() as Enemy
		if other == null or other == self or _impacted.has(other.get_instance_id()):
			continue
		_impacted[other.get_instance_id()] = true
		var hit := _environmental_hit(IMPACT_ATTACK, velocity * 0.6)
		box.receive(hit)
		if not is_dead():
			receive_hit(_environmental_hit(IMPACT_ATTACK, -velocity * 0.3))
		HitSpark.spawn(get_parent(), (global_position + other.global_position) * 0.5, Vector2.UP, Color("ffd36b"), 12)


func _check_wall_slam(pre_velocity: Vector2) -> void:
	if ai != AI.LAUNCHED or _wall_slammed or not is_on_wall():
		return
	if absf(pre_velocity.x) < data.impact_speed:
		return
	_wall_slammed = true
	velocity.x = -pre_velocity.x * 0.3
	receive_hit(_environmental_hit(IMPACT_ATTACK, Vector2(velocity.x, -80.0)))
	EventBus.camera_shake_requested.emit(0.15)


func _check_hazards() -> void:
	if is_dead() or (data.flying and not is_airborne_physics()):
		return
	if CombatQuery.rect_touches_areas(get_world_2d(), body_rect(), CombatLayers.HAZARD):
		receive_hit(_environmental_hit(HAZARD_ATTACK, Vector2(0, -200)))


func _environmental_hit(attack: AttackData, kb: Vector2) -> HitInfo:
	var credited: Node2D = last_hit.attacker if last_hit and is_instance_valid(last_hit.attacker) else null
	var hit := HitInfo.create(credited, attack, kb, kb.normalized() if kb != Vector2.ZERO else Vector2.UP,
		[&"environmental"] as Array[StringName])
	hit.source_position = global_position
	if credited is Player:
		hit.damage_mult = Game.circuit_mult(&"environmental_damage")
	return hit


func debug_label() -> String:
	return "%s %s hp %.0f poise %.0f" % [data.id, AI.keys()[ai], health, poise]
