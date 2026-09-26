class_name ChallengeStage
extends Resource
## One stage of a staged challenge (a Deep Rig stratum, M9 D3 §3.3 folded into
## ChallengeData, D-147). A stage is a room with a ChallengeGoal whose
## stage_id matches `id`; its par and redline times feed the RankTable score.

## Player text in this resource (the l10n extractor and length lint read it).
const LOC_FIELDS := {"title": 32}
const LOC_EXEMPT := ["id"]

@export var id: String = ""
@export var title: String = ""
@export_file("*.tscn") var room: String = ""
@export var entry: StringName = &""
## Seconds: 0 time points at RankTable.fail_mult × par, full points at redline.
@export var par_s: float = 60.0
@export var redline_s: float = 40.0
## Multiplies the average style rank before the style points (a stage built
## around one fight can ask for more style).
@export var style_weight: float = 1.0
## When set, the stage's goal fires on this boss's defeat (ChallengeGoal.on_boss).
@export var boss_id: String = ""


func validate() -> PackedStringArray:
	var out := PackedStringArray()
	if id == "" or not RegEx.create_from_string("^[a-z0-9_]+$").search(id):
		out.append("stage id '%s' must be [a-z0-9_]+" % id)
	if title == "":
		out.append("stage %s has no title" % id)
	if room == "" or not ResourceLoader.exists(room):
		out.append("stage %s room '%s' does not exist" % [id, room])
	if par_s <= 0.0 or redline_s <= 0.0 or redline_s >= par_s:
		out.append("stage %s needs 0 < redline_s (%.1f) < par_s (%.1f)" % [id, redline_s, par_s])
	if style_weight < 0.0:
		out.append("stage %s style_weight must be >= 0" % id)
	return out
