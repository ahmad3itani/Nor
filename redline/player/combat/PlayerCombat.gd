class_name PlayerCombat
extends Node
## Rook's combat component: health, attack buffers, melee selection and hit
## delivery, ranged fire/ammo/recoil, damage intake, perfect dodge and hazards.
## Melee *movement* lives in MeleeState; this node decides what to swing and
## resolves what it hits. Tuning: PlayerCombatConfig + WeaponData resources.

signal attack_started(attack: AttackData)
signal hit_landed(hit: HitInfo, result: int, target: Node2D)
signal fired(weapon: WeaponData)

const HAZARD_ATTACK := preload("res://data/combat/hazard_attack.tres")

@export var config: PlayerCombatConfig
@export var melee_weapon: WeaponData
@export var ranged_weapons: Array[WeaponData] = []

var ranged_index: int = 0
var health: int = 0
var dead: bool = false
var hurt_invuln_timer: float = 0.0
var combo_index: int = 0
var combo_timer: float = 0.0
var light_buffer: float = 0.0
var heavy_buffer: float = 0.0
var ranged_buffer: float = 0.0
var fire_cooldown: float = 0.0
var since_last_shot: float = 0.0
var ammo: Dictionary = {}  # weapon id -> rounds
var air_hang_left: int = 0
var movement_tech_timer: float = 0.0
var current_attack: AttackData

@onready var player: Player = get_parent()


func _ready() -> void:
	reset()
	player.state_machine.state_changed.connect(_on_state_changed)


func reset() -> void:
	health = config.max_health
	dead = false
	hurt_invuln_timer = 0.0
	combo_index = 0
	combo_timer = 0.0
	light_buffer = 0.0
	heavy_buffer = 0.0
	ranged_buffer = 0.0
	fire_cooldown = 0.0
	current_attack = null
	for w in ranged_weapons:
		ammo[w.id] = w.ammo_max


func ranged_weapon() -> WeaponData:
	if ranged_weapons.is_empty():
		return null
	return ranged_weapons[ranged_index % ranged_weapons.size()]


func cycle_ranged() -> void:
	if ranged_weapons.is_empty():
		return
	ranged_index = (ranged_index + 1) % ranged_weapons.size()
	EventBus.ranged_weapon_changed.emit(ranged_weapon())


## Records presses. Also called during hitstop so inputs made in a freeze
## frame are never lost.
func buffer_input(input: PlayerInputFrame) -> void:
	if input.light_pressed:
		light_buffer = config.attack_buffer_time
	if input.heavy_pressed:
		heavy_buffer = config.attack_buffer_time
	if input.ranged_pressed:
		ranged_buffer = config.attack_buffer_time


func tick(input: PlayerInputFrame, delta: float) -> void:
	light_buffer = maxf(light_buffer - delta, 0.0)
	heavy_buffer = maxf(heavy_buffer - delta, 0.0)
	ranged_buffer = maxf(ranged_buffer - delta, 0.0)
	fire_cooldown = maxf(fire_cooldown - delta, 0.0)
	hurt_invuln_timer = maxf(hurt_invuln_timer - delta, 0.0)
	movement_tech_timer = maxf(movement_tech_timer - delta, 0.0)
	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo_index = 0
	buffer_input(input)
	if player.is_on_floor():
		air_hang_left = config.air_hang_uses
	_tick_reload(delta)
	_try_fire(input)
	_check_hazards()


# --- Melee --------------------------------------------------------------------

func wants_melee() -> bool:
	return not dead and melee_weapon != null and (light_buffer > 0.0 or heavy_buffer > 0.0)


## Picks the contextual attack for the buffered press and consumes it.
func consume_melee(on_floor: bool, up_held: bool) -> AttackData:
	var w := melee_weapon
	var heavy := heavy_buffer > 0.0
	light_buffer = 0.0
	heavy_buffer = 0.0
	combo_timer = 0.0
	var attack: AttackData
	if heavy:
		combo_index = 0
		if on_floor:
			attack = w.launcher if (up_held and w.launcher) else w.heavy
		else:
			attack = w.air_heavy
	elif on_floor:
		attack = w.light_chain[combo_index % w.light_chain.size()]
		combo_index = (combo_index + 1) % w.light_chain.size()
	else:
		attack = w.air_light
	if attack == null:
		attack = w.light_chain[0]
	current_attack = attack
	AudioManager.play_sfx(attack.swing_sfx)
	attack_started.emit(attack)
	return attack


