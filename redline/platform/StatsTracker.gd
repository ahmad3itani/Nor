class_name StatsTracker
extends Node
## Stat bookkeeping and feat detectors (M9 D1 §4.2). Child of the Platform
## autoload. Listens to EventBus only: gameplay never calls in (the Playtest
## pattern), so removing this node changes nothing about play.
##
## Where stats count (D-145):
## - campaign stats count only while Platform.earning_allowed() and the current
##   room is a world room (labs respawn dummies: a lab is not the game);
## - during a challenge run nothing counts except the feat whitelist below
##   (R02.3), applied to the LIFETIME store on a FINISHED result, and the
##   challenge_silver_medals counter. The sandbox profile is never counted.
## Profile values live in GameState.stats (per save), lifetime values in the
## machine-wide LocalStore.

## Emitted after any stat changed (AchievementTracker re-evaluates).
signal changed

## Profile values computed from GameState instead of stored (StatDef DERIVED
## rows must be listed here, PlatformRules PL-12). play_time and deaths are
## derived per profile and counted for the lifetime.
const DERIVED_IDS: Array[StringName] = [&"play_time", &"deaths", &"memory_details_found", &"anchors_rested",
	&"secrets_found"]

## ChallengeData.Outcome.FINISHED (T04); RankLadder tier 2 = Silver.
const OUTCOME_FINISHED := 0
const SILVER_MEDAL := 2
## Challenge feats that count toward lifetime stats (R02.3, amends D-145), so a
## one-shot mastery achievement never needs a replay of Act I.
## Finishing a boss no-hit rematch IS the feat.
const FEAT_NOHIT_RUNS := {"br_collector_nohit": &"boss_nohit_collector_drone",
	"br_krail_nohit": &"boss_nohit_warden_krail"}
## A clamp stagger on Krail during these rematches.
const FEAT_CLAMP_RUNS: PackedStringArray = ["br_krail", "br_krail_nohit"]
## The Rainline trial with zero catches.
const FEAT_CHASE_RUN := "tt_rainline"
## The Pulse Pit style run feeds the best style rank.
const FEAT_STYLE_RUN := "pit_style"

var catalog: StatCatalog
## boss_id -> {"t0": fight clock at start, "hit": bool}
var _boss_fight: Dictionary = {}
## Unpaused physics seconds (boss times).
var _fight_clock: float = 0.0
## The live challenge attempt's feats: {id, clamp, catches, style}; {} when
## no run is live.
var _run: Dictionary = {}


func _ready() -> void:
	if catalog == null:
		catalog = StatCatalog.shipped()
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.perfect_dodge.connect(func(_a: Node2D) -> void: _count(&"perfect_dodges"))
	EventBus.style_changed.connect(_on_style_changed)
	EventBus.boss_started.connect(func(b: Node2D, _t: String) -> void: begin_fight(BossArena.id_of(b)))
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.player_died.connect(_on_player_died)
	EventBus.room_leaving.connect(func(_r: Node) -> void: _boss_fight.clear())
	EventBus.chase_caught.connect(_on_chase_caught)
	EventBus.chase_completed.connect(_on_chase_completed)
	EventBus.clamp_dropped.connect(_on_clamp_dropped)
	EventBus.shutter_passed.connect(_on_shutter_passed)
	EventBus.flag_changed.connect(_on_flag_changed)
	EventBus.challenge_started.connect(_on_challenge_started)
	EventBus.challenge_reset.connect(func(_id: String, _r: StringName) -> void: _reset_run_feats())
	EventBus.challenge_finished.connect(_on_challenge_finished)
	EventBus.game_state_reset.connect(_on_game_state_reset)


func _process(delta: float) -> void:
	# Lifetime play time follows Game._process (unpaused), in world rooms only.
	if not get_tree().paused and counting():
		_lifetime_set(&"play_time", lifetime_value(&"play_time") + delta)


func _physics_process(delta: float) -> void:
	if not get_tree().paused:
		_fight_clock += delta


# --- Queries ---

