class_name MemorySceneData
extends Resource
## A playable memory vignette (bible §18, §21, §39 "memory-scene assets").
## A short, player-paced tableau with 3-6 beats, a pan across a scene wider
## than the screen and one optional hidden detail. FRAGMENT scenes unlock
## when their fragment is recovered; SURFACED scenes (no pickup) unlock on
## `unlock_condition`. Always adds to a mystery rather than explaining it.
##
## Played by ui/memory/MemoryScenePlayer.gd at Anchors and from the journal
## (never on pickup, D-112). State is flags only (D-116): mem_seen_<id>,
## mem_detail_<id>, memories_remembered.

enum Source { FRAGMENT, SURFACED }

const VIEW_HALF := 240.0
const MIN_WIDTH := 480
const MAX_WIDTH := 720
const MAX_BEAT_CHARS := 110
const MAX_TOTAL_CHARS := 400
const MAX_DETAIL_CHARS := 120
const LORE_DIR := "res://data/lore"

## == fragment.id for FRAGMENT scenes.
@export var id: String = ""
@export var source: Source = Source.FRAGMENT
## Required for FRAGMENT, null for SURFACED.
@export var fragment: MemoryFragmentData
## SURFACED only; FRAGMENT scenes use fragment.title.
@export var title: String = ""
## SURFACED only (Game.check_condition syntax; "" = always).
@export var unlock_condition: String = ""
## Gallery grouping; later acts add scenes.
@export var act: int = 1
## Gallery order in Rook's life, spaced by 100 so later acts can insert.
@export var timeline_slot: int = 0
## Higher plays first when several are pending at one rest.
@export var queue_priority: int = 0
## 480..720; wider than 480 lets the player pan.
@export var tableau_width: int = 480
## View centre at open.
@export var start_view_x: float = 240.0
@export var shapes: Array[MemoryShape] = []
@export var beats: Array[MemoryBeat] = []
## Optional line revealed by centring the view on detail_x for a moment.
@export var detail_text: String = ""
## Tableau x of the detail (-1 = none). Only the player's pan can reach it:
## never within detail_radius of start_view_x or of any beat's view_x.
@export var detail_x: float = -1.0
## The detail can be found from this beat index on.
@export var detail_from_beat: int = 0
## Deterministic static, so captures are reproducible.
@export var burn_seed: int = 0


func display_title() -> String:
	if source == Source.FRAGMENT and fragment:
		return fragment.title
	return title


## The journal card: the fragment's own text, or the beats joined.
func card_text() -> String:
	if source == Source.FRAGMENT and fragment:
		return fragment.text
	var parts := PackedStringArray()
	for b in beats:
		parts.append(b.text)
	return " ".join(parts)


func has_detail() -> bool:
	return detail_x >= 0.0


func max_view_x() -> float:
	return maxf(VIEW_HALF, tableau_width - VIEW_HALF)


## Per-scene rules (A2 §8 as amended by the M8 plan); the validator calls it
## for every data/memories scene.
func validate() -> PackedStringArray:
	return validate_with(40.0)


