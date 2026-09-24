class_name PlayerStateMachine
extends RefCounted
## Tiny explicit FSM. States are registered by id; transitions are returned by
## states, never forced from outside except respawn (force_state).

const MAX_CHAINED_TRANSITIONS := 4

signal state_changed(from_state: StringName, to_state: StringName)

var states: Dictionary = {}
var current: PlayerState


func add_state(state: PlayerState) -> void:
	states[state.id] = state


func start(initial: StringName) -> void:
	current = states[initial]
	current.time_in_state = 0.0
	current.enter(&"")


func force_state(id: StringName) -> void:
	_switch(id)


func physics_update(input: PlayerInputFrame, delta: float) -> void:
	current.time_in_state += delta
	var next := current.physics_update(input, delta)
	var hops := 0
	# The receiving state runs in the same tick so inputs never lose a frame.
	while next != &"" and hops < MAX_CHAINED_TRANSITIONS:
		_switch(next)
		next = current.physics_update(input, delta)
		hops += 1
	if hops == MAX_CHAINED_TRANSITIONS and next != &"":
		push_warning("PlayerStateMachine: transition loop detected at %s -> %s" % [current.id, next])


func _switch(id: StringName) -> void:
	assert(states.has(id), "Unknown player state: %s" % id)
	var previous := current.id if current else &""
	if current:
		current.exit(id)
	current = states[id]
	current.time_in_state = 0.0
	current.enter(previous)
	state_changed.emit(previous, id)
