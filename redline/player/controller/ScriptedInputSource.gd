class_name ScriptedInputSource
extends PlayerInputSource
## Deterministic input for tests: set the held state, and one-shot presses
## are consumed on the next sample.

var move_x: int = 0
var down_held: bool = false
var jump_held: bool = false
var up_held: bool = false
var _light_queued: bool = false
var _heavy_queued: bool = false
var _ranged_queued: bool = false
var _interact_queued: bool = false
var _heal_queued: bool = false
var _jump_press_queued: bool = false
var _dodge_press_queued: bool = false


func press_jump() -> void:
	_jump_press_queued = true
	jump_held = true


func release_jump() -> void:
	jump_held = false


func press_dodge() -> void:
	_dodge_press_queued = true


func press_light() -> void:
	_light_queued = true


func press_heavy() -> void:
	_heavy_queued = true


func press_ranged() -> void:
	_ranged_queued = true


func press_interact() -> void:
	_interact_queued = true


func press_heal() -> void:
	_heal_queued = true


func sample(_config: PlayerMovementConfig) -> PlayerInputFrame:
	var f := PlayerInputFrame.new()
	f.move_x = move_x
	f.move = Vector2(move_x, 1.0 if down_held else (-1.0 if up_held else 0.0))
	f.up_held = up_held
	f.light_pressed = _light_queued
	f.heavy_pressed = _heavy_queued
	f.ranged_pressed = _ranged_queued
	_light_queued = false
	_heavy_queued = false
	_ranged_queued = false
	f.interact_pressed = _interact_queued
	f.heal_pressed = _heal_queued
	_interact_queued = false
	_heal_queued = false
	f.down_held = down_held
	f.jump_pressed = _jump_press_queued
	f.jump_held = jump_held
	f.dodge_pressed = _dodge_press_queued
	_jump_press_queued = false
	_dodge_press_queued = false
	return f
