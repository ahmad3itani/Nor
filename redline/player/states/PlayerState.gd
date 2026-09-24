class_name PlayerState
extends RefCounted
## Base for movement states. A state owns one movement mode's physics and
## decides the next state; shared physics helpers live on Player (the motor),
## so states stay small and readable.

var player: Player
var config: PlayerMovementConfig:
	get: return player.config
var id: StringName
var time_in_state: float = 0.0


func _init(p_player: Player, p_id: StringName) -> void:
	player = p_player
	id = p_id


func enter(_previous: StringName) -> void:
	pass


func exit(_next: StringName) -> void:
	pass


## Apply this tick's movement. Return the id of the next state, or &"" to stay.
## When a state hands off, the next state runs in the same tick (no dead frame).
func physics_update(_input: PlayerInputFrame, _delta: float) -> StringName:
	return &""


## Label for the debug overlay; states may add sub-phase detail (e.g. rise/apex/fall).
func debug_label() -> String:
	return String(id)


## Transitions shared by every grounded state. Returns &"" when none applies.
func ground_transitions(input: PlayerInputFrame) -> StringName:
	if not player.is_on_floor():
		return &"air"
	if player.wants_evade():
		return player.evade_state()
	if player.jump_buffered():
		if input.down_held and player.is_on_one_way():
			player.drop_through()
			return &"air"
		if player.set_low(false):
			player.start_jump(&"ground")
			return &"air"
	return &""


## Where to go when a grounded state finishes on its own.
func settle_state(input: PlayerInputFrame) -> StringName:
	if input.move_x != 0 or absf(player.velocity.x) > 1.0:
		return &"run"
	return &"idle"
