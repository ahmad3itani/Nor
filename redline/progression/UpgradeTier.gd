class_name UpgradeTier
extends Resource
## One purchasable step of an UpgradeData (D-182). Effects are declarative,
## like CircuitData: `multipliers` multiply across every owned tier (default
## 1.0) and `values` add up (default 0.0). Gameplay asks Game.upgrade_mult /
## upgrade_value for a stat and never checks which tier is owned.

## Localization (D5 §4.1): player-visible text fields -> max source chars.
const LOC_FIELDS := {"summary": 90}

## Scrap. A granted tier (below) still lists its value for the menu's
## sense of scale, but is never paid and never counted as a sink.
@export var price: int = 100
## Game.check_condition expressions; every one must hold to buy the tier.
@export var requires: PackedStringArray = []
## One line for the menu, e.g. "Mk II: hold heavy to charge. Damage +10%."
@export var summary: String = ""
## stat -> factor (UpgradeData.KNOWN_STATS).
@export var multipliers: Dictionary = {}
## stat -> amount (UpgradeData.KNOWN_STATS).
@export var values: Dictionary = {}
## Mk III only: 1 Power, 2 Flow, 3 Utility. The last three tiers of an
## upgrade with branch 1, 2, 3 are alternatives offered together; 0 = a plain
## tier.
@export_range(0, 3) var branch: int = 0
## Economy act of this tier (0 = the upgrade's own act).
@export var act: int = 0
## Installed free by a story beat (DialogueData.give_upgrade ->
## UpgradeLibrary.grant, D-218): never bought, never an economy sink.
@export var granted: bool = false
