class_name ChallengeData
extends Resource
## One challenge (M9 D2 §2.1 merged with D3's run model, D-147/D-148): boss
## rematches, time trials, Nerve runs (no hit / movement only), the Pulse Pit
## and the Deep Rig strata are all this one resource, run by the Challenges
## autoload inside a ProfileSandbox. Content lives in data/challenges/*.tres
## (T08, T10); this file only defines the schema and its pure rules.
##
## Medals: medal_thresholds holds 4 values (Bronze, Silver, Gold, Redline):
## frames for TIME (lower is better), points for SCORE (higher is better).
## Any finish is tier 0 (Clear). RANK challenges take their tier from
## rank_table. Tier names come from RankLadder (data), never style letters.

## NULL first: the menu lists the Deep Rig first ('null' is an internal id).
enum Group { NULL, BOSS_REMATCH, TIME_TRIAL, NERVE, PULSE_PIT }
## TIME frames lower-better; SCORE points higher-better; RANK = RankTable
## score 0..1000 higher-better.
enum ScoreKind { TIME, SCORE, RANK }
enum StartOn { FIRST_INPUT, ROOM_READY, BOSS_STARTED }
enum EndOn { EXIT, BOSS_DEFEATED, TIME_LIMIT, DEATH, GOAL }
enum OnDeath { END_RUN, RESTART_STAGE, FINISH }
enum Outcome { FINISHED, FAILED_HIT, FAILED_ATTACK, DIED, QUIT }

const LOC_FIELDS := {"title": 40, "description": 120, "locked_hint": 60, "requires_text": 60}
const LOC_EXEMPT := ["id"]
## Developer-ghost bots (T08's GhostBake binds them).
const DEV_BOTS: Array[StringName] = [&"none", &"route", &"boss_blade", &"boss_pistol"]

@export var id: String = ""
## Bump when the room, boss or kit changes: older records archive (D2 §5.4).
@export var revision: int = 1
@export var group: Group = Group.BOSS_REMATCH
@export var title: String = ""
@export_multiline var description: String = ""
## Shown on a locked row, e.g. "Defeat the Collector Drone." Never shaming.
@export var locked_hint: String = ""
## Game.check_condition on the PROFILE state ("" = always).
@export var unlock_when: String = ""
## When the locked row shows its title and hint ("" = unlock_when; R04.12).
@export var reveal_when: String = ""
## Profile conditions checked at start (e.g. "ability:dash").
@export var requires: PackedStringArray = []
@export var requires_text: String = ""
@export var sort_order: int = 0

@export_file("*.tscn") var start_room: String = ""
@export var start_entry: StringName = &""
@export var kit: ChallengeKit

@export var score_kind: ScoreKind = ScoreKind.TIME
@export var start_on: StartOn = StartOn.FIRST_INPUT
@export var end_on: EndOn = EndOn.EXIT
@export var on_death: OnDeath = OnDeath.END_RUN
## EXIT: the RoomExit.target_room the finish line replaces.
@export_file("*.tscn") var finish_exit_target: String = ""
## EXIT: the room the finish line sits in ("" = start_room).
@export var finish_room: String = ""
## BOSS_DEFEATED (and BOSS_STARTED starts): the BossArena.boss_id.
@export var boss_id: String = ""
## TIME_LIMIT: seconds (0 = none).
@export var time_limit_s: float = 0.0

## No hit: any player_damaged ends the run (pits and burnout included).
@export var fail_on_damage: bool = false
## Movement only: a swing or a shot ends the run (reloads do not).
@export var fail_on_attack: bool = false

## A split at boss_defeated (live delta against the personal best).
@export var split_boss: bool = true
## Single-room checkpoint lines (room-local x crossings, left to right).
@export var split_xs: PackedFloat32Array = []

## Bronze, Silver, Gold, Redline (see the header). Unused for RANK.
@export var medal_thresholds: PackedInt32Array = []
## Staged runs (Deep Rig): empty = one implicit stage (the start room).
@export var stages: Array[ChallengeStage] = []
## RANK only.
@export var rank_table: RankTable
## Pulse Pit waves (T10's WaveSet; typed as Resource so this schema never
## names another task's class).
@export var waves: Resource
## Profile flags set AFTER the restore when the run FINISHED
## (e.g. null_depth_reached).
@export var on_finish_flags: PackedStringArray = []

## Developer ghost (T08 GhostBake): &"none" | &"route" | &"boss_blade" | &"boss_pistol".
@export var dev_bot: StringName = &"none"
## RouteBot steps (the one source of truth for the bake).
@export var dev_route: Array = []
@export_file("*.ghost") var dev_ghost: String = ""


func stage_count() -> int:
	return maxi(1, stages.size())


## The stage at `i`, or null for the implicit single stage.
func stage(i: int) -> ChallengeStage:
	return stages[i] if i >= 0 and i < stages.size() else null


func stage_room(i: int) -> String:
	var s := stage(i)
	return s.room if s and s.room != "" else start_room


func stage_entry(i: int) -> StringName:
	var s := stage(i)
	return s.entry if s and s.room != "" else start_entry


func finish_room_path() -> String:
	return finish_room if finish_room != "" else start_room


## Every room path the run can load or ends at (the demo filter reads it).
func room_paths() -> PackedStringArray:
	var out := PackedStringArray([start_room])
	for s in stages:
		if s and s.room != "" and not out.has(s.room):
			out.append(s.room)
	if end_on == EndOn.EXIT:
		for p in [finish_room_path(), finish_exit_target]:
			if p != "" and not out.has(p):
				out.append(p)
	return out


