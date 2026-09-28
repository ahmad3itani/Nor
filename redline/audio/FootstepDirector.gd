class_name FootstepDirector
extends Node
## Footsteps per surface (SOUND_DIRECTION section 6), a child of AudioManager
## so feedback stays out of the motor. While the player runs on the floor it
## accumulates |dx| and plays footstep_<surface> every STRIDE pixels. When the
## player's visual offers a `step_contact` signal (the run cycle's contact
## frames), that drives the steps instead and the distance path stops.
##
## Surface, first hit wins: the floor collider's "surface" metadata, then the
## room's RoomPresentation.footstep_surface (PresentationIndex), then concrete.
## Reads only; never touches collision, layers or the player's state.

const STRIDE := 26.0
const DEFAULT_SURFACE := &"concrete"
const RUN_STATE := &"run"

## Steps played since start (tests read it).
var steps: int = 0
## The last surface a step used.
var last_surface: StringName = &""

var _player: CharacterBody2D = null
var _visual_steps: bool = false
var _distance: float = 0.0
var _last_x: float = 0.0
var _room_surface: StringName = &""


func _ready() -> void:
	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.room_loaded.connect(func(r: Node) -> void: _room_surface = room_surface(r))


func _on_player_spawned(player: Node2D) -> void:
	_player = player as CharacterBody2D
	_distance = 0.0
	_visual_steps = false
	if _player == null:
		return
	_last_x = _player.global_position.x
	_room_surface = room_surface(_current_room())
	var visual := _player.get_node_or_null("Visual")
	if visual != null and visual.has_signal(&"step_contact"):
		visual.connect(&"step_contact", _on_step_contact)
		_visual_steps = true


## SceneRouter by node lookup: AudioManager (and so this script) compiles
## before the later autoloads, so it must not name them (CLAUDE.md pitfall).
func _current_room() -> Node:
	return AmbienceDirector.router_room(self)


## The room's default surface (PresentationIndex), or &"" when it has none.
static func room_surface(room: Node) -> StringName:
	if room == null or not is_instance_valid(room):
		return &""
	var pres := PresentationIndex.for_room_node(room)
	return pres.footstep_surface if pres != null else &""


## First hit wins: collider metadata, room default, concrete.
static func resolve_surface(collider_surface: StringName, room_default: StringName) -> StringName:
	if collider_surface != &"":
		return collider_surface
	if room_default != &"":
		return room_default
	return DEFAULT_SURFACE


static func sfx_id(surface: StringName) -> StringName:
	return StringName("footstep_%s" % surface)


## The "surface" metadata of the floor the body stands on, or &"".
static func floor_surface(body: CharacterBody2D) -> StringName:
	for i in body.get_slide_collision_count():
		var c := body.get_slide_collision(i)
		if c == null or c.get_normal().y > -0.5:
			continue
		var col := c.get_collider()
		if col != null and is_instance_valid(col) and col.has_meta(&"surface"):
			return StringName(str(col.get_meta(&"surface")))
	return &""


func _running(p: CharacterBody2D) -> bool:
	return p.is_on_floor() and p.has_method(&"current_state_id") and p.call(&"current_state_id") == RUN_STATE


func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = null
		return
	var x := _player.global_position.x
	var dx := absf(x - _last_x)
	_last_x = x
	if _visual_steps or not _running(_player):
		_distance = 0.0
		return
	# A teleport (respawn, door carry) is not a stride.
	if dx > STRIDE * 2.0:
		return
	_distance += dx
	if _distance >= STRIDE:
		_distance -= STRIDE
		play_step()


## The visual passes the planted foot (0/1); the step sound ignores it.
func _on_step_contact(_foot: int = 0) -> void:
	if _player != null and is_instance_valid(_player) and _running(_player):
		play_step()


func play_step() -> void:
	last_surface = resolve_surface(floor_surface(_player) if _player != null and is_instance_valid(_player) else &"", _room_surface)
	var id := sfx_id(last_surface)
	var audio := get_parent()
	steps += 1
	if audio == null or not audio.has_method(&"play_sfx"):
		return
	if not audio.call(&"has_sfx", id):
		id = sfx_id(DEFAULT_SURFACE)
	audio.call(&"play_sfx", id)
