class_name ReactorCore
extends Node
## Rook's Redline Core (bible §6): "Movement is life. Violence buys time."
## Drains only while inside Flow Zones; refills from hits, kills (more at
## higher style ranks), environmental kills, perfect dodges and hits right
## after movement tech. Empty = burnout: health drains until refilled.
## Mode (Normal / Assist / Challenge) follows Settings.reactor_mode.

@export var configs: Array[ReactorConfig] = []

var config: ReactorConfig
var charge: float = 0.0
## FlowZones Rook is inside (FlowZone -> true); each brings its own drain
## scale and floor. Anonymous entries (enter_flow() with no zone: tests, code
## paths without a node) count as a plain zone: scale 1.0, no floor.
var _zones: Dictionary = {}
var _anon_zones: int = 0
var _burnout_timer: float = 0.0
var _heartbeat_timer: float = 0.0
var _was_critical: bool = false

@onready var player: Player = get_parent()


func _ready() -> void:
	apply_mode(Settings.reactor_mode)
	charge = config.start_charge
	EventBus.enemy_damaged.connect(_on_enemy_damaged)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.perfect_dodge.connect(_on_perfect_dodge)
	EventBus.player_respawned.connect(_on_respawned)


func apply_mode(index: int) -> void:
	config = configs[clampi(index, 0, configs.size() - 1)]
	charge = minf(charge, config.max_charge)
	_emit()


func in_flow() -> bool:
	return _anon_zones > 0 or not _zones.is_empty()


func enter_flow(zone: FlowZone = null) -> void:
	if zone == null:
		_anon_zones += 1
	else:
		_zones[zone] = true
	_emit()


func exit_flow(zone: FlowZone = null) -> void:
	if zone == null:
		_anon_zones = maxi(_anon_zones - 1, 0)
	else:
		_zones.erase(zone)
	_emit()


## Overlapping zones never stack: the harshest scale wins (M7).
func drain_scale() -> float:
	var s := 1.0 if _anon_zones > 0 else 0.0
	for z: Variant in _zones:
		if is_instance_valid(z):
			s = maxf(s, (z as FlowZone).drain_scale)
	return s


## The highest floor of the zones Rook is inside (0 = drains to empty).
func drain_floor() -> float:
	var f := 0.0
	for z: Variant in _zones:
		if is_instance_valid(z):
			f = maxf(f, (z as FlowZone).drain_floor)
	return f


## A zone freed with Rook inside (room change) never sends body_exited;
## drop it before it is read (calling into a freed node crashes 4.3).
func _prune_zones() -> void:
	for z: Variant in _zones.keys():
		if not is_instance_valid(z):
			_zones.erase(z)


func is_critical() -> bool:
	return charge <= config.critical_threshold


func gain(amount: float) -> void:
	if amount <= 0.0:
		return
	var mult := config.gain_multiplier
	if player.combat.health >= player.combat.config.max_health:
		mult *= 1.0 + Game.circuit_value(&"full_health_reactor_bonus")
	charge = minf(charge + amount * mult, config.max_charge)
	_emit()


func _physics_process(delta: float) -> void:
	_prune_zones()
	if player.combat.dead or player.hitstop_timer > 0.0:
		return
	if not in_flow():
		_burnout_timer = 0.0
		return
	# A floored zone stops the drain at its floor; gains still lift the Core
	# above it. Since charge never reaches 0 there, burnout never starts.
	var floor_charge := drain_floor()
	if charge > floor_charge:
		var drain := config.drain_per_second * _drain_factor() * drain_scale() * delta
		charge = maxf(charge - drain, floor_charge)
	if charge <= 0.0:
		_burnout_timer += delta
		if _burnout_timer >= config.burnout_interval:
			_burnout_timer = 0.0
			AudioManager.play_sfx(&"burnout")
			player.combat.take_damage(1, Vector2.ZERO, 0.0, false, "burnout")
	else:
		_burnout_timer = 0.0
	if is_critical():
		_heartbeat_timer -= delta
		if _heartbeat_timer <= 0.0:
			# Faster heartbeat as the core empties (readable audio, bible §28).
			_heartbeat_timer = lerpf(0.45, 0.9, charge / maxf(config.critical_threshold, 1.0))
			AudioManager.play_sfx(&"heartbeat")
	_emit()


## Runner's Debt: speed slows the drain, standing still speeds it up.
func _drain_factor() -> float:
	var debt := Game.circuit_value(&"runners_debt")
	if debt <= 0.0:
		return 1.0
	var speed := absf(player.velocity.x)
	if speed > player.config.max_run_speed + 1.0:
		return 1.0 - debt
	if speed < 10.0:
		return 1.0 + debt
	return 1.0


func _emit() -> void:
	if config == null:
		return
	var critical := is_critical() and in_flow()
	EventBus.reactor_changed.emit(charge, config.max_charge, critical)
	_was_critical = critical


func _credited(hit: HitInfo) -> bool:
	return hit != null and hit.attacker == player


func _on_enemy_damaged(_enemy: Node2D, hit: HitInfo, result: int) -> void:
	if result != CombatResult.HIT or not _credited(hit):
		return
	var amount := hit.attack.reactor_gain * config.hit_gain_scale
	if hit.has_tag(&"after_movement"):
		amount += config.movement_hit_bonus
	gain(amount)


func _on_enemy_killed(enemy: Node2D, hit: HitInfo) -> void:
	if not _credited(hit) or not enemy is Enemy:
		return
	var rank := player.style.meter.rank_index() if player.style else 0
	var amount := (enemy as Enemy).data.reactor_reward * (1.0 + config.style_rank_kill_bonus * rank)
	if hit.has_tag(&"environmental"):
		amount += config.environmental_kill_bonus
	gain(amount)


func _on_perfect_dodge(_attacker: Node2D) -> void:
	gain(config.perfect_dodge_gain)


func _on_respawned(p: Node2D, _spawn: StringName) -> void:
	if p != player:
		return
	charge = config.start_charge
	_burnout_timer = 0.0
	_emit()
