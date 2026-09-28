class_name ShopItem
extends Resource
## One shop entry. Circuits use their own price unless overridden; weapons
## and upgrades must set price. Upgrades bump an integer flag (upgrade_flag).

enum Kind { CIRCUIT, WEAPON, UPGRADE }

## Localization (D5 §4.1): player-visible text fields -> max source chars
## (0 = none). The source stays English here; Loc translates at display.
const LOC_FIELDS := {"display_name": 32, "description": 140}

@export var kind: Kind = Kind.CIRCUIT
@export var item_id: String = ""
@export var price: int = 0
## Stock appears only once this flag is set (e.g. after the boss).
@export var requires_flag: String = ""
## Economy act of this stock (EconomyAudit per-act bands, D-187).
@export var act: int = 1

@export_group("Upgrade")
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var upgrade_flag: String = ""
@export var max_purchases: int = 1