func validate_with(radius: float) -> PackedStringArray:
	var e := PackedStringArray()
	var tag := id if id != "" else "(no id)"
	if id == "":
		e.append("memory scene needs an id")
	if source == Source.FRAGMENT:
		if fragment == null:
			e.append("memory %s: FRAGMENT scene needs a fragment" % tag)
		elif fragment.id != id:
			e.append("memory %s: id must equal its fragment id '%s'" % [tag, fragment.id])
		if unlock_condition != "":
			e.append("memory %s: FRAGMENT scenes unlock on pickup, not unlock_condition" % tag)
	else:
		if title == "":
			e.append("memory %s: SURFACED scene needs a title" % tag)
		if fragment != null:
			e.append("memory %s: SURFACED scene must not have a fragment" % tag)
		if not ContentValidator.is_valid_condition(unlock_condition):
			e.append("memory %s: bad unlock_condition '%s'" % [tag, unlock_condition])
	if beats.size() < 3 or beats.size() > 6:
		e.append("memory %s: needs 3-6 beats (has %d)" % [tag, beats.size()])
	if tableau_width < MIN_WIDTH or tableau_width > MAX_WIDTH:
		e.append("memory %s: tableau_width %d outside %d..%d" % [tag, tableau_width, MIN_WIDTH, MAX_WIDTH])
	var lo := VIEW_HALF
	var hi := max_view_x()
	if start_view_x < lo or start_view_x > hi:
		e.append("memory %s: start_view_x %.0f outside [%.0f, %.0f]" % [tag, start_view_x, lo, hi])
	var total := 0
	var re := RegEx.create_from_string("^[A-Z][A-Z ]{0,15}$")
	for i in beats.size():
		var b := beats[i]
		if b == null:
			e.append("memory %s: beat %d is empty" % [tag, i])
			continue
		total += b.text.length()
		if b.text.length() < 1 or b.text.length() > MAX_BEAT_CHARS:
			e.append("memory %s: beat %d text is %d chars (1..%d)" % [tag, i, b.text.length(), MAX_BEAT_CHARS])
		if b.speaker != "" and re.search(b.speaker) == null:
			e.append("memory %s: beat %d speaker '%s' must be UPPERCASE, <= 16 chars" % [tag, i, b.speaker])
		if b.view_x != -1.0 and (b.view_x < lo or b.view_x > hi):
			e.append("memory %s: beat %d view_x %.0f outside [%.0f, %.0f]" % [tag, i, b.view_x, lo, hi])
		if b.burn < 0.0 or b.burn > 1.0:
			e.append("memory %s: beat %d burn outside 0..1" % [tag, i])
		if b.min_seconds < 0.2 or b.min_seconds > 2.0:
			e.append("memory %s: beat %d min_seconds outside 0.2..2.0" % [tag, i])
	if total > MAX_TOTAL_CHARS:
		e.append("memory %s: beats total %d chars (max %d)" % [tag, total, MAX_TOTAL_CHARS])
	if has_detail():
		if detail_text == "" or detail_text.length() > MAX_DETAIL_CHARS:
			e.append("memory %s: detail_text must be 1..%d chars" % [tag, MAX_DETAIL_CHARS])
		if detail_from_beat < 0 or detail_from_beat >= beats.size():
			e.append("memory %s: detail_from_beat %d is not a beat" % [tag, detail_from_beat])
		# Reachable by panning: the view centre is clamped to [lo, hi].
		if detail_x < lo - radius or detail_x > hi + radius:
			e.append("memory %s: detail_x %.0f is unreachable (view centre %.0f..%.0f, radius %.0f)" % [tag, detail_x, lo, hi, radius])
		# Hidden: only the player's own pan may reveal it.
		if absf(detail_x - start_view_x) <= radius:
			e.append("memory %s: detail_x %.0f is within the radius of start_view_x" % [tag, detail_x])
		for i in beats.size():
			if beats[i] and beats[i].view_x != -1.0 and absf(detail_x - beats[i].view_x) <= radius:
				e.append("memory %s: detail_x %.0f is revealed by beat %d's auto-pan" % [tag, detail_x, i])
	elif detail_text != "":
		e.append("memory %s: detail_text without detail_x" % tag)
	for s in shapes:
		if s == null:
			e.append("memory %s: empty shape" % tag)
			continue
		if s.from_beat < 0 or s.from_beat >= beats.size() or (s.to_beat != -1 and (s.to_beat < s.from_beat or s.to_beat >= beats.size())):
			e.append("memory %s: shape beats %d..%d outside the scene" % [tag, s.from_beat, s.to_beat])
		if s.tone < 0 or s.tone > 2:
			e.append("memory %s: shape tone %d outside 0..2" % [tag, s.tone])
	return e


## Resource content protocol (ContentValidator.check_resource).
func content_flags() -> Dictionary:
	var produces: Array[String] = [flag_seen(), "memories_remembered"]
	if has_detail():
		produces.append(flag_detail())
	var conditions: Array[String] = []
	if unlock_condition != "":
		conditions.append(unlock_condition)
	return {"produces": produces, "conditions": conditions}


func content_check() -> PackedStringArray:
	var e := PackedStringArray()
	if source == Source.FRAGMENT and fragment:
		var expected := "%s/%s.tres" % [LORE_DIR, id]
		if fragment.resource_path != expected:
			e.append("memory %s: fragment must be %s (is '%s')" % [id, expected, fragment.resource_path])
	return e


func flag_seen() -> String:
	return "mem_seen_" + id


func flag_detail() -> String:
	return "mem_detail_" + id
