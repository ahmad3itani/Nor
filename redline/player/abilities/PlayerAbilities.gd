class_name PlayerAbilities
extends Resource
## Which traversal unlocks the player currently owns (bible §5).
## Initial moveset (run/jump/slide/dodge...) is always available and not listed.
## Only Dash is implemented in M1; the rest are declared so saves and gates can
## reference them without renaming later.

@export var dash: bool = false
@export var air_dash: bool = false
@export var wall_jump: bool = false
@export var wall_run: bool = false
@export var grapple: bool = false
@export var enemy_bounce: bool = false
@export var ground_slam: bool = false
@export var rail_grind: bool = false
@export var recoil_launch: bool = false
@export var phase_dash: bool = false
@export var pulse_tether: bool = false
@export var overdrive: bool = false
