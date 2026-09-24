class_name PlayerStyle
extends Node
## Feeds the StyleMeter from combat events credited to this player and
## announces rank changes. Style never gates progress (bible §10).

@export var config: StyleConfig

var meter: StyleMeter
var _last_rank: int = 0

@onready var player: Player = get_parent()


func _ready() -> void:
	meter = StyleMeter.new(config)
	EventBus.enemy_damaged.connect(_on_enemy_damaged)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.perfect_dodge.connect(func(_a: Node2D) -> void: meter.add_bonus(config.perfect_dodge_points))
	EventBus.player_damaged.connect(func(_amount: int, _hp: int) -> void: meter.take_damage())
	EventBus.player_respawned.connect(func(p: Node2D, _id: StringName) -> void:
		if p == player:
			meter.reset())


func _physics_process(delta: float) -> void:
	if player.hitstop_timer > 0.0:
		return
	meter.tick(delta)
	var rank := meter.rank_index()
	if rank != _last_rank:
		if rank > _last_rank:
			AudioManager.play_sfx(&"rank_up")
		_last_rank = rank
		EventBus.style_changed.emit(meter.points, rank)


func _on_enemy_damaged(_enemy: Node2D, hit: HitInfo, result: int) -> void:
	if hit == null or hit.attacker != player:
		return
	if result == CombatResult.HIT:
		meter.add_hit(hit.attack.style_tag, hit.attack.style_points, hit.tags)
	elif result == CombatResult.BLOCKED:
		meter.add_bonus(config.blocked_points)


func _on_enemy_killed(enemy: Node2D, hit: HitInfo) -> void:
	if hit == null or hit.attacker != player or not enemy is Enemy:
		return
	var amount := (enemy as Enemy).data.style_value * config.kill_multiplier
	if hit.has_tag(&"environmental"):
		amount *= config.environmental_multiplier
	meter.add_bonus(amount)
