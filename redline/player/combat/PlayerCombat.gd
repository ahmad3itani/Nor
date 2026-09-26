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
## What last hurt Rook ("needle/needle_stab", "hazard", "pit", "burnout").
var last_damage_source: String = ""
var hurt_invuln_timer: float = 0.0
var combo_index: int = 0
var combo_timer: float = 0.0
var light_buffer: float = 0.0
var heavy_buffer: float = 0.0
var ranged_buffer: float = 0.0
var heal_buffer: float = 0.0
var injectors: int = 0
var fire_cooldown: float = 0.0
var since_last_shot: float = 0.0
var ammo: Dictionary = {}  # weapon id -> rounds
var air_hang_left: int = 0
var movement_tech_timer: float = 0.0
var current_attack: AttackData
## Horizontal speed when the current swing started (Momentum Coil).
var attack_start_speed: float = 0.0
var _kills_since_heal: int = 0
## M9 damage assist carry (T11 writes, CombatHud draws): the fraction of a
## pip taken but not yet removed.
var damage_carry: float = 0.0

@onready var player: Player = get_parent()


func _ready() -> void:
	reset()
	player.state_machine.state_changed.connect(_on_state_changed)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	# The damage-assist buffer starts over after a respawn or a rest, so a
	# half pip never follows Rook into the next attempt (D4 §8.2).
	EventBus.player_respawned.connect(_on_player_respawned)
	EventBus.anchor_rested.connect(_on_anchor_rested)


func reset() -> void:
	health = config.max_health
	dead = false
	hurt_invuln_timer = 0.0
	combo_index = 0
	combo_timer = 0.0
	light_buffer = 0.0
	heavy_buffer = 0.0
	ranged_buffer = 0.0
	heal_buffer = 0.0
	injectors = injector_capacity()
	fire_cooldown = 0.0
	current_attack = null
	_refill_ammo()


## Full rest at an Anchor: health and injectors (core is refilled by the Anchor).
func rest() -> void:
	health = config.max_health
	injectors = injector_capacity()
	dead = false
	_refill_ammo()


func injector_capacity() -> int:
	return config.injector_max + Game.injector_bonus()


## null clears a slot: the campaign starts Rook unarmed (bible §42), and every
## melee entry point already gates on wants_melee(), every shot on
## ranged_weapon(), so an empty slot simply does nothing.
func set_loadout(melee: WeaponData, ranged: WeaponData) -> void:
	melee_weapon = melee
	# A fresh array: the exported one may be the scene's shared default.
	var slots: Array[WeaponData] = []
	if ranged:
		slots.append(ranged)
	ranged_weapons = slots
	ranged_index = 0
	_refill_ammo()


func _refill_ammo() -> void:
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
	if input.heal_pressed:
		heal_buffer = config.attack_buffer_time


func tick(input: PlayerInputFrame, delta: float) -> void:
	light_buffer = maxf(light_buffer - delta, 0.0)
	heavy_buffer = maxf(heavy_buffer - delta, 0.0)
	ranged_buffer = maxf(ranged_buffer - delta, 0.0)
	heal_buffer = maxf(heal_buffer - delta, 0.0)
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


# --- Healing --------------------------------------------------------------------

func wants_heal() -> bool:
	return heal_buffer > 0.0 and not dead and injectors > 0 and health < config.max_health


func finish_heal() -> void:
	heal_buffer = 0.0
	injectors -= 1
	health = mini(health + config.heal_amount, config.max_health)
	AudioManager.play_sfx(&"heal")
	HitSpark.spawn(player.get_parent(), player.global_position + Vector2(0, -18), Vector2.UP, Color("7dff9a"), 12, 70.0)
	EventBus.player_healed.emit(health)


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
	attack_start_speed = absf(player.velocity.x)
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
		hit.damage_mult = melee_damage_mult()
		hit.bonus_vs_staggered = Game.circuit_value(&"predator_damage")
		var result := box.receive(hit)
		if _on_hit_result(hit, result, box.owner_entity(), rect):
			landed += 1
	if landed > 0:
		player.hitstop(attack.hitstop)
		if attack.camera_trauma > 0.0:
			EventBus.camera_shake_requested.emit(attack.camera_trauma)
	return landed


