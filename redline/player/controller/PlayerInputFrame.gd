class_name PlayerInputFrame
extends RefCounted
## One tick of player intent. States read this, never the Input singleton,
## so tests and future replays/ghosts (bible §29) can feed scripted input.

## Digitised horizontal intent: -1, 0 or 1.
var move_x: int = 0
## Raw stick/keys vector, for future aiming.
var move: Vector2 = Vector2.ZERO
var down_held: bool = false
var jump_pressed: bool = false
var jump_held: bool = false
var dodge_pressed: bool = false