func reveal_condition() -> String:
	return reveal_when if reveal_when != "" else unlock_when


## True when `a` beats `b` for this score kind (-1 = no value, beaten by any).
func is_better(a: int, b: int) -> bool:
	if a < 0:
		return false
	if b < 0:
		return true
	return a < b if score_kind == ScoreKind.TIME else a > b


## -1 no finish; 0 Clear .. 4 Redline (RankLadder ids). RANK delegates to
## rank_table (the score alone; Challenges applies the per-stage rules).
func medal_for(value: int) -> int:
	if value < 0:
		return -1
	if score_kind == ScoreKind.RANK:
		return rank_table.tier_for_score(value) if rank_table else 0
	var tier := 0
	for i in medal_thresholds.size():
		var t := medal_thresholds[i]
		var ok := value <= t if score_kind == ScoreKind.TIME else value >= t
		if not ok:
			break
		tier = i + 1
	return mini(tier, RankTable.TOP_TIER)


func validate() -> PackedStringArray:
	var out := PackedStringArray()
	if id == "" or not RegEx.create_from_string("^[a-z0-9_]+$").search(id):
		out.append("challenge id '%s' must be [a-z0-9_]+" % id)
	if revision < 1:
		out.append("%s: revision must be >= 1" % id)
	if title == "":
		out.append("%s: no title" % id)
	if start_room == "" or not ResourceLoader.exists(start_room):
		out.append("%s: start_room '%s' does not exist" % [id, start_room])
	if kit == null:
		out.append("%s: no kit" % id)
	else:
		for e in kit.validate():
			out.append("%s: %s" % [id, e])
	for c in [unlock_when, reveal_when] + Array(requires):
		if not ContentValidator.is_valid_condition(String(c)):
			out.append("%s: invalid condition '%s'" % [id, c])
	if not requires.is_empty() and requires_text == "":
		out.append("%s: requires needs a requires_text" % id)
	match end_on:
		EndOn.EXIT:
			if finish_exit_target == "":
				out.append("%s: EXIT needs finish_exit_target" % id)
		EndOn.BOSS_DEFEATED:
			if boss_id == "":
				out.append("%s: BOSS_DEFEATED needs boss_id" % id)
		EndOn.TIME_LIMIT:
			if time_limit_s <= 0.0:
				out.append("%s: TIME_LIMIT needs time_limit_s > 0" % id)
		EndOn.DEATH:
			# A death is the run's end only when it finishes it (a survival run).
			if on_death != OnDeath.FINISH:
				out.append("%s: DEATH needs on_death FINISH" % id)
		EndOn.GOAL:
			pass
	# Every RoomExit in a run room is off (a run never carries Rook into a
	# sandboxed world room), so a run finishes in the room it starts in.
	if finish_room != "" and finish_room != start_room:
		out.append("%s: finish_room must be empty or the start_room (exits are off in runs)" % id)
	if start_on == StartOn.BOSS_STARTED and boss_id == "" and stages.all(func(s: ChallengeStage) -> bool: return s == null or s.boss_id == ""):
		out.append("%s: BOSS_STARTED needs a boss_id" % id)
	if time_limit_s < 0.0:
		out.append("%s: time_limit_s must be >= 0" % id)
	out.append_array(_validate_medals())
	var stage_ids := {}
	for s in stages:
		if s == null:
			out.append("%s: empty stage" % id)
			continue
		for e in s.validate():
			out.append("%s: %s" % [id, e])
		if stage_ids.has(s.id):
			out.append("%s: stage id '%s' used twice" % [id, s.id])
		stage_ids[s.id] = true
	if not stages.is_empty() and end_on != EndOn.GOAL:
		out.append("%s: staged runs end on GOAL" % id)
	if not DEV_BOTS.has(dev_bot):
		out.append("%s: unknown dev_bot '%s'" % [id, dev_bot])
	for i in range(1, split_xs.size()):
		if split_xs[i] <= split_xs[i - 1]:
			out.append("%s: split_xs must be ascending" % id)
			break
	for f in on_finish_flags:
		if f == "":
			out.append("%s: empty on_finish_flags entry" % id)
	return out


func _validate_medals() -> PackedStringArray:
	var out := PackedStringArray()
	if score_kind == ScoreKind.RANK:
		if rank_table == null:
			out.append("%s: RANK needs a rank_table" % id)
		else:
			for e in rank_table.validate():
				out.append("%s: %s" % [id, e])
		return out
	if medal_thresholds.size() != 4:
		out.append("%s: medal_thresholds needs 4 values (Bronze, Silver, Gold, Redline)" % id)
		return out
	for i in range(1, 4):
		var a := medal_thresholds[i - 1]
		var b := medal_thresholds[i]
		var ordered := b < a if score_kind == ScoreKind.TIME else b > a
		if not ordered:
			out.append("%s: medal thresholds must be strictly %s" % [id, "descending (frames)" if score_kind == ScoreKind.TIME else "ascending (points)"])
			break
	if medal_thresholds[0] <= 0:
		out.append("%s: medal thresholds must be > 0" % id)
	return out


## Resource content protocol (M8): unlock/reveal/requires read flags;
## on_finish_flags are produced (null_depth_reached, D-154).
func content_flags() -> Dictionary:
	var conds: Array = []
	for c in [unlock_when, reveal_when] + Array(requires):
		if String(c) != "":
			conds.append(String(c))
	return {"produces": Array(on_finish_flags), "conditions": conds}
