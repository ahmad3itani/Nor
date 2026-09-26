class_name NgPlusConfig
extends Resource
## What a New Game+ keeps and resets (bible §30, D-153). Carry is a
## whitelist: anything not listed resets, so a new system never leaks into
## NG+ by accident. NewGamePlus.carry() reads this; the shipped values live
## in data/ngplus/ng_plus.tres.

## No player-facing text: flag names and numbers only.
const LOC_FIELDS := {}
const LOC_EXEMPT := ["carry_flags", "carry_flag_prefixes", "optional_abilities", "skip_start_flags", "cycle_flag",
	"remix_flag", "keep_dash_flag"]

## Flags NG+ must never carry, whatever the lists above say: the story,
## bosses, quests, arcs and seen scenes all start over (validate()).
const DENY_EXACT: PackedStringArray = ["act1_complete", "slice_end_seen", "unlocked_dash"]
const DENY_PREFIXES: PackedStringArray = ["quest_", "arc_", "mem_seen_", "seen_seq_"]
const DENY_SUFFIXES: PackedStringArray = ["_defeated"]

@export var carry_weapons: bool = true
@export var carry_circuits: bool = true
@export var carry_core_shards: bool = true
@export var carry_scrap_banked: bool = true
## Every ShopItem.upgrade_flag (read from data/shops at runtime).
@export var carry_shop_upgrades: bool = true
## Flags kept by exact name.
@export var carry_flags: PackedStringArray = ["null_open", "null_depth_reached"]
## Flags kept by prefix (tutorials never repeat; Null bookkeeping).
@export var carry_flag_prefixes: PackedStringArray = ["hint_", "null_"]
## Abilities kept when the "Start with the Dash" option is on.
@export var optional_abilities: PackedStringArray = ["dash"]
## Onboarding start flags NOT applied in NG+ (the Core HUD is known).
@export var skip_start_flags: PackedStringArray = ["core_hud_hidden"]
@export var cycle_flag: String = "ng_cycle"
@export var remix_flag: String = "ng_remix"
@export var keep_dash_flag: String = "ng_keep_dash"
## "NG+9" and beyond reads "NG+9+".
@export var max_cycle_label: int = 9
## R09.2/R09.6: secret Scrap stashes refill in NG+ but pay this share of
## their Scrap (roundi), so re-finding them is worth a look without turning
## every cycle into a Scrap farm (EconomyAudit.compute(true) counts it).
@export_range(0.0, 1.0) var secret_scrap_scale: float = 0.25
## A Scrap bundle within this many pixels of a BreakableWall or of a
## fragment/shard spot is a secret stash (it refills); every other bundle is
## plain loot on the path and stays taken (NewGamePlus.secret_bundles_in).
@export var secret_spot_radius: float = 96.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for pair: Array in [["cycle_flag", cycle_flag], ["remix_flag", remix_flag], ["keep_dash_flag", keep_dash_flag]]:
		if String(pair[1]) == "":
			errors.append("NgPlusConfig: %s is empty" % pair[0])
	for p in carry_flag_prefixes:
		if not p.ends_with("_"):
			errors.append("NgPlusConfig: carry prefix '%s' must end in '_'" % p)
		if denied(p):
			errors.append("NgPlusConfig: carry prefix '%s' would carry story state" % p)
	for f in carry_flags:
		if denied(f):
			errors.append("NgPlusConfig: '%s' is story state and never carries" % f)
	for a in optional_abilities:
		if not a in PlayerAbilities.new():
			errors.append("NgPlusConfig: optional ability '%s' is not a PlayerAbilities field" % a)
	if max_cycle_label < 1:
		errors.append("NgPlusConfig: max_cycle_label must be >= 1")
	if secret_scrap_scale < 0.0 or secret_scrap_scale > 1.0:
		errors.append("NgPlusConfig: secret_scrap_scale must be within 0..1 (%s)" % secret_scrap_scale)
	if secret_spot_radius <= 0.0:
		errors.append("NgPlusConfig: secret_spot_radius must be > 0")
	return errors


## Content protocol: NG+ writes the three option/cycle flags, so conditions
## that read them (remix active_when, "atleast:ng_cycle:1") lint clean.
func content_flags() -> Dictionary:
	return {"produces": [cycle_flag, remix_flag, keep_dash_flag]}


## Whether a flag (or a prefix) is on the never-carry list.
static func denied(f: String) -> bool:
	if DENY_EXACT.has(f):
		return true
	for p in DENY_PREFIXES:
		if f.begins_with(p) or p.begins_with(f):
			return true
	for s in DENY_SUFFIXES:
		if f.ends_with(s):
			return true
	return false


## Whether the flag `f` carries into the next cycle (exact name or prefix).
func carries_flag(f: String) -> bool:
	if denied(f):
		return false
	if carry_flags.has(f):
		return true
	for p in carry_flag_prefixes:
		if f.begins_with(p):
			return true
	return false
