class_name AmbientEmitter
extends Node
## Random ambience one-shots (SOUND_DIRECTION section 7): while active, plays
## `stream` every `interval` seconds (random in [x, y]) with a little volume
## and pan jitter, on its own bus so the pan never moves the bed. Its own
## RandomNumberGenerator keeps the global one (and so route, boss and ghost
## tests) untouched. Headless runs schedule but never create a player.

const BUS := &"AmbienceFx"

var stream: AudioStream = null
var interval: Vector2 = Vector2(4.0, 11.0)
var volume_db: float = -18.0
var volume_jitter: float = 3.0
var pan_jitter: float = 0.6
## Drips fired since start (tests and the PerfProbe read it).
var shots: int = 0

var _active: bool = false
var _wait: float = 0.0
var _rng := RandomNumberGenerator.new()
var _player: AudioStreamPlayer = null


func _ready() -> void:
	_rng.seed = 0x5d21
	if DisplayServer.get_name() != "headless":
		_player = AudioStreamPlayer.new()
		_player.bus = BUS
		add_child(_player)


func configure(s: AudioStream, every: Vector2, db: float, db_jitter: float, pan: float) -> void:
	stream = s
	interval = every
	volume_db = db
	volume_jitter = db_jitter
	pan_jitter = pan


func is_active() -> bool:
	return _active


func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on and stream != null
	if _active:
		_wait = _next_wait()
	elif _player:
		_player.stop()


func _next_wait() -> float:
	return _rng.randf_range(interval.x, maxf(interval.y, interval.x))


## Advances the schedule; returns true when a one-shot fired this step.
func step(delta: float) -> bool:
	if not _active:
		return false
	_wait -= delta
	if _wait > 0.0:
		return false
	_wait = _next_wait()
	shots += 1
	var db := volume_db + _rng.randf_range(-volume_jitter, volume_jitter)
	var pan := _rng.randf_range(-pan_jitter, pan_jitter)
	if _player:
		_set_pan(pan)
		_player.stream = stream
		_player.volume_db = db
		_player.play()
	return true


func _process(delta: float) -> void:
	step(delta)


func _set_pan(pan: float) -> void:
	var idx := AudioServer.get_bus_index(BUS)
	if idx < 0 or AudioServer.get_bus_effect_count(idx) == 0:
		return
	var fx := AudioServer.get_bus_effect(idx, 0) as AudioEffectPanner
	if fx:
		fx.pan = pan
