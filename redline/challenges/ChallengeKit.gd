class_name ChallengeKit
extends Resource
## A fixed, fair loadout and world state for a challenge (M9 D2 §2.2). The kit
## IS the whole sandbox GameState: nothing comes from the profile, so records
## compare (D-147). ProfileSandbox.kit_state builds it off-line.
##
## The one exception is use_profile_loadout (the Deep Rig strata): the sandbox
## copies the profile's weapons, circuits, shards and abilities, never its
## progress (health, injectors and Core start full, Scrap 0, flags only the
## kit's set_flags).

## Build like a title New Game (OnboardingConfig start: unarmed, start flags).
@export var campaign_start: bool = false
## "" = unarmed slot.
@export var melee: String = "pulse_blade"
@export var ranged: String = ""
## Owned besides melee/ranged (the Loadout menu is off in runs; this only
## matters for kits that let weapon cycling reach them).
@export var owned_weapons: PackedStringArray = []
## Equipped (and owned) circuits.
@export var circuits: PackedStringArray = []
@export var core_shards: int = 0
## PlayerAbilities property names, e.g. ["dash"].
@export var abilities: PackedStringArray = []
## Story/world state the room needs (copied lists, never read from dev presets).
@export var set_flags: PackedStringArray = []
## Written as false (never erased): the HUD only reacts to flag_changed.
@export var clear_flags: PackedStringArray = []
## {"injector_upgrades": 1}
@export var int_flags: Dictionary = {}
## -1 = the player's Settings.reactor_mode; 0/1/2 forced for the whole run.
@export var reactor_mode: int = -1
@export var core_hud_hidden: bool = false
## Deep Rig: the sandbox is a copy of the profile's loadout (see above).
@export var use_profile_loadout: bool = false


func validate() -> PackedStringArray:
	var out := PackedStringArray()
	if reactor_mode < -1 or reactor_mode > 2:
		out.append("kit reactor_mode %d must be -1..2" % reactor_mode)
	if core_shards < 0:
		out.append("kit core_shards must be >= 0")
	var probe := PlayerAbilities.new()
	for a in abilities:
		if not a in probe:
			out.append("kit ability '%s' is not a PlayerAbilities field" % a)
	for f in set_flags:
		if clear_flags.has(f):
			out.append("kit flag '%s' is both set and cleared" % f)
	for k in int_flags:
		if typeof(int_flags[k]) != TYPE_INT and typeof(int_flags[k]) != TYPE_FLOAT:
			out.append("kit int_flags['%s'] must be a number" % k)
	return out
