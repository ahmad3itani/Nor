class_name Room
extends Node2D
## A handcrafted room: bounds (camera limits + kill plane), spawn markers,
## and the player/camera it hosts. Restarts are instant (bible §7, §38).
##
## Lab rooms (world_room = false) reset everything on death or R.
## World rooms (world_room = true) persist the player through Game.state:
## entry markers, carried momentum, pits that cost a pip and return you to
## safe ground, and death that sends you back to the last Anchor.

@export var room_name: String = "Room"
@export var bounds: Rect2 = Rect2(0, 0, 480, 270)
@export var player_scene: PackedScene = preload("res://player/Player.tscn")
@export var camera_config: CameraConfig = preload("res://data/camera/default_camera.tres")
## Falling this far below the bounds counts as death -> instant respawn.
@export var kill_margin: float = 48.0
@export var draw_grid: bool = true
@export var world_room: bool = false
@export var district_name: String = ""
## Palette/backdrop/weather. Null = graybox look (labs).
@export var theme: DistrictTheme

var player: Player
var camera: PlayerCamera
var spawns: Array[SpawnMarker] = []
var active_spawn_index: int = 0
## Optional pit handler (M7 chase/escape rooms): called with the player when a
## pit is fallen into. Returning true means it handled the fall (no pip, no
## last-safe teleport), so a set piece can own its own recovery. Contract:
## the pit check runs every physics frame, so an override that returns true
## must move the player back above the kill line that same call, or it is
## called again next frame until it does. Anything but true (including no
## return value) falls through to the normal pit.
var pit_override: Callable


func _ready() -> void:
	for node in find_children("*", "SpawnMarker", true, false):
		spawns.append(node as SpawnMarker)
	assert(not spawns.is_empty(), "Room needs at least one SpawnMarker")
	for i in spawns.size():
		if spawns[i].is_default:
			active_spawn_index = i
	var entry := SceneRouter.pending_entry
	var carry := SceneRouter.pending_carry
	if entry != &"":
		for i in spawns.size():
			if spawns[i].spawn_id == entry:
				active_spawn_index = i

	player = player_scene.instantiate()
	# Enter the physics space at the spawn, not at the room origin: a body that
	# appears inside an exit rect for even one step fires it (the Collector
	# Bay's west door sits on its origin), so respawn() below is too late.
	player.position = to_local(active_spawn().global_position)
	add_child(player)
	camera = PlayerCamera.new()
	camera.config = camera_config
	add_child(camera)
	camera.set_bounds(bounds)
	camera.make_current()
	if theme:
		var backdrop := DistrictBackdrop.new()
		backdrop.setup(theme, camera)
		add_child(backdrop)
	respawn()
	camera.follow(player)
	EventBus.player_died.connect(_on_player_died)
	if world_room:
		_enter_world(carry)
	EventBus.player_spawned.emit(player)


func _enter_world(carry: Dictionary) -> void:
	Game.apply_to_player(player)
	if carry.has("velocity"):
		player.velocity = carry["velocity"]
		player.facing = int(carry.get("facing", player.facing))
		if absf(player.velocity.x) > 1.0:
			player.state_machine.force_state(&"run")
	var path := SceneRouter.current_room_path
	if not Game.state.visited_rooms.has(path):
		Game.state.visited_rooms.append(path)
	Game.map_reveal(path, player.position + Vector2(0, -16))
	var drop := Game.state.dropped_scrap
	if drop.get("room", "") == path and int(drop.get("amount", 0)) > 0:
		var cache := ScrapCache.new()
		cache.position = Vector2(float(drop["x"]), float(drop["y"]))
		add_child(cache)
	EventBus.room_leaving.connect(_on_room_leaving)
	EventBus.loadout_changed.connect(_on_loadout_changed)
	EventBus.room_entered.emit(district_name, room_name)
	Game.note_room_entry(SceneRouter.current_room_path, active_spawn().spawn_id)


func _on_loadout_changed() -> void:
	if is_instance_valid(player):
		player.combat.set_loadout(Game.catalog.weapon(Game.state.melee_weapon), Game.catalog.weapon(Game.state.ranged_weapon))


func _on_room_leaving(room: Node) -> void:
	if room == self and is_instance_valid(player):
		Game.capture_from_player(player)


func _physics_process(_delta: float) -> void:
	if not world_room:
		if Input.is_action_just_pressed("reset"):
			respawn()
		elif player.global_position.y > bounds.end.y + kill_margin:
			respawn()
		return
	if player.combat.dead:
		return
	if player.global_position.y > bounds.end.y + kill_margin:
		_pit_fall()
	# Fog of discovery: a few times a second is plenty at run speed.
	if Engine.get_physics_frames() % 6 == 0:
		Game.map_reveal(SceneRouter.current_room_path, player.global_position - global_position + Vector2(0, -16))


## Pits hurt but never send you back to an Anchor (bible §2.8 fast recovery).
func _pit_fall() -> void:
	if pit_override.is_valid() and pit_override.call(player) == true:
		return
	player.combat.take_damage(1, Vector2.ZERO, 0.0, false, "pit")
	if player.combat.dead:
		return
	player.teleport(player.last_safe_position)
	camera.snap_to_target()


## Near-instant restart (bible §7): a short beat to read what killed you.
func _on_player_died() -> void:
	var delay := player.combat.config.respawn_delay
	if world_room:
		Game.on_player_death(SceneRouter.current_room_path, player.last_safe_position)
	await get_tree().create_timer(delay, false, true).timeout
	if not is_instance_valid(player) or not player.combat.dead:
		return
	if world_room:
		SceneRouter.transition_to(Game.respawn_room(), Game.respawn_entry())
	else:
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
