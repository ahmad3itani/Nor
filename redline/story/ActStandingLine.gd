class_name ActStandingLine
extends Resource
## One "where things stand" line on an act card: people and places, never a
## score (bible §18 "no morality meter").

const TEXT_MAX := 90

## Localization (D5 §4.1): player-visible text fields -> max source chars
## (0 = none). The source stays English here; Loc translates at display.
const LOC_FIELDS := {"text": 160}

## Game.check_condition; "" = always (the fallback line).
@export var condition: String = ""
@export var text: String = ""
