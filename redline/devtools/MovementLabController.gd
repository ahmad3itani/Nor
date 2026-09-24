extends Node
## Movement Lab dev hotkeys (bible §34). Keeps debug-only behaviour out of
## Player and Room. Lives as a child of the lab room.
##   Tab / R3  next spawn station      F2  toggle Dash unlock
##   F4        slow motion (x0.25)     F5  hot-reload movement config from disk
##   F6        cycle tuning presets

@export var presets: Array[String] = [
	"res://data/movement/default_movement.tres",
	"res://data/movement/tight_movement.tres",
	"res://data/movement/floaty_movement.tres",
]
@export var slowmo_scale: float = 0.25

var _preset_index: int = 0

@onready var room: Room = get_parent()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("debug_next_spawn"):
		room.cycle_spawn(1)
	if Input.is_action_just_pressed("debug_toggle_dash"):
		Game.set_ability(&"dash", not Game.abilities.dash)
	if Input.is_action_just_pressed("debug_slowmo"):
		Engine.time_scale = slowmo_scale if is_equal_approx(Engine.time_scale, 1.0) else 1.0
	if Input.is_action_just_pressed("debug_reload_config"):
		_load_preset(_preset_index)
	if Input.is_action_just_pressed("debug_cycle_preset"):
		_load_preset(wrapi(_preset_index + 1, 0, presets.size()))


func _load_preset(index: int) -> void:
	# CACHE_MODE_IGNORE so edits saved in the editor while the game runs are picked up.
	var cfg := ResourceLoader.load(presets[index], "", ResourceLoader.CACHE_MODE_IGNORE) as PlayerMovementConfig
	if cfg == null:
		push_error("MovementLab: failed to load %s" % presets[index])
		return
	var problems := cfg.validate()
	if not problems.is_empty():
		push_error("MovementLab: %s invalid: %s" % [presets[index], ", ".join(problems)])
		return
	_preset_index = index
	room.player.apply_config(cfg)
	EventBus.movement_config_changed.emit(cfg)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
