class_name ShopItem
extends Resource
## One shop entry. Circuits use their own price unless overridden; weapons
## and upgrades must set price. Upgrades bump an integer flag (upgrade_flag).

enum Kind { CIRCUIT, WEAPON, UPGRADE }

@export var kind: Kind = Kind.CIRCUIT
@export var item_id: String = ""
@export var price: int = 0
## Stock appears only once this flag is set (e.g. after the boss).
@export var requires_flag: String = ""

@export_group("Upgrade")
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var upgrade_flag: String = ""
@export var max_purchases: int = 1
