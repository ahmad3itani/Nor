@tool
class_name EnemySpawner
extends Marker2D
## Places one enemy and can bring it back (lab reset, optional auto-respawn).
## Real encounters will get an Encounter/Wave resource in M5+; this is the
## minimal authored spawn point.

@export var enemy_scene: PackedScene
@export var ai_enabled: bool = true
@export_enum("Right:1", "Left:-1") var facing: int = -1
## Seconds after the enemy dies before it respawns. 0 = never.
@export var auto_respawn_delay: float = 0.0

var current: Enemy
var _dead_time: float = 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group(&"enemy_spawners")
	spawn.call_deferred()


func spawn() -> Enemy:
	if current and is_instance_valid(current):
		current.queue_free()
	current = enemy_scene.instantiate()
	current.ai_enabled = ai_enabled
	current.facing = facing
	current.position = position
	get_parent().add_child(current)
	_dead_time = 0.0
	return current


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or auto_respawn_delay <= 0.0:
		return
	if current == null or not is_instance_valid(current) or current.is_dead():
		_dead_time += delta
		if _dead_time >= auto_respawn_delay:
			spawn()


func _draw() -> void:
	if Engine.is_editor_hint():
		draw_rect(Rect2(-7, -28, 14, 28), Color(1.0, 0.3, 0.3, 0.35))
