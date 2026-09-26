class_name RunSession
extends RefCounted
## The live run's bookkeeping (Challenges owns one while a run is active):
## the challenge, where to return, the sandbox, the attempt, the current
## stage and its counts, the style samples and the neutral tags seen.
## Pure data; Challenges does every side effect.

var challenge: ChallengeData
## {"room": path, "entry": id} (a world start) or {"title": true}; {} = stay.
var return_to: Dictionary = {}
var sandbox: ProfileSandbox = null
## CinematicMode.theatre before the run (restored on quit).
var theatre_was: bool = false
## Attempts this session, from 1 (full restarts add one).
var attempt: int = 1
var stage_index: int = 0

## Current stage counts (a stage restart clears frames, hits and style; a
## death adds to deaths and keeps them for the stage's rank).
var stage_frames: int = 0
var stage_hits: int = 0
var stage_deaths: int = 0
## Frames × style rank, for the time-weighted average rank (D3 §3.4).
var style_rank_sum: float = 0.0
var style_rank: int = 0
## Sum of the positive style point deltas this attempt (the SCORE default).
var style_score: float = 0.0
var _style_points: float = 0.0

## [{id, title, frames, hits, deaths, style, score, tier}] per cleared stage.
var stage_results: Array = []
## Neutral tags unioned over the whole run (R04.28): assists, and timing
## ("hitstop_reduced").
var assists: PackedStringArray = PackedStringArray()
var timing: PackedStringArray = PackedStringArray()
## The neutral cause line of a failed run ("Run over: fell").
var cause: String = ""
## ChallengeData.Outcome of the last finished attempt (-1 = none yet).
var last_outcome: int = -1
## Any attempt this session FINISHED (on_finish_flags apply on quit).
var finished_once: bool = false
## Index of the next split_xs line to cross.
var next_split_x: int = 0
## The profile's play time when start() saved it: the start fade never adds
## to it (profile play time excludes run time, D2 §3.4.5).
var profile_play_time: float = 0.0


func _init(ch: ChallengeData = null, ret: Dictionary = {}, p_theatre_was: bool = false) -> void:
	challenge = ch
	return_to = ret.duplicate(true)
	theatre_was = p_theatre_was


## A fresh attempt: stage 0, no results, no style.
func reset_attempt() -> void:
	stage_index = 0
	stage_results = []
	style_score = 0.0
	_style_points = 0.0
	cause = ""
	next_split_x = 0
	assists = PackedStringArray()
	timing = PackedStringArray()
	reset_stage(false)


## The current stage starts again; `keep_deaths` for a death restart.
func reset_stage(keep_deaths: bool) -> void:
	stage_frames = 0
	stage_hits = 0
	if not keep_deaths:
		stage_deaths = 0
	style_rank_sum = 0.0
	style_rank = 0
	next_split_x = 0


func on_style(points: float, rank: int) -> void:
	if points > _style_points:
		style_score += points - _style_points
	_style_points = points
	style_rank = rank


## One counted frame of the stage.
func tick_stage() -> void:
	stage_frames += 1
	style_rank_sum += style_rank


func avg_style_rank() -> float:
	return style_rank_sum / stage_frames if stage_frames > 0 else 0.0


func add_tags(p_assists: PackedStringArray, p_timing: PackedStringArray) -> void:
	for t in p_assists:
		if not assists.has(t):
			assists.append(t)
	for t in p_timing:
		if not timing.has(t):
			timing.append(t)


func tags() -> Dictionary:
	return {"assists": Array(assists), "timing": Array(timing)}
