extends "res://tests/fixtures/l10n/fixture_line.gd"
## LOC_FIELDS fixture: inherits the line's "text" and adds a subtitle with a
## context (merged up the base-script chain). A subclass cannot redeclare
## LOC_FIELDS on 4.3, hence LOC_FIELDS_EXTRA.

const LOC_FIELDS_EXTRA := {"subtitle": 48}
const LOC_CONTEXT := {"subtitle": "card"}

@export var subtitle: String = ""