## Circuit damage scaling for melee, including Momentum Coil's speed bonus.
func melee_damage_mult() -> float:
	var mult := Game.circuit_mult(&"melee_damage")
	var momentum := Game.circuit_value(&"momentum_damage")
	if momentum > 0.0:
		var run := player.config.max_run_speed
		var t := clampf((attack_start_speed - run) / maxf(player.config.dash_speed - run, 1.0), 0.0, 1.0)
		mult *= 1.0 + momentum * t
	return mult


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
	# Aim assist bends the shot after facing is set, so it never turns Rook
	# around; ground waves follow the floor and ignore aim anyway (D4 §8.1).
	if not w.shot.projectile.ground_wave:
		aim = assisted_aim(aim, muzzle)
	var pellets := w.shot.projectile.pellets
	var spread := w.shot.projectile.spread_deg
	var tags := context_tags(w.shot, true)
	for i in pellets:
		# Even fan instead of random spread: readable and deterministic.
		var offset := 0.0 if pellets == 1 else lerpf(-spread * 0.5, spread * 0.5, float(i) / (pellets - 1))
		var p := Projectile.spawn(player.get_parent(), player, w.shot, muzzle, aim.rotated(deg_to_rad(offset)),
			CombatLayers.ENEMY_HURTBOX, tags, player.global_position + Vector2(0, w.muzzle_offset.y))
		p.damage_mult = Game.circuit_mult(&"ranged_damage")
		p.bonus_vs_staggered = Game.circuit_value(&"predator_damage")
		p._life *= Game.circuit_mult(&"ranged_range")
		p.impacted.connect(_on_projectile_impact.bind(p))
	_apply_recoil(w, aim)
	AudioManager.play_sfx(w.fire_sfx)
	HitSpark.spawn(player.get_parent(), muzzle, aim, w.shot.projectile.color, 4, 90.0)
	if w.shot.camera_trauma > 0.0:
		EventBus.camera_shake_requested.emit(w.shot.camera_trauma)
	fired.emit(w)
	EventBus.ranged_fired.emit(w, int(ammo[w.id]))


## The aim after Settings.aim_assist (unchanged when Off).
func assisted_aim(aim: Vector2, muzzle: Vector2) -> Vector2:
	var cfg := Settings.config()
	var cr := AimAssist.cone_and_range(Settings.aim_assist, cfg)
	if cr.x <= 0.0 or cr.y <= 0.0:
		return aim
	return AimAssist.adjust(aim, muzzle, AimAssist.candidates_for(player, muzzle, cr.y, cfg.aim_require_on_screen), cr.x, cr.y)


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
	# A locking scene owns Rook: no damage and no perfect dodge under it (M8).
	if player.cinematic_lock:
		return CombatResult.IGNORED
	if player.invulnerable:
		var state := player.state_machine.current
		var window := config.perfect_dodge_window + Game.circuit_value(&"perfect_window_bonus")
		if (state.id == &"dodge" or state.id == &"dash") and state.time_in_state <= window:
			player.hitstop(config.perfect_dodge_hitstop)
			AudioManager.play_sfx(&"perfect_dodge")
			if Game.circuit_value(&"perfect_dodge_reload") > 0.0:
				_refill_ammo()
			EventBus.perfect_dodge.emit(hit.attacker)
			return CombatResult.PERFECT_EVADE
		return CombatResult.EVADED
	if hurt_invuln_timer > 0.0:
		return CombatResult.IGNORED
	var away := player.global_position.x - hit.source_position.x
	var side := signf(away) if not is_zero_approx(away) else signf(hit.direction.x)
	var kb := Vector2(side * config.hurt_knockback.x, config.hurt_knockback.y)
	return take_damage(int(ceil(hit.attack.damage)), kb, hit.attack.hitstop, true, _source_of(hit), false, _is_boss_hit(hit))


## A hit from a boss itself (EnemyData.boss): the damage assist's
## "Bosses: reduced" scope. The attacker may be freed already.
static func _is_boss_hit(hit: HitInfo) -> bool:
	return is_instance_valid(hit.attacker) and hit.attacker is Enemy and (hit.attacker as Enemy).data != null \
		and (hit.attacker as Enemy).data.boss


