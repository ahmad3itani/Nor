class_name StatDef
extends Resource
## One tracked stat (M9 D1 §3.2). Kept per profile (GameState.stats) and/or
## for the machine lifetime (LocalStore). Stats are records of play, never a
## scoreboard of failure: deaths exist for the playtest but are not listed on
## the Records page (§24 never shame, R02.8).

const LOC_FIELDS := {"label": 32}
const LOC_EXEMPT := ["id", "api_name"]

## COUNTER adds, MAX keeps the highest, MIN the lowest value above 0 (times),
## DERIVED is computed from the profile (StatsTracker.DERIVED_IDS).
enum Kind { COUNTER, MAX, MIN, DERIVED }
enum Format { INT, TIME, RANK }

@export var id: StringName = &""
@export var kind: Kind = Kind.COUNTER
## Records page label (English source text, translated at display).
@export var label: String = ""
@export var format: Format = Format.INT
## Kept in the machine-wide store.
@export var lifetime: bool = true
## Kept in the profile (GameState.stats), or derived from it.
@export var profile: bool = true
## Listed on the Records page.
@export var shown: bool = true
## Platform stat name (storefront rule: [A-Z0-9_], <= 128). "" = STAT_<ID>.
@export var api_name: String = ""


func api() -> String:
	return api_name if api_name != "" else "STAT_" + String(id).to_upper()


func is_int() -> bool:
	return format != Format.TIME


func validate() -> PackedStringArray:
	var e := PackedStringArray()
	var re := RegEx.create_from_string("^[a-z0-9_]+$")
	if re.search(String(id)) == null:
		e.append("stat id '%s' must be snake_case" % id)
	if label.strip_edges() == "" or label.length() > int(LOC_FIELDS["label"]):
		e.append("stat %s: label must be 1..%d chars" % [id, LOC_FIELDS["label"]])
	if not lifetime and not profile:
		e.append("stat %s is kept nowhere (lifetime and profile both off)" % id)
	return e