## Air attacks may hold Rook aloft a limited number of times per airtime.
func take_air_hang() -> bool:
	if air_hang_left <= 0:
		return false
	air_hang_left -= 1
	return true


func on_attack_finished() -> void:
	current_attack = null
	combo_timer = config.combo_reset_time


## Delivers this tick's melee hits. hit_ids persists across the active window
## so each target is hit at most once per swing. Returns hits landed.
func melee_query(attack: AttackData, hit_ids: Dictionary) -> int:
	var rect := attack.world_hitbox(player.global_position, player.facing)
	var boxes := CombatQuery.hurtboxes_in_rect(player.get_world_2d(), rect, CombatLayers.ENEMY_HURTBOX)
	var landed := 0
	for box in boxes:
		var key := box.get_instance_id()
		if hit_ids.has(key):
			continue
		if attack.max_targets > 0 and hit_ids.size() >= attack.max_targets:
			break
		hit_ids[key] = true
		var hit := HitInfo.create(player, attack, attack.world_knockback(player.facing),
			Vector2(player.facing, 0), context_tags(attack, false))
		var result := box.receive(hit)
		if _on_hit_result(hit, result, box.owner_entity(), rect):
			landed += 1
	if landed > 0:
		player.hitstop(attack.hitstop)
		if attack.camera_trauma > 0.0:
			EventBus.camera_shake_requested.emit(attack.camera_trauma)
	return landed


func context_tags(attack: AttackData, ranged: bool) -> Array[StringName]:
	var tags: Array[StringName] = []
	if not player.is_on_floor():
		tags.append(&"aerial")
	if movement_tech_timer > 0.0:
		tags.append(&"after_movement")
	if ranged:
		tags.append(&"ranged")
	if melee_weapon and attack == melee_weapon.launcher:
		tags.append(&"launcher")
	return tags


func _on_hit_result(hit: HitInfo, result: int, target: Node2D, rect: Rect2) -> bool:
	if result == CombatResult.IGNORED:
		return false
	hit_landed.emit(hit, result, target)
	var at := target.global_position + Vector2(0, -12) if target else rect.get_center()
	if result == CombatResult.BLOCKED:
		AudioManager.play_sfx(&"block")
		HitSpark.spawn(player.get_parent(), at, Vector2(-player.facing, -0.3), Color("7fd7ff"), 6)
	else:
		AudioManager.play_sfx(hit.attack.hit_sfx)
		HitSpark.spawn(player.get_parent(), at, hit.direction, Color("ffffff"), 10)
	return true


# --- Ranged -------------------------------------------------------------------

func aim_direction(input: PlayerInputFrame) -> Vector2:
	var x := float(input.move_x)
	var y := 0.0
	if input.up_held:
		y = -1.0
	elif input.down_held and not player.is_on_floor():
		y = 1.0
	if x == 0.0 and y == 0.0:
		x = player.facing
	return Vector2(x, y).normalized()


func _can_shoot_now() -> bool:
	var state := player.state_machine.current
	if state.id == &"hurt":
		return false
	if state.id == &"melee" and current_attack and state.time_in_state < current_attack.cancel_time:
		return false
	return true


func _try_fire(input: PlayerInputFrame) -> void:
	var w := ranged_weapon()
	if dead or w == null or ranged_buffer <= 0.0 or fire_cooldown > 0.0 or not _can_shoot_now():
		return
	ranged_buffer = 0.0
	if int(ammo.get(w.id, 0)) <= 0:
		AudioManager.play_sfx(&"empty")
		fire_cooldown = w.fire_interval
		return
	var aim := aim_direction(input)
	if not is_zero_approx(aim.x):
		player.facing = int(signf(aim.x))
	ammo[w.id] = int(ammo[w.id]) - 1
	fire_cooldown = w.fire_interval
	since_last_shot = 0.0
	var muzzle := player.global_position + Vector2(w.muzzle_offset.x * player.facing, w.muzzle_offset.y)
	var pellets := w.shot.projectile.pellets
	var spread := w.shot.projectile.spread_deg
	var tags := context_tags(w.shot, true)
	for i in pellets:
		# Even fan instead of random spread: readable and deterministic.
		var offset := 0.0 if pellets == 1 else lerpf(-spread * 0.5, spread * 0.5, float(i) / (pellets - 1))
		var p := Projectile.spawn(player.get_parent(), player, w.shot, muzzle, aim.rotated(deg_to_rad(offset)),
			CombatLayers.ENEMY_HURTBOX, tags, player.global_position + Vector2(0, w.muzzle_offset.y))
		p.impacted.connect(_on_projectile_impact.bind(p))
	_apply_recoil(w, aim)
	AudioManager.play_sfx(w.fire_sfx)
	HitSpark.spawn(player.get_parent(), muzzle, aim, w.shot.projectile.color, 4, 90.0)
	if w.shot.camera_trauma > 0.0:
		EventBus.camera_shake_requested.emit(w.shot.camera_trauma)
	fired.emit(w)
	EventBus.ranged_fired.emit(w, int(ammo[w.id]))


