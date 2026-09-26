extends Node
## Platform services (M9 D1, bible §29): achievements, stats, rich presence,
## leaderboard mirroring and cloud-save hooks behind one PlatformBackend.
## Only the local backend ships; a Steam adapter is a documented slot with no
## code (§37.7: gameplay never depends on a platform API, and no networking).
## Gameplay never calls Platform: it listens to EventBus (the Playtest pattern).
##
## stub: filled by T02. Every body here is inert with its final signature, so
## the shared-file hooks (SaveManager, CaptureTour, TestRunner, DevConsole)
## land once in T01. No class_name: an autoload's script must not declare one
## (4.3: 'Class "Platform" hides an autoload singleton').

## Headless runs (tests, probes) never write unless a test opts in.
var allow_headless := false
## Root of every platform file (achievements.json, records.json, ghosts/).
## Tests and CaptureTour redirect it with reset_for_tests().
var store_dir: String = "user://platform"
## Dev: let a dev-tainted profile earn (D-145), for testing the toasts.
var dev_allow_tainted := false


## Whether platform files may be written (final semantics: headless only
## with allow_headless). The stub never writes either way.
func active() -> bool:
	return allow_headless or DisplayServer.get_name() != "headless"


func is_unlocked(_id: String) -> bool:
	return false


func unlocked_ids() -> PackedStringArray:
	return PackedStringArray()


## A stat's value (lifetime = the machine-wide total, else this profile's).
func stat(_id: StringName, _lifetime: bool = true) -> float:
	return 0.0


## False for dev-tainted profiles, theatre replays and sandboxes (T02).
func earning_allowed() -> bool:
	return false


## SaveManager calls this after every successful profile write (cloud hook).
func notify_file_written(_path: String) -> void:
	pass


func flush() -> void:
	pass


## Mirrors a local personal best to the backend's leaderboard (local only).
func submit_score(_board: String, _value: int, _meta: Dictionary) -> void:
	pass


func presence_text() -> String:
	return ""


func reset_for_tests(dir: String) -> void:
	store_dir = dir
	allow_headless = true


func reset_after_tests() -> void:
	store_dir = "user://platform"
	allow_headless = false
	dev_allow_tainted = false


func clear_cache() -> void:
	pass
