class_name NewGamePlus
extends RefCounted
## New Game+ (M9 D3, bible §30): after the Act I close the profile starts
## again with a carry-over and remixed rooms. The cycle lives in the int flag
## ng_cycle (0/absent = first run); the previous profile is archived first
## (SaveManager.archive_profile, "cycle<N>").
##
## stub: filled by T09 (NgPlusConfig data, carry, remix switch).


## Whether this save data may start NG+ (Act I closed).
static func can_begin(_data: Dictionary) -> bool:
	return false


static func cycle() -> int:
	return Game.flag_int("ng_cycle")


## The cycle of raw save data (JSON numbers are floats, hence int()).
static func cycle_of(data: Dictionary) -> int:
	return int((data.get("flags", {}) as Dictionary).get("ng_cycle", 0))


## "" for the first run, "NG+" for cycle 1, "NG+2" onwards (a brand label,
## the same in every locale).
static func cycle_label(n: int) -> String:
	return "" if n <= 0 else ("NG+" if n == 1 else "NG+%d" % n)


## Archives the profile and starts the next cycle. Returns false if refused.
static func begin(_options: Dictionary) -> bool:
	return false


## Whether a seen_seq_* / mem_seen_* flag was seen in an earlier cycle.
static func knows_seen_flag(_f: String) -> bool:
	return false


static func clear_cache() -> void:
	pass
