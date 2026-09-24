class_name BossArena
extends Area2D
## Boss encounter controller (bible §17 rules): the Anchor sits just outside
## (short runback), gates close on entry, the intro plays once and is skipped
## on later attempts, defeat sets a flag, opens the gates and spawns the reward.
## Origin: top-left of the trigger area.

@export var size: Vector2 = Vector2(400, 200)
@export var boss_id: String = "warden_krail"
@export var boss_title: String = "WARDEN KRAIL"
@export var boss_subtitle: String = "Lowlight Enforcement"
@export var boss_path: NodePath
@export var gate_paths: Array[NodePath] = []
@export var reward_scene: PackedScene
## Seconds of intro banner before the boss acts (first attempt only).
@export var intro_time: float = 2.2
@export var retry_intro_time: float = 0.6

var boss: Enemy
var started: bool = false


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


func _on_boss_died(_e: Enemy) -> void:
	Game.set_flag(defeated_flag())
	EventBus.boss_defeated.emit(boss_id)
	await get_tree().create_timer(boss.data.death_time + 0.2, false, true).timeout
	_set_gates(false)
	if reward_scene:
		var reward := reward_scene.instantiate() as Node2D
		reward.position = boss.global_position if is_instance_valid(boss) else global_position + size * 0.5
		get_parent().add_child(reward)


func _set_gates(closed: bool) -> void:
	for p in gate_paths:
		var g := get_node_or_null(p)
		if g and g.has_method("set_closed"):
			g.set_closed(closed)
