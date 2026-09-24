extends Node
## Turns movement events into audio + dust. Kept out of Player/states so the
## motor stays pure physics and feedback can be retuned or replaced freely.
## All tuning is exported on the node (edit in Player.tscn).

@export_group("Sound ids")
@export var sfx_jump: StringName = &"jump"
@export var sfx_slide_jump: StringName = &"jump_slide"
@export var sfx_land_soft: StringName = &"land_soft"
@export var sfx_land_hard: StringName = &"land_hard"
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

var _slide_trail_timer: float = 0.0

@onready var player: Player = get_parent()


func _ready() -> void:
	player.jumped.connect(_on_jumped)
	player.landed.connect(_on_landed)
	player.state_machine.state_changed.connect(_on_state_changed)
	EventBus.player_respawned.connect(func(_p: Node2D, _id: StringName) -> void: AudioManager.play_sfx(sfx_respawn))


## Every sound id this node can request; used by tests to catch typos.
func sound_ids() -> Array[StringName]:
	return [sfx_jump, sfx_slide_jump, sfx_land_soft, sfx_land_hard, sfx_slide, sfx_dodge, sfx_dash, sfx_respawn]


func _world() -> Node:
	return player.get_parent()


func _on_jumped(kind: StringName) -> void:
	AudioManager.play_sfx(sfx_slide_jump if kind == &"slide" else sfx_jump)
	if kind != &"coyote":
		DustBurst.spawn(_world(), player.global_position, jump_dust, Vector2.UP, 70.0, 40.0)


func _on_landed(impact_speed: float) -> void:
	if impact_speed < min_land_speed:
		return
	var hard := impact_speed >= player.config.hard_land_speed
	var t := clampf(impact_speed / player.config.fast_fall_speed, 0.0, 1.0)
	AudioManager.play_sfx(sfx_land_hard if hard else sfx_land_soft, lerpf(0.5, 1.0, t))
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
			DustBurst.spawn(_world(), player.global_position, 6, back, 25.0, 60.0)
		&"dodge":
			AudioManager.play_sfx(sfx_dodge)
		&"dash":
			AudioManager.play_sfx(sfx_dash)
			if player.is_on_floor():
				DustBurst.spawn(_world(), player.global_position, dash_dust, back, 20.0, 90.0)


func _physics_process(delta: float) -> void:
	if player.current_state_id() != &"slide":
		_slide_trail_timer = 0.0
		return
	_slide_trail_timer -= delta
	if _slide_trail_timer <= 0.0:
		_slide_trail_timer = slide_trail_interval
		DustBurst.spawn(_world(), player.global_position, 2, Vector2(-player.facing, -0.6), 30.0, 35.0, 0.25)
