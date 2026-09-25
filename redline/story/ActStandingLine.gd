class_name ActStandingLine
extends Resource
## One "where things stand" line on an act card: people and places, never a
## score (bible §18 "no morality meter").

const TEXT_MAX := 90

## Game.check_condition; "" = always (the fallback line).
@export var condition: String = ""
@export var text: String = ""