## "enemy_id/attack_id" for playtest death causes (M4). The attacker may be
## freed already (a projectile outliving its shooter), so never touch it blind.
static func _source_of(hit: HitInfo) -> String:
	var who := "unknown"
	if is_instance_valid(hit.attacker) and hit.attacker is Enemy and (hit.attacker as Enemy).data:
		who = String((hit.attacker as Enemy).data.id)
	return "%s/%s" % [who, String(hit.attack.id) if hit.attack else "?"]


## knock=false for damage over time (reactor burnout): no stun, no knockback.
## `source` names what hurt Rook (enemy/attack, hazard, pit, burnout) so
## playtest telemetry can report death causes. `from_boss` marks a boss's own
## hit (receive_hit fills it) for the bosses-only damage assist.
func take_damage(amount: int, knockback: Vector2, hitstop_time: float, knock: bool, source: String = "unknown", nonlethal: bool = false, from_boss: bool = false) -> int:
	if dead:
		return CombatResult.IGNORED
	# A locking scene owns Rook (M8): direct damage (pits, chase catches,
	# spikes, burnout) is ignored too, not only hits; a pit still returns him
	# to his last safe spot.
	if player.cinematic_lock:
		return CombatResult.IGNORED
	last_damage_source = source
	amount = ceili(amount * Game.circuit_mult(&"damage_taken"))
	# Damage assist (D4 §8.2): before the nonlethal clamp and Emergency Loop,
	# so neither can be bypassed; a hit that rounds to 0 still counts as a hit.
	var factor := DamageAssist.factor_for(Settings.damage_assist, Settings.config(), source, from_boss)
	if factor < 1.0:
		var scaled := DamageAssist.scale(amount, damage_carry, factor)
		amount = int(scaled[0])
		damage_carry = float(scaled[1])
	# Teaching set pieces (M7) may hurt but never kill: clamp after the
	# circuit multiplier so a damage-taken penalty can't sneak a death in.
	if nonlethal:
		amount = maxi(0, mini(amount, health - 1))
	if amount >= health and Game.circuit_value(&"emergency_loop") > 0.0 and not Game.has_flag("emergency_loop_spent"):
		# Emergency Loop: survive once per rest at 1 pip.
		amount = health - 1
		Game.set_flag("emergency_loop_spent")
		AudioManager.play_sfx(&"perfect_dodge")
		EventBus.hint_requested.emit("EMERGENCY LOOP", 1.5)
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


## A push with no damage (M7: a set piece shoves Rook back). Reuses the hurt
## state for its short loss of control, but grants no invulnerability and
## emits no player_damaged, so it never reads as a hit.
func shove(v: Vector2) -> void:
	if dead:
		return
	player.velocity = v
	player.state_machine.force_state(&"hurt")


func _check_hazards() -> void:
	if dead or hurt_invuln_timer > 0.0:
		return
	var size := player.config.low_size if player.is_low else player.config.standing_size
	var rect := Rect2(player.global_position - Vector2(size.x * 0.5, size.y), size)
	if CombatQuery.rect_touches_areas(player.get_world_2d(), rect, CombatLayers.HAZARD):
		# Hazards ignore dodge i-frames on purpose: spikes are about positioning.
		take_damage(config.hazard_damage, Vector2(-player.facing * 60.0, config.hazard_bounce.y),
			HAZARD_ATTACK.hitstop, true, "hazard")


func _on_enemy_killed(_enemy: Node2D, hit: HitInfo) -> void:
	var per_heal := int(Game.circuit_value(&"kills_per_heal"))
	if per_heal <= 0 or hit == null or hit.attacker != player or dead:
		return
	_kills_since_heal += 1
	if _kills_since_heal >= per_heal:
		_kills_since_heal = 0
		if health < config.max_health:
			health += 1
			AudioManager.play_sfx(&"heal")
			EventBus.player_healed.emit(health)


func _on_player_respawned(p: Node2D, _spawn: StringName) -> void:
	if p == player:
		damage_carry = 0.0


func _on_anchor_rested(_anchor: Node) -> void:
	damage_carry = 0.0


func _on_state_changed(_from: StringName, to: StringName) -> void:
	if to == &"slide" or to == &"dodge" or to == &"dash":
		movement_tech_timer = config.movement_tech_window
