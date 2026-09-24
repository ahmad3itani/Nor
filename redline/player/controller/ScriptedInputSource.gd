class_name ScriptedInputSource
extends PlayerInputSource
## Deterministic input for tests: set the held state, and one-shot presses
## are consumed on the next sample.

var move_x: int = 0
var down_held: bool = false
var jump_held: bool = false
var _jump_press_queued: bool = false
var _dodge_press_queued: bool = false


func press_jump() -> void:
	_jump_press_queued = true
	jump_held = true


func release_jump() -> void:
	jump_held = false


func press_dodge() -> void:
	_dodge_press_queued = true


func sample(_config: PlayerMovementConfig) -> PlayerInputFrame:
	var f := PlayerInputFrame.new()
	f.move_x = move_x
	f.move = Vector2(move_x, 1.0 if down_held else 0.0)
	f.down_held = down_held
	f.jump_pressed = _jump_press_queued
	f.jump_held = jump_held
	f.dodge_pressed = _dodge_press_queued
	_jump_press_queued = false
	_dodge_press_queued = false
	return f
