class_name DialogueLine
extends Resource

## Localization (D5 §4.1): player-visible text fields -> max source chars
## (0 = none). The source stays English here; Loc translates at display.
const LOC_FIELDS := {"speaker": 24, "text": 160}

@export var speaker: String = ""
@export_multiline var text: String = ""
