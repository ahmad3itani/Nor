extends RedlineTestCase
## Runs last (TestRunner sorts the files; D6 §8.3, T14): the suite left no
## stray file in user://. Every M9 store (platform unlocks and stats, records
## and ghosts, NG+ archives, demo dirs, playtest sessions) must write to a
## test temp dir during tests and remove it, never to the developer's real
## user dir.
##
## Only files written while this test run was going are judged (the user dir
## also holds the developer's own saves and settings from real play, and
## capture-tour files). Known temp settings files are removed first (R14.8);
## logs and the shader cache are the engine's.
##
## A file left inside a suite's own temp folder (user://test_*) is reported,
## not failed: it cannot reach a player's data, and the real risk this test
## guards is a store writing to the developer's real paths. Do not run a
## capture tour at the same time: tours write the real user dir.

## Paths (relative to user://) that may change during a run.
const ALLOWED_PREFIXES: PackedStringArray = ["logs/", "shader_cache/", "vulkan/"]
## Temp settings files other suites point Settings at (their .bak/.tmp go too).
const TEMP_SETTINGS: PackedStringArray = ["user://test_m8_settings.cfg", "user://test_memory_scenes.cfg",
	"user://capture_tour_settings.cfg"]
## Seconds of slack before the process start (file times are whole seconds).
const SLACK := 2.0


## When this process started, in unix seconds.
static func run_started() -> float:
	return Time.get_unix_time_from_system() - Time.get_ticks_msec() / 1000.0 - SLACK


func test_no_stray_user_files() -> void:
	for p in TEMP_SETTINGS:
		Settings.remove_settings_files(p)
	var since := run_started()
	var strays := PackedStringArray()
	var leftovers := PackedStringArray()
	for rel in _files("user://", ""):
		if _allowed(rel):
			continue
		if float(FileAccess.get_modified_time("user://" + rel)) >= since:
			if rel.begins_with("test_"):
				leftovers.append(rel)
			else:
				strays.append(rel)
	if not leftovers.is_empty():
		print("  user dir: temp files a suite did not remove: %s" % [leftovers])
	check(strays.is_empty(), "files written to the real user:// paths by the test run (use a temp dir and remove it): %s" % [strays])


## T01 R01.28: the capture-tour sandbox is wiped by the tours and by the test
## teardown, so it is never left behind.
func test_tour_sandbox_gone() -> void:
	check(not DirAccess.dir_exists_absolute("user://tour_sandbox"), "user://tour_sandbox is gone")
	check(not DirAccess.dir_exists_absolute(TourSandbox.ROOT), "%s is gone" % TourSandbox.ROOT)


static func _allowed(rel: String) -> bool:
	for p in ALLOWED_PREFIXES:
		if rel.begins_with(p):
			return true
	return false


## Every file under `dir`, relative to user://.
static func _files(dir: String, rel: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		out.append(rel + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_files(dir.path_join(d), rel + d + "/"))
	return out