## Campaign stats count now: earning allowed and a world room is current.
func counting() -> bool:
	if not Platform.earning_allowed():
		return false
	var r := SceneRouter.current_room
	return is_instance_valid(r) and r is Room and (r as Room).world_room


## This profile's value. During a run the held (real) profile is read, never
## the sandbox.
func profile_value(id: StringName) -> float:
	var s := _profile_state()
	match id:
		&"play_time":
			return s.play_time_sec
		&"deaths":
			return float(s.deaths)
		&"anchors_rested":
			return float(s.anchors_rested.size())
		&"secrets_found":
			return float(SliceStats.secrets_found()) if s == Game.state else 0.0
		&"memory_details_found":
			var n := 0
			for f: String in s.flags:
				if f.begins_with("mem_detail_") and bool(s.flags[f]):
					n += 1
			return float(n)
	return float(s.stats.get(String(id), 0.0))


func lifetime_value(id: StringName) -> float:
	return Platform.store().lifetime_value(id)


# --- Updates (campaign: profile + lifetime) ---

## COUNTER: adds to the profile (unless derived) and the lifetime value.
func add(id: StringName, amount: float = 1.0) -> void:
	var def := catalog.stat(id)
	if def == null:
		return
	if def.profile and not DERIVED_IDS.has(id):
		Game.state.stats[String(id)] = float(Game.state.stats.get(String(id), 0.0)) + amount
	if def.lifetime:
		_lifetime_set(id, lifetime_value(id) + amount)
	changed.emit()


## MAX: keeps the highest value.
func record_max(id: StringName, value: float) -> void:
	var def := catalog.stat(id)
	if def == null:
		return
	var any := false
	if def.profile and not DERIVED_IDS.has(id) and value > float(Game.state.stats.get(String(id), 0.0)):
		Game.state.stats[String(id)] = value
		any = true
	if def.lifetime and value > lifetime_value(id):
		_lifetime_set(id, value)
		any = true
	if any:
		changed.emit()


## MIN (times): keeps the lowest value above 0; 0 means "none yet".
func record_min(id: StringName, value: float) -> void:
	var def := catalog.stat(id)
	if def == null or value <= 0.0:
		return
	var any := false
	if def.profile and not DERIVED_IDS.has(id):
		var old := float(Game.state.stats.get(String(id), 0.0))
		if old <= 0.0 or value < old:
			Game.state.stats[String(id)] = value
			any = true
	if def.lifetime:
		var lt := lifetime_value(id)
		if lt <= 0.0 or value < lt:
			_lifetime_set(id, value)
			any = true
	if any:
		changed.emit()


## Starts the no-hit and time detectors for a boss (boss_started).
func begin_fight(boss_id: String) -> void:
	if boss_id != "":
		_boss_fight[boss_id] = {"t0": _fight_clock, "hit": false}


## Forgets open fights and the live run's feats (test teardown).
func reset() -> void:
	_boss_fight.clear()
	_run = {}


# --- Listeners ---

## A load, new game or restore starts clean: no open fight carries into the
## next profile, and a stale run is dropped unless a run is live (the
## sandbox swap itself resets the state mid-run).
func _on_game_state_reset() -> void:
	_boss_fight.clear()
	if not Challenges.active():
		_run = {}


func _count(id: StringName) -> void:
	if counting():
		add(id)


func _on_enemy_killed(enemy: Node2D, hit: HitInfo) -> void:
	if not counting() or hit == null or not is_instance_valid(hit.attacker) or not hit.attacker is Player:
		return
	var data: Variant = enemy.get("data") if is_instance_valid(enemy) else null
	if data is EnemyData and (data as EnemyData).boss:
		return
	add(&"kills")
	if hit.has_tag(&"environmental"):
		add(&"kills_environmental")
	if hit.has_tag(&"aerial"):
		add(&"kills_aerial")


func _on_style_changed(_points: float, rank: int) -> void:
	if not _run.is_empty():
		_run["style"] = maxi(int(_run["style"]), rank)
	if counting():
		record_max(&"best_style_rank", float(rank))


func _on_player_damaged(_amount: int, _health: int) -> void:
	for id: String in _boss_fight:
		_boss_fight[id]["hit"] = true


