class_name CombatLayers
extends RefCounted
## Physics layer bit values shared by bodies, hurtboxes and queries.
## Names mirror [layer_names] in project.godot.

const WORLD := 1
const PLAYER_BODY := 2
const ONE_WAY := 4
const ENEMY_BODY := 8
const PLAYER_HURTBOX := 16
const ENEMY_HURTBOX := 32
const HAZARD := 64
