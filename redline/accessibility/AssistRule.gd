class_name AssistRule
extends Resource
## One adaptive-assist rule (bible §23, D4 §10.3): after repeated defeats with
## a matching cause, the suggestion card offers these settings. It never
## applies them by itself; the player answers the card (T11 AssistAdvisor).
## Rules are checked in order and the first match with anything left to
## offer wins.

## Localization (D5): player-visible text fields -> max source chars.
const LOC_FIELDS := {"text": 90}
## Settings keys and cause ids, never shown as text.
const LOC_EXEMPT := ["cause_prefix", "suggest"]

## Damage-source prefix of the deaths ("burnout", "scanner", ...); "" = any cause.
@export var cause_prefix: String = ""
## Only in a boss-fight context.
@export var boss_only: bool = false
## Settings keys the card offers, in row order.
@export var suggest: PackedStringArray = []
## The value each suggested key would be set to (same order as `suggest`).
@export var values: Array = []
## Body line of the card: says what happened, never who the option is for.
@export var text: String = ""


func validate() -> PackedStringArray:
	var out := PackedStringArray()
	if suggest.is_empty():
		out.append("assist rule '%s' suggests nothing" % cause_prefix)
	if suggest.size() != values.size():
		out.append("assist rule '%s': %d keys but %d values" % [cause_prefix, suggest.size(), values.size()])
	if text.strip_edges() == "":
		out.append("assist rule '%s' has no text" % cause_prefix)
	return out
