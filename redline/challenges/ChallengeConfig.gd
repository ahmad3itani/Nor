class_name ChallengeConfig
extends Resource
## Challenge runtime tuning and shared text (R04.14, R04.30):
## data/challenges/challenge_config.tres. RunClock/Challenges/RecordStore read
## it; no literal thresholds in code.

const PATH := "res://data/challenges/challenge_config.tres"
const LOC_FIELDS := {"group_titles": 24, "ghost_mode_names": 16}

@export_group("Fast reset")
## A reset under this run time is a tap; past it, a hold (a long run is never
## lost to a stray press, D2 §3.5).
@export var fast_reset_tap_window_s: float = 60.0
@export var fast_reset_hold_s: float = 0.35
## The first-use chip ("{reset}: restart") on attempt 1 of a session.
@export var reset_chip_s: float = 3.0

@export_group("Results")
## Seconds between a run's end and the result card (the finish reads first).
@export var finish_card_delay_s: float = 1.0
## Entries kept per local board (all profiles share one board).
@export var pb_board_size: int = 10
## How long a split delta stays on the run HUD.
@export var split_toast_s: float = 2.0

@export_group("Medals (T08 reads)")
## Redline = rig-ghost time × bot_margin (the bot is frame-perfect, D-150).
@export var bot_margin: float = 1.1
## CH-15 warns when Silver < Redline × silver_floor_mult + silver_floor_add_s.
@export var silver_floor_mult: float = 1.5
@export var silver_floor_add_s: float = 3.0

@export_group("Text")
## One title per ChallengeData.Group, in enum order (NULL is the Deep Rig:
## 'null' stays an internal id, R10.6).
@export var group_titles: PackedStringArray = ["Deep Rig", "Boss Rematch", "Time Trial", "Nerve", "Pulse Pit"]
## Settings.challenge_ghost 0..3 (the dev ghost is the "Rig ghost" to players).
@export var ghost_mode_names: PackedStringArray = ["Off", "Personal best", "Rig ghost", "Both"]
## Seconds the one-time "new at the training rig" HUD hint stays (R04.20).
@export var suggest_new_group_hint_s: float = 3.0

static var _shared: ChallengeConfig = null


static func shared() -> ChallengeConfig:
	if _shared == null:
		_shared = load(PATH) as ChallengeConfig
		if _shared == null:
			_shared = ChallengeConfig.new()
	return _shared


static func clear_cache() -> void:
	_shared = null


func validate() -> PackedStringArray:
	var out := PackedStringArray()
	if fast_reset_tap_window_s < 0.0 or fast_reset_hold_s <= 0.0 or fast_reset_hold_s > 2.0:
		out.append("fast reset: tap window >= 0 and 0 < hold <= 2 s")
	if finish_card_delay_s < 0.0 or finish_card_delay_s > 5.0:
		out.append("finish_card_delay_s must be 0..5")
	if pb_board_size < 1 or pb_board_size > 50:
		out.append("pb_board_size must be 1..50")
	if bot_margin < 1.0:
		out.append("bot_margin must be >= 1.0 (a medal above the bot's own time)")
	if silver_floor_mult < 1.0 or silver_floor_add_s < 0.0:
		out.append("silver floor: mult >= 1 and add >= 0")
	if group_titles.size() != ChallengeData.Group.size():
		out.append("group_titles needs one title per group (%d)" % ChallengeData.Group.size())
	if ghost_mode_names.size() != 4:
		out.append("ghost_mode_names needs 4 names (Off, PB, rig, both)")
	if suggest_new_group_hint_s <= 0.0 or split_toast_s <= 0.0 or reset_chip_s <= 0.0:
		out.append("hint, split and chip durations must be > 0")
	return out
