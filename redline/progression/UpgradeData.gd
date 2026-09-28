class_name UpgradeData
extends Resource
## An upgrade line at one station (D-182): Mara's workbench, Vell's Core work
## or Luma's clinic. Ownership is the int flag upg_<id> (tiers owned) plus
## upg_<id>_branch (the Mk III branch picked, 1..3); no GameState key and no
## schema bump. Gameplay only reads stats through Game.upgrade_mult /
## upgrade_value (the Circuit rule, CIRCUITS.md).

enum Category { WEAPON, ABILITY, CORE }
enum Station { WORKBENCH, VELL, LUMA }

## Localization (D5 §4.1): player-visible text fields -> max source chars.
const LOC_FIELDS := {"display_name": 28, "description": 140}

## Stats an upgrade tier may name (Docs/ECONOMY.md "Upgrades"). The Circuit
## namespace (CircuitData.KNOWN_STATS) stays separate: a consumer that
## honours both reads both. max_health_bonus waits for Plate Weave (D-211).
const KNOWN_STATS := [
	&"weapon_damage", &"weapon_poise", &"ammo_bonus", &"reload_time", &"spread", &"charge_heavy", &"charge_time",
	&"hit_reactor_gain", &"style_gain", &"dash_cooldown", &"dash_iframe", &"dodge_cooldown", &"perfect_window_bonus",
	&"riposte", &"heal_time", &"heal_amount_bonus", &"injector_bonus", &"core_capacity_bonus", &"surge", &"surge_cost",
	&"surge_window", &"surge_radius", &"surge_launch", &"parry", &"parry_window_bonus", &"parry_poise", &"flow_drain",
]

## The flag is "upg_" + id.
@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var category: Category = Category.WEAPON
@export var station: Station = Station.WORKBENCH
## WEAPON: the stats count only while this weapon is equipped ("" = global).
@export var weapon_id: String = ""
## Economy act of the tiers that leave UpgradeTier.act at 0.
@export var act: int = 1
## Index = tier - 1. A Mk III branch group is the last three entries, with
## branch 1, 2 and 3.
@export var tiers: Array[UpgradeTier] = []
## Scrap to swap an owned Mk III branch at the workbench (a repeatable sink,
## kept out of the one-time economy bands).
@export var rebranch_price: int = 40


func flag() -> String:
	return "upg_" + id


func branch_flag() -> String:
	return "upg_%s_branch" % id


## Index of the first branch tier, or -1 when the upgrade has no branch group.
func branch_start() -> int:
	for i in tiers.size():
		if tiers[i] != null and tiers[i].branch != 0:
			return i
	return -1


## The highest tier number a player can own (a branch group counts once).
func max_tier() -> int:
	var b := branch_start()
	return tiers.size() if b < 0 else b + 1


## The economy act of tier `t`.
func tier_act(t: UpgradeTier) -> int:
	return t.act if t != null and t.act > 0 else act


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == "" or display_name == "":
		errors.append("upgrade %s incomplete (id, display_name)" % id)
	if tiers.is_empty():
		errors.append("upgrade %s has no tiers" % id)
	var b := branch_start()
	for i in tiers.size():
		var t := tiers[i]
		if t == null:
			errors.append("upgrade %s: empty tier slot %d" % [id, i + 1])
			continue
		if t.price <= 0:
			errors.append("upgrade %s: tier %d needs a price > 0" % [id, i + 1])
		if t.multipliers.is_empty() and t.values.is_empty():
			errors.append("upgrade %s: tier %d has no effect" % [id, i + 1])
		for k in t.multipliers.keys() + t.values.keys():
			if not KNOWN_STATS.has(StringName(k)):
				errors.append("upgrade %s: tier %d uses unknown stat %s" % [id, i + 1, k])
		for c in t.requires:
			if not ContentValidator.is_valid_condition(c):
				errors.append("upgrade %s: tier %d requires '%s', not a valid condition" % [id, i + 1, c])
		if t.granted and t.branch != 0:
			errors.append("upgrade %s: a branch tier cannot be granted" % id)
	# A branch group is the last three tiers, branches 1, 2, 3 in order.
	if b >= 0:
		if tiers.size() - b != 3:
			errors.append("upgrade %s: a branch group is exactly the last 3 tiers" % id)
		else:
			for j in 3:
				if tiers[b + j] == null or tiers[b + j].branch != j + 1:
					errors.append("upgrade %s: branch tiers must be 1, 2, 3 in order" % id)
					break
	if weapon_id != "" and Game.catalog.weapon(weapon_id) == null:
		errors.append("upgrade %s: weapon '%s' not in catalog" % [id, weapon_id])
	if category == Category.WEAPON and weapon_id == "":
		errors.append("upgrade %s: a WEAPON upgrade names its weapon_id" % id)
	return errors


## Resource content protocol (D-133): the tier flags are produced here (the
## station's buy), every `requires` is read.
func content_flags() -> Dictionary:
	var produces: Array[String] = [flag()]
	if branch_start() >= 0:
		produces.append(branch_flag())
	var conditions: Array[String] = []
	for t in tiers:
		if t != null:
			for c in t.requires:
				conditions.append(c)
	return {"produces": produces, "conditions": conditions}


## Cross-file checks: a schematic a tier needs exists (SchematicList).
func content_check() -> PackedStringArray:
	var errors := PackedStringArray()
	var names := SchematicList.shared()
	for t in tiers:
		if t == null:
			continue
		for c in t.requires:
			var e := c.trim_prefix("!")
			if e.begins_with("flag:sch_") and not names.has_id(e.trim_prefix("flag:sch_")):
				errors.append("upgrade %s requires unknown schematic '%s'" % [id, e.trim_prefix("flag:")])
	return errors
