class_name BossArena
extends Area2D
## Boss encounter controller (bible §17 rules): the Anchor sits just outside
## (short runback), gates close on entry, the intro plays once and is skipped
## on later attempts, defeat sets a flag, opens the gates and spawns the reward.
## The reward can never be missed: a room re-entered after the win spawns it
## again, and the pickup frees itself once it has been taken (a Collectible
## by persist_id, an AbilityPickup by its flag).
## Origin: top-left of the trigger area.

@export var size: Vector2 = Vector2(400, 200)
@export var boss_id: String = "warden_krail"
@export var boss_title: String = "WARDEN KRAIL"
@export var boss_subtitle: String = "Lowlight Enforcement"
@export var boss_path: NodePath
@export var gate_paths: Array[NodePath] = []
@export var reward_scene: PackedScene
## Where the reward lands, in the arena parent's space (room space in
## generated rooms): on the floor, never mid-air. INF = where the boss died.
@export var reward_position: Vector2 = Vector2.INF
## Seconds of intro banner before the boss acts (first attempt only).
@export var intro_time: float = 2.2
@export var retry_intro_time: float = 0.6

var boss: Enemy
var started: bool = false
var _reward: Node2D


func _ready() -> void:
	collision_layer = 0
	collision_mask = CombatLayers.PLAYER_BODY
	monitoring = true
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = size * 0.5
	add_child(shape)
	boss = get_node_or_null(boss_path) as Enemy
	if Game.has_flag(defeated_flag()):
		if boss:
			boss.queue_free()
		_set_gates(false)
		# Left before picking the reward up: it waits here on the next visit.
		_spawn_reward.call_deferred(Vector2.INF)
		return
	if boss:
		boss.ai_enabled = false
		if not boss.died.is_connected(_on_boss_died):
			boss.died.connect(_on_boss_died)
	_set_gates(false)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func defeated_flag() -> String:
	return "%s_defeated" % boss_id


func _on_body_entered(body: Node2D) -> void:
	if started or not body is Player or boss == null:
		return
	started = true
	_set_gates(true)
	var seen := Game.has_flag("%s_intro_seen" % boss_id)
	Game.set_flag("%s_intro_seen" % boss_id)
	EventBus.boss_started.emit(boss, boss_title)
	EventBus.room_entered.emit(boss_title, boss_subtitle if not seen else "")
	AudioManager.play_sfx(&"boss_roar")
	await get_tree().create_timer(retry_intro_time if seen else intro_time, false, true).timeout
	if is_instance_valid(boss) and not boss.is_dead():
		boss.ai_enabled = true
		boss.set_ai(Enemy.AI.ENGAGE)


func _on_boss_died(e: Enemy) -> void:
	# The boss is freed at death_time, before the delay below ends: read
	# everything needed from it now.
	var died_at := e.global_position
	var delay := e.data.death_time + 0.2
	Game.set_flag(defeated_flag())
	EventBus.boss_defeated.emit(boss_id)
	await get_tree().create_timer(delay, false, true).timeout
	_set_gates(false)
	_spawn_reward(died_at)


## `fallback` (global) is used when reward_position is INF; with no fallback
## either, the arena centre.
func _spawn_reward(fallback: Vector2) -> void:
	if reward_scene == null or not is_inside_tree() or is_instance_valid(_reward):
		return
	var parent := get_parent()
	var reward := reward_scene.instantiate() as Node2D
	if reward_position != Vector2.INF:
		reward.position = reward_position
	else:
		var at := fallback if fallback != Vector2.INF else global_position + size * 0.5
		reward.position = (parent as Node2D).to_local(at) if parent is Node2D else at
	_reward = reward
	parent.add_child(reward)


func _set_gates(closed: bool) -> void:
	for p in gate_paths:
		var g := get_node_or_null(p)
		if g and g.has_method("set_closed"):
			g.set_closed(closed)
