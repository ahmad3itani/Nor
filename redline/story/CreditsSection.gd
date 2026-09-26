class_name CreditsSection
extends Resource
## One heading of the credits roll and the names under it.

const HEADING_MAX := 40
const LINE_MAX := 48

## Localization (D5 §4.1): player-visible text fields -> max source chars
## (0 = none). The source stays English here; Loc translates at display.
const LOC_FIELDS := {"heading": 40, "lines": 60}

@export var heading: String = ""
@export var lines: PackedStringArray = []
