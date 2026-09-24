class_name PlaytestConfig
extends Resource
## Everything the M4 playtest instrumentation is tuned by (bible §37.3).

## Record sessions unless the player turns it off in Settings. Files stay on
## the tester's machine (user://playtests); nothing is ever sent anywhere.
@export var record_by_default: bool = true
## Position sample rate for heatmaps and idle/confusion detection.
@export var sample_interval: float = 0.5
## Session file is rewritten this often, so a crash loses at most this much.
@export var autosave_interval: float = 20.0
## A frame longer than this counts as a spike (ms).
@export var spike_ms: float = 33.4
## Keep at most this many spike records per session (the histogram keeps all).
@export var max_spikes: int = 200
## Standing (almost) still this long outside menus counts as "idle / unsure".
@export var idle_seconds: float = 20.0
## Share of testers that must pass a §44 criterion to count it as met.
@export_range(0.0, 1.0) var pass_ratio: float = 0.6
## §44: "Do not scale production unless external playtesters independently
## report *most* of the following" (10 criteria): most = at least this many.
@export_range(1, 10) var criteria_needed: int = 6
## Position samples closer than this (px) count as "not moving" for idle spans.
@export var idle_radius: float = 8.0
## Tags offered by the "Report a moment" menu.
@export var moment_tags: PackedStringArray = []
@export var variants: Array[PlaytestVariant] = []
@export var survey: Array[SurveyQuestion] = []


func variant(id: String) -> PlaytestVariant:
	for v in variants:
		if v.id == id:
			return v
	return null


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var seen := {}
	for v in variants:
		errors.append_array(v.validate())
		if seen.has(v.id):
			errors.append("duplicate variant %s" % v.id)
		seen[v.id] = true
	seen.clear()
	for q in survey:
		if q.id == "" or q.text == "":
			errors.append("survey question incomplete: %s" % q.id)
		if seen.has(q.id):
			errors.append("duplicate survey question %s" % q.id)
		seen[q.id] = true
		if q.kind == SurveyQuestion.Kind.CHOICE and q.choices.size() < 2:
			errors.append("choice question %s needs choices" % q.id)
	if variants.is_empty():
		errors.append("at least one (baseline) variant is required")
	return errors
