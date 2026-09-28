extends Node
## Turns movement events into audio + dust. Kept out of Player/states so the
## motor stays pure physics and feedback can be retuned or replaced freely.
## All tuning is exported on the node (edit in Player.tscn).
##
## Presentation overhaul T06: dust is drawn from the vfx/dust sheet (vfx/splash
## on water surfaces); the DustBurst particles stay as the placeholder whenever
## a sprite cannot spawn. It also creates Rook's JuiceDirector (kill motes,
## heal, perfect dodge, upgrades, Core aura). Sound calls are unchanged.

@export_group("Sound ids")
@export var sfx_jump: StringName = &"jump"
@export var sfx_slide_jump: StringName = &"jump_slide"
@export var sfx_land_soft: StringName = &"land_soft"
@export var sfx_land_hard: StringName = &"land_hard"
## A soft landing on water (a collider tagged surface=water or a water room).
@export var sfx_land_water: StringName = &"land_water"
@export var sfx_slide: StringName = &"slide"
@export var sfx_dodge: StringName = &"dodge"
@export var sfx_dash: StringName = &"dash"
@export var sfx_respawn: StringName = &"respawn"

@export_group("Dust")
## Landings slower than this make no dust/sound (e.g. stepping off a curb).
@export var min_land_speed: float = 120.0
@export var land_dust_max: int = 14
@export var jump_dust: int = 5
@export var slide_trail_interval: float = 0.05
@export var dash_dust: int = 8
## Sprite trails (slide) are 4-frame puffs: fewer of them than particles.
@export var sprite_trail_interval: float = 0.1
## Wall scrapes: at most one per this many seconds of wall contact.
@export var wall_scrape_interval: float = 0.25

var director: JuiceDirector

var _slide_trail_timer: float = 0.0
var _wall_timer: float = 0.0
var _was_on_wall: bool = false
var _steps: int = 0
var _room_surface: StringName = &""
var _room_surface_for: Node

@onready var player: Player = get_parent()


func _ready() -> void:
	player.jumped.connect(_on_jumped)
	player.landed.connect(_on_landed)
	player.state_machine.state_changed.connect(_on_state_changed)
	EventBus.player_respawned.connect(func(_p: Node2D, _id: StringName) -> void: AudioManager.play_sfx(sfx_respawn))
	director = JuiceDirector.new()
	director.player = player
	add_child(director)
	_connect_step_contact.call_deferred()


## Every sound id this node can request; used by tests to catch typos.
func sound_ids() -> Array[StringName]:
	return [sfx_jump, sfx_slide_jump, sfx_land_soft, sfx_land_hard, sfx_land_water, sfx_slide, sfx_dodge, sfx_dash, sfx_respawn]


func _world() -> Node:
	return player.get_parent()


## Run puffs ride the sprite's contact frames (the T04 visual's step_contact
## signal, whatever its arguments); without it Rook runs puff-free as before.
func _connect_step_contact() -> void:
	var v: Node = player.visual if is_instance_valid(player) else null
	if v == null or not v.has_signal(&"step_contact"):
		return
	for s in v.get_signal_list():
		if s["name"] == "step_contact":
			var cb := _on_step_contact.unbind((s["args"] as Array).size())
			if not v.is_connected(&"step_contact", cb):
				v.connect(&"step_contact", cb)
			return


## The floor under Rook is water: a collider tagged surface=water, else the
## room's RoomPresentation footstep surface.
func on_water() -> bool:
	for i in player.get_slide_collision_count():
		var c := player.get_slide_collision(i)
		var col := c.get_collider()
		if c.get_normal().y < -0.5 and col is Object and (col as Object).has_meta(&"surface"):
			return StringName((col as Object).get_meta(&"surface")) == &"water"
	var room := _world()
	if room != _room_surface_for:
		_room_surface_for = room
		var pres := PresentationIndex.for_room_node(room)
		_room_surface = pres.footstep_surface if pres else &""
	return _room_surface == &"water"


