class_name PlatformConfig
extends Resource
## Platform-services tuning (M9 D1, bible §29). One file:
## data/platform/platform_config.tres. Numbers here are provisional until the
## §44 playtest (D-140); code never hard-codes them.

## PlatformBackends factory key. Unknown ids fall back to the local backend
## with a warning (a missing adapter never blocks play, §37.7).
@export var backend_id: StringName = &"local"
## The achievements/lifetime-stats file inside Platform.store_dir.
@export var store_file: String = "achievements.json"
## LocalStore format version (independent of the profile save schema).
@export var store_version: int = 1
## Seconds one achievement toast stays up (T07's AchievementToast).
@export var toast_seconds: float = 3.5
## This many unlocks queued at once collapse into one toast (D-143).
@export var toast_collapse_at: int = 4
## A power-shutter pass with this much margin or less is a close call.
@export var close_call_margin_s: float = 0.25
## Unsaved lifetime stats are written at least this often (plus on every
## profile save, unlock and quit).
@export var flush_interval_s: float = 60.0
## AchievementsMenu rows per page (T07).
@export var menu_rows_per_page: int = 6
## No grind (D-146): a COUNTER achievement target above this is an error.
@export var grind_cap: float = 25.0


func validate() -> PackedStringArray:
	var e := PackedStringArray()
	if backend_id == &"":
		e.append("backend_id is empty")
	if store_file.strip_edges() == "" or store_file.contains("/"):
		e.append("store_file must be a bare file name")
	if store_version < 1:
		e.append("store_version must be >= 1")
	if toast_seconds <= 0.0 or toast_collapse_at < 2:
		e.append("toast_seconds must be > 0 and toast_collapse_at >= 2")
	if close_call_margin_s <= 0.0 or flush_interval_s <= 0.0:
		e.append("close_call_margin_s and flush_interval_s must be > 0")
	if menu_rows_per_page < 1 or grind_cap < 1.0:
		e.append("menu_rows_per_page and grind_cap must be >= 1")
	return e
