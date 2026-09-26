class_name RankLadder
extends Resource
## The one medal ladder (D-149, R04.13): five tiers, ids 0..4, used by every
## challenge medal and every Deep Rig rank. Their names live in data
## (data/challenges/rank_ladder.tres: Clear, Bronze, Silver, Gold, Redline) and
## are deliberately NOT the style-rank letters (§10's D..REDLINE ladder), so a
## medal never reads like a style grade. Tier 0 is any finish: finishing
## always earns something (§24, never shaming).

const LOC_FIELDS := {"names": 12}
const PATH := "res://data/challenges/rank_ladder.tres"
const COUNT := 5

## Display names by tier id (English source; callers wrap with Loc.t).
@export var names: PackedStringArray = ["Clear", "Bronze", "Silver", "Gold", "Redline"]

static var _shared: RankLadder = null


static func shared() -> RankLadder:
	if _shared == null:
		_shared = load(PATH) as RankLadder
		if _shared == null:
			_shared = RankLadder.new()
	return _shared


## Source-text name of tier `i` ("" for -1 / no finish).
static func name(i: int) -> String:
	var n := shared().names
	return n[i] if i >= 0 and i < n.size() else ""


static func count() -> int:
	return shared().names.size()


static func clear_cache() -> void:
	_shared = null


func validate() -> PackedStringArray:
	var out := PackedStringArray()
	if names.size() != COUNT:
		out.append("rank ladder needs %d names (has %d)" % [COUNT, names.size()])
	var style_letters := ["D", "C", "B", "A", "S", "SS", "SSS"]
	var seen := {}
	for n in names:
		if n.strip_edges() == "":
			out.append("rank ladder has an empty name")
		elif style_letters.has(n.strip_edges().to_upper()):
			out.append("rank ladder name '%s' reads as a style rank letter (D-149)" % n)
		if seen.has(n):
			out.append("rank ladder name '%s' is used twice" % n)
		seen[n] = true
	return out