func _on_player_died() -> void:
	# A death ends every open fight: the retry starts a fresh, clean attempt.
	_boss_fight.clear()
	if counting():
		add(&"deaths")


func _on_boss_defeated(boss_id: String) -> void:
	var fight: Dictionary = _boss_fight.get(boss_id, {})
	_boss_fight.erase(boss_id)
	if not counting():
		return
	add(&"bosses_defeated")
	if fight.is_empty():
		return
	record_min(StringName("boss_time_%s" % boss_id), _fight_clock - float(fight["t0"]))
	if not bool(fight["hit"]):
		add(StringName("boss_nohit_%s" % boss_id))


func _on_chase_caught(_chase_id: String, _checkpoint: int) -> void:
	if not _run.is_empty():
		_run["catches"] = int(_run["catches"]) + 1


func _on_chase_completed(chase_id: String, seconds: float, catches: int, _min_lead: float) -> void:
	if not _run.is_empty():
		_run["catches"] = maxi(int(_run["catches"]), catches)
	if not counting():
		return
	if catches == 0:
		add(&"chase_clean")
	record_min(StringName("chase_best_%s" % chase_id), seconds)


func _on_clamp_dropped(_clamp_id: String, staggered_boss: bool) -> void:
	if not staggered_boss:
		return
	if not _run.is_empty():
		_run["clamp"] = true
	if counting():
		add(&"clamp_boss_staggers")


func _on_shutter_passed(_shutter_id: String, margin_s: float) -> void:
	if counting() and margin_s <= Platform.config.close_call_margin_s:
		add(&"shutter_close_calls")


## The Act I clear time is taken when the flag is SET in play. Game.load_game's
## derivation writes the flag without flag_changed, so a load never counts.
func _on_flag_changed(id: String, value: Variant) -> void:
	if id == "act1_complete" and bool(value) and counting():
		record_min(&"act1_clear_time", Game.state.play_time_sec)


# --- Challenge runs (lifetime only) ---

func _on_challenge_started(challenge_id: String, _attempt: int) -> void:
	_run = {"id": challenge_id}
	_reset_run_feats()


func _reset_run_feats() -> void:
	if _run.is_empty():
		return
	_run["clamp"] = false
	_run["catches"] = 0
	_run["style"] = 0


## Counts even while Challenges.active(): the lifetime store only, never the
## sandbox (R02.3, R02.7).
func _on_challenge_finished(challenge_id: String, outcome: int, _value: int, medal: int, _new_best: bool) -> void:
	var run := _run
	_run = {}
	if outcome != OUTCOME_FINISHED or not Platform.lifetime_allowed():
		return
	if run.get("id", challenge_id) != challenge_id:
		# No start seen: no evidence for the per-run feats.
		run = {"id": challenge_id, "clamp": false, "catches": -1, "style": 0}
	if medal >= SILVER_MEDAL:
		_lifetime_add(&"challenge_silver_medals")
	if FEAT_NOHIT_RUNS.has(challenge_id):
		_lifetime_add(FEAT_NOHIT_RUNS[challenge_id])
	if FEAT_CLAMP_RUNS.has(challenge_id) and bool(run.get("clamp", false)):
		_lifetime_add(&"clamp_boss_staggers")
	if challenge_id == FEAT_CHASE_RUN and run.has("catches") and int(run["catches"]) == 0:
		_lifetime_add(&"chase_clean")
	if challenge_id == FEAT_STYLE_RUN and int(run.get("style", 0)) > lifetime_value(&"best_style_rank"):
		_lifetime_set(&"best_style_rank", float(run["style"]))
	changed.emit()
	# These counters live only in the lifetime store: persist them now rather
	# than on the flush timer.
	Platform.flush()


func _lifetime_add(id: StringName, amount: float = 1.0) -> void:
	var def := catalog.stat(id)
	if def != null and def.lifetime:
		_lifetime_set(id, lifetime_value(id) + amount)


func _lifetime_set(id: StringName, value: float) -> void:
	Platform.store().set_lifetime(id, value)


func _profile_state() -> GameState:
	return Game.held_profile if Game.held_profile != null else Game.state