func _dust(row: StringName, at: Vector2, facing: int = 1) -> VfxOneShot:
	return DustBurst.puff(_world(), row, at, facing, on_water())


func _on_jumped(kind: StringName) -> void:
	AudioManager.play_sfx(sfx_slide_jump if kind == &"slide" else sfx_jump)
	if kind != &"coyote":
		if _dust(&"run_puff", player.global_position, player.facing) == null:
			DustBurst.spawn(_world(), player.global_position, jump_dust, Vector2.UP, 70.0, 40.0)


func _on_landed(impact_speed: float) -> void:
	if impact_speed < min_land_speed:
		return
	var hard := impact_speed >= player.config.hard_land_speed
	var t := clampf(impact_speed / player.config.fast_fall_speed, 0.0, 1.0)
	var land := sfx_land_hard if hard else (sfx_land_water if on_water() else sfx_land_soft)
	AudioManager.play_sfx(land, lerpf(0.5, 1.0, t))
	if _dust(&"land_hard" if hard else &"land", player.global_position) != null:
		return
	# Two low sideways puffs read as "impact" and stay visible past the body.
	var count := int(land_dust_max * t * 0.5) + 2
	for side in [-1, 1]:
		DustBurst.spawn(_world(), player.global_position + Vector2(side * 4, 0), count,
			Vector2(side, -0.35), 20.0, 40.0 + 70.0 * t)


func _on_state_changed(_from: StringName, to: StringName) -> void:
	var back := Vector2(-player.facing, -0.4)
	match to:
		&"slide":
			AudioManager.play_sfx(sfx_slide)
			if _dust(&"slide", player.global_position, player.facing) == null:
				DustBurst.spawn(_world(), player.global_position, 6, back, 25.0, 60.0)
		&"dodge":
			AudioManager.play_sfx(sfx_dodge)
		&"dash":
			AudioManager.play_sfx(sfx_dash)
			if player.is_on_floor():
				if _dust(&"dash_trail", player.global_position, player.facing) == null:
					DustBurst.spawn(_world(), player.global_position, dash_dust, back, 20.0, 90.0)


## A foot touches the floor on a run frame: a small puff behind it. Run puffs
## are decoration, so the ambient motion setting trims them (Reduced: every
## other step, Off: none); gameplay VFX never are.
func _on_step_contact() -> void:
	if player.current_state_id() != &"run" or not player.is_on_floor():
		return
	_steps += 1
	var lv := Motion.level()
	if lv == Motion.OFF or (lv == Motion.REDUCED and _steps % 2 == 1):
		return
	_dust(&"run_puff", player.global_position, player.facing)


func _physics_process(delta: float) -> void:
	_tick_wall_scrape(delta)
	if player.current_state_id() != &"slide":
		_slide_trail_timer = 0.0
		return
	_slide_trail_timer -= delta
	if _slide_trail_timer <= 0.0:
		var sprite := _dust(&"dash_trail", player.global_position, player.facing)
		_slide_trail_timer = sprite_trail_interval if sprite else slide_trail_interval
		if sprite == null:
			DustBurst.spawn(_world(), player.global_position, 2, Vector2(-player.facing, -0.6), 30.0, 35.0, 0.25)


## Airborne wall contact scrapes a little grit off the wall (sprite only:
## the placeholder never had one).
func _tick_wall_scrape(delta: float) -> void:
	_wall_timer = maxf(_wall_timer - delta, 0.0)
	var on_wall := player.is_on_wall() and not player.is_on_floor()
	if on_wall and (not _was_on_wall or _wall_timer <= 0.0) and absf(player.velocity.y) > 20.0:
		_wall_timer = wall_scrape_interval
		var side := -int(signf(player.get_wall_normal().x))
		if side != 0:
			var half := player.config.standing_size.x * 0.5
			DustBurst.puff(_world(), &"wall_scrape", player.global_position + Vector2(side * half, -12.0), side)
	_was_on_wall = on_wall
