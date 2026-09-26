class_name RemixOp
extends Resource
## One NG+ remix operation on a room instance (bible §30, D-154). Ops are
## data: an enemy added, removed or swapped, or one whitelisted property set
## on an enemy, a hazard or a boss behaviour. Geometry, exits, collectibles
## and arena gates are never touched, so routes and door contracts hold.

## No player-facing text (node paths and property names).
const LOC_FIELDS := {}
const LOC_EXEMPT := ["scene_kind"]

enum Kind { ADD_ENEMY, REMOVE_ENEMY, SWAP_ENEMY, SET }

## RoomGen SCENES keys an ADD/SWAP may name (tools/roomgen/roomgen.py).
const SCENES := {
	"Needle": "res://enemies/variants/Needle.tscn", "Shield": "res://enemies/variants/Shield.tscn",
	"ScoutDrone": "res://enemies/variants/ScoutDrone.tscn", "Hopper": "res://enemies/variants/Hopper.tscn",
	"Watcher": "res://enemies/variants/Watcher.tscn", "Enforcer": "res://enemies/variants/Enforcer.tscn",
}

## Allowed SET properties by class (RemixRules RM-3 and a test pin it). The
## class is the node's script class_name (or its engine class).
const SET_WHITELIST := {
	"Enemy": [&"data", &"facing"],
	"ScannerBeam": [&"data", &"phase"],
	"PowerShutter": [&"timing"],
	"GridClamp": [&"timing"],
	"ChaseDirector": [&"data"],
	"FlowZone": [&"drain_scale", &"drain_floor"],
	"WardenKrailBehavior": [&"phase2_threshold", &"phase2_telegraph_scale", &"close_range", &"far_range", &"summon_scene", &"summon_offsets", &"phase_pause"],
	"CollectorDroneBehavior": [&"phase2_threshold", &"phase2_telegraph_scale", &"phase2_speed_mult", &"stalk_speed", &"setup_speed", &"sag_hold", &"first_deck", &"deck_p1", &"deck_p2", &"rng_seed"],
}

@export var kind: Kind = Kind.SET
## Path from the room root, e.g. "Enemies/Needle3", "Hazards/Scanner_ss_full_1",
## "Enemies/WardenKrail1/Behavior". ADD_ENEMY: the node it is placed beside.
@export var target: NodePath
## ADD/SWAP: one of the SCENES keys ("Needle", "Shield", ...).
@export var scene_kind: String = ""
## ADD/SWAP: a *_remix EnemyData (scrap_drop 0, RM-5). A SWAP replacement
## takes the replaced enemy's drop at runtime (R09.11).
@export var data: EnemyData
## ADD: from the target's position (same floor).
@export var offset: Vector2 = Vector2.ZERO
## ADD/SWAP: 0 = copy the target's facing.
@export var facing: int = 0
## SET: the property to write.
@export var property: StringName = &""
## SET: the value (Resource, float, int, bool, Vector2 or a typed Array).
## Not an @export (4.3 cannot export a Variant): _get_property_list stores it.
var value: Variant = null


func _get_property_list() -> Array[Dictionary]:
	return [{"name": "value", "type": TYPE_NIL, "usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_NIL_IS_VARIANT}]


## The class names that decide the SET whitelist for `node`: its script's
## class_name chain first (a script without one, like the boss behaviours,
## answers to its file name), then the engine class.
static func class_names(node: Object) -> PackedStringArray:
	var out := PackedStringArray()
	var s := node.get_script() as Script
	while s != null:
		var g := String(s.get_global_name())
		if g == "" and s.resource_path != "":
			g = s.resource_path.get_file().get_basename()
		if g != "":
			out.append(g)
		s = s.get_base_script()
	out.append(node.get_class())
	return out


## Whether SET `property` is allowed on `node`.
static func settable(node: Object, property_name: StringName) -> bool:
	for c in class_names(node):
		if SET_WHITELIST.has(c) and (SET_WHITELIST[c] as Array).has(property_name):
			return true
	return false


func describe() -> String:
	match kind:
		Kind.ADD_ENEMY:
			return "ADD %s beside %s %s" % [scene_kind, target, offset]
		Kind.REMOVE_ENEMY:
			return "REMOVE %s" % target
		Kind.SWAP_ENEMY:
			return "SWAP %s -> %s" % [target, scene_kind]
	return "SET %s.%s" % [target, property]