func _apply_recoil(w: WeaponData, aim: Vector2) -> void:
	if player.is_on_floor():
		player.velocity.x -= aim.x * w.ground_recoil
		return
	var push := -aim * w.air_recoil
	player.velocity.x += push.x
	if push.y < 0.0:
		# Shooting downward arrests the fall first, then pushes up.
		player.velocity.y = minf(player.velocity.y, 0.0) + push.y
	else:
		player.velocity.y += push.y


func _on_projectile_impact(result: int, projectile: Projectile) -> void:
	if result == CombatResult.IGNORED:
		return
	AudioManager.play_sfx(&"block" if result == CombatResult.BLOCKED else projectile.attack.hit_sfx)


func _tick_reload(delta: float) -> void:
	since_last_shot += delta
	for w in ranged_weapons:
		var current := int(ammo.get(w.id, 0))
		if current < w.ammo_max and since_last_shot >= w.reload_time:
			ammo[w.id] = w.ammo_max
			if w == ranged_weapon():
				AudioManager.play_sfx(&"reload")
				EventBus.ranged_fired.emit(w, w.ammo_max)


# --- Damage intake ------------------------------------------------------------

func receive_hit(hit: HitInfo) -> int:
	if dead:
		return CombatResult.IGNORED
	if player.invulnerable:
		var state := player.state_machine.current
		if (state.id == &"dodge" or state.id == &"dash") and state.time_in_state <= config.perfect_dodge_window:
			player.hitstop(config.perfect_dodge_hitstop)
			AudioManager.play_sfx(&"perfect_dodge")
			EventBus.perfect_dodge.emit(hit.attacker)
			return CombatResult.PERFECT_EVADE
		return CombatResult.EVADED
	if hurt_invuln_timer > 0.0:
		return CombatResult.IGNORED
	var away := player.global_position.x - hit.source_position.x
	var side := signf(away) if not is_zero_approx(away) else signf(hit.direction.x)
	var kb := Vector2(side * config.hurt_knockback.x, config.hurt_knockback.y)
	return take_damage(int(ceil(hit.attack.damage)), kb, hit.attack.hitstop, true)


## knock=false for damage over time (reactor burnout): no stun, no knockback.
func take_damage(amount: int, knockback: Vector2, hitstop_time: float, knock: bool) -> int:
	if dead:
		return CombatResult.IGNORED
	health = maxi(health - amount, 0)
	EventBus.player_damaged.emit(amount, health)
	AudioManager.play_sfx(&"player_hurt")
	EventBus.camera_shake_requested.emit(0.3)
	if knock:
		hurt_invuln_timer = config.hurt_invuln_time
		player.hitstop(hitstop_time)
		player.velocity = knockback
		player.state_machine.force_state(&"hurt")
	if health <= 0:
		dead = true
		player.state_machine.force_state(&"hurt")
		EventBus.player_died.emit()
		return CombatResult.KILLED
	return CombatResult.HIT


func _check_hazards() -> void:
	if dead or hurt_invuln_timer > 0.0:
		return
	var size := player.config.low_size if player.is_low else player.config.standing_size
	var rect := Rect2(player.global_position - Vector2(size.x * 0.5, size.y), size)
	if CombatQuery.rect_touches_areas(player.get_world_2d(), rect, CombatLayers.HAZARD):
		# Hazards ignore dodge i-frames on purpose: spikes are about positioning.
		take_damage(config.hazard_damage, Vector2(-player.facing * 60.0, config.hazard_bounce.y),
			HAZARD_ATTACK.hitstop, true)


func _on_state_changed(_from: StringName, to: StringName) -> void:
	if to == &"slide" or to == &"dodge" or to == &"dash":
		movement_tech_timer = config.movement_tech_window
