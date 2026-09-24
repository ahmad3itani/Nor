extends Node
## Headless tuning probe: runs scripted manoeuvres on flat ground for every
## movement preset and prints the resulting distances/heights as a table.
## Use it to compare presets or check level-metric assumptions (gap widths,
## ledge heights) after editing PlayerMovementConfig values.
##   godot --headless --fixed-fps 60 res://devtools/MovementProbe.tscn

const PRESET_DIR := "res://data/movement"
const PLAYER_SCENE := preload("res://player/Player.tscn")

var _world: Node2D
var _player: Player
var _input: ScriptedInputSource


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _setup(cfg: PlayerMovementConfig, dash: bool) -> void:
	_world = Node2D.new()
	add_child(_world)
	var floor_block := GrayboxBlock.new()
	floor_block.size = Vector2(6000, 64)
	floor_block.position = Vector2(-1000, 0)
	_world.add_child(floor_block)
	_player = PLAYER_SCENE.instantiate()
	_player.config = cfg
	_player.abilities = PlayerAbilities.new()
	_player.abilities.dash = dash
	_input = ScriptedInputSource.new()
	_player.input_source = _input
	_world.add_child(_player)
	_player.respawn(Vector2(0, -2))
	await _frames(5)


func _teardown() -> void:
	_world.queue_free()
	await _frames(1)


## Holds right and performs `setup_action` once at full speed, then jumps
## `jump_delay` frames later. Returns [height, horizontal distance] of the jump.
func _measure_jump(cfg: PlayerMovementConfig, action: StringName, dash := false) -> Vector2:
	await _setup(cfg, dash)
	_input.move_x = 1
	await _frames(30)
	match action:
		&"slide":
			_input.down_held = true
			await _frames(3)
		&"dodge":
			_input.press_dodge()
			await _frames(int(ceil(cfg.dodge_jump_cancel_time * 60.0)) + 1)
		&"dash":
			_input.press_dodge()
			await _frames(int(ceil(cfg.dash_jump_cancel_time * 60.0)) + 1)
	_input.press_jump()
	await _frames(2)
	_input.down_held = false
	# Wait for landing.
	for i in 240:
		await _frames(1)
		if _player.is_on_floor() and i > 3:
			break
	var result := Vector2(_player.metrics.last_jump_height, _player.metrics.last_jump_distance)
	await _teardown()
	return result


func _measure_ground(cfg: PlayerMovementConfig) -> Dictionary:
	await _setup(cfg, false)
	_input.move_x = 1
	var frames_to_max := 0
	for i in 120:
		await _frames(1)
		if _player.velocity.x >= cfg.max_run_speed - 0.01:
			frames_to_max = i + 1
			break
	await _frames(10)
	var x0 := _player.global_position.x
	_input.move_x = 0
	await _frames(30)
	var stop_dist := _player.global_position.x - x0
	_input.move_x = 1
	await _frames(40)
	_input.down_held = true
	var slide_start := _player.global_position.x
	await _frames(int(cfg.slide_max_duration * 60.0) + 2)
	var slide_dist := _player.global_position.x - slide_start
	_input.down_held = false
	_input.move_x = 0
	await _frames(40)
	var dx := _player.global_position.x
	_input.press_dodge()
	await _frames(int(ceil(cfg.dodge_duration * 60.0)))
	var dodge_dist := _player.global_position.x - dx
	await _teardown()
	return {"frames_to_max": frames_to_max, "stop": stop_dist, "slide": slide_dist, "dodge": dodge_dist}


func _run() -> void:
	var files := DirAccess.get_files_at(PRESET_DIR)
	files.sort()
	print("| preset | frames to max run | stop dist | slide dist | dodge dist | jump h / d | slide-jump h / d | dodge-jump h / d | dash-jump h / d |")
	print("|---|---|---|---|---|---|---|---|---|")
	for f in files:
		if not f.ends_with(".tres"):
			continue
		var cfg: PlayerMovementConfig = load("%s/%s" % [PRESET_DIR, f])
		var g := await _measure_ground(cfg)
		var j := await _measure_jump(cfg, &"run")
		var sj := await _measure_jump(cfg, &"slide")
		var dj := await _measure_jump(cfg, &"dodge")
		var ddj := await _measure_jump(cfg, &"dash", true)
		print("| %s | %d | %.1f | %.1f | %.1f | %.1f / %.1f | %.1f / %.1f | %.1f / %.1f | %.1f / %.1f |" % [
			cfg.preset_name, g["frames_to_max"], g["stop"], g["slide"], g["dodge"],
			j.x, j.y, sj.x, sj.y, dj.x, dj.y, ddj.x, ddj.y])
	get_tree().quit()
