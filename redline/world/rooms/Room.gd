class_name Room
extends Node2D
## A handcrafted room: bounds (camera limits + kill plane), spawn markers,
## and the player/camera it hosts. Restarts are instant (bible §7, §38).

@export var room_name: String = "Room"
@export var bounds: Rect2 = Rect2(0, 0, 480, 270)
@export var player_scene: PackedScene = preload("res://player/Player.tscn")
@export var camera_config: CameraConfig = preload("res://data/camera/default_camera.tres")
## Falling this far below the bounds counts as death -> instant respawn.
@export var kill_margin: float = 48.0
@export var draw_grid: bool = true

var player: Player
var camera: PlayerCamera
var spawns: Array[SpawnMarker] = []
var active_spawn_index: int = 0


func _ready() -> void:
	for node in find_children("*", "SpawnMarker", true, false):
		spawns.append(node as SpawnMarker)
	assert(not spawns.is_empty(), "Room needs at least one SpawnMarker")
	for i in spawns.size():
		if spawns[i].is_default:
			active_spawn_index = i

	player = player_scene.instantiate()
	add_child(player)
	camera = PlayerCamera.new()
	camera.config = camera_config
	add_child(camera)
	camera.set_bounds(bounds)
	camera.make_current()
	respawn()
	camera.follow(player)
	EventBus.player_died.connect(_on_player_died)
	EventBus.player_spawned.emit(player)


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("reset"):
		respawn()
	elif player.global_position.y > bounds.end.y + kill_margin:
		respawn()


## Near-instant restart (bible §7): a short beat to read what killed you.
func _on_player_died() -> void:
	var delay := player.combat.config.respawn_delay
	await get_tree().create_timer(delay, false, true).timeout
	if is_instance_valid(player) and player.combat.dead:
		respawn()


func active_spawn() -> SpawnMarker:
	return spawns[active_spawn_index]


func respawn() -> void:
	var marker := active_spawn()
	player.respawn(marker.global_position, marker.facing)
	if camera.target:
		camera.snap_to_target()
	EventBus.player_respawned.emit(player, marker.spawn_id)


func cycle_spawn(step: int = 1) -> void:
	active_spawn_index = wrapi(active_spawn_index + step, 0, spawns.size())
	respawn()


func _draw() -> void:
	if not draw_grid:
		return
	# Faint 16px grid with 64px majors: makes speed and jump height legible.
	var minor := Color(1, 1, 1, 0.035)
	var major := Color(1, 1, 1, 0.08)
	var x := bounds.position.x
	while x <= bounds.end.x:
		draw_line(Vector2(x, bounds.position.y), Vector2(x, bounds.end.y), major if int(x) % 64 == 0 else minor)
		x += 16.0
	var y := bounds.position.y
	while y <= bounds.end.y:
		draw_line(Vector2(bounds.position.x, y), Vector2(bounds.end.x, y), major if int(y) % 64 == 0 else minor)
		y += 16.0
	draw_rect(bounds, Color(0.9, 0.16, 0.24, 0.5), false, 1.0)
