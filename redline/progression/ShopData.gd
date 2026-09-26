class_name ShopData
extends Resource

## Localization (D5 §4.1): player-visible text fields -> max source chars
## (0 = none). The source stays English here; Loc translates at display.
const LOC_FIELDS := {"title": 32}

@export var id: StringName = &""
@export var title: String = ""
@export var items: Array[ShopItem] = []
