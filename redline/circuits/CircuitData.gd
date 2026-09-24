class_name CircuitData
extends Resource
## A build-changing Circuit (bible §11). Effects are declarative so systems
## just ask Game for a stat: `multipliers` multiply (default 1.0), `values`
## add up (default 0.0). Stat names are documented in Docs/CIRCUITS.md.

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Core Capacity used while equipped.
@export_range(1, 5) var cost: int = 1
## Scrap price in shops.
@export var price: int = 60
@export var multipliers: Dictionary = {}
@export var values: Dictionary = {}

const KNOWN_STATS := [
	&"melee_damage", &"ranged_damage", &"damage_taken", &"scrap_gain", &"iframe_time",
	&"environmental_damage", &"ranged_range", &"momentum_damage", &"perfect_dodge_reload",
	&"kills_per_heal", &"perfect_window_bonus", &"predator_damage", &"emergency_loop",
	&"full_health_reactor_bonus", &"runners_debt",
]


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == "" or display_name == "" or description == "":
		errors.append("circuit %s incomplete" % id)
	if multipliers.is_empty() and values.is_empty():
		errors.append("circuit %s has no effect" % id)
	for k in multipliers.keys() + values.keys():
		if not KNOWN_STATS.has(StringName(k)):
			errors.append("circuit %s uses unknown stat %s" % [id, k])
	return errors
