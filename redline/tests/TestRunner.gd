extends Node
## Headless test entry point. Run from the project folder:
##   godot --headless --fixed-fps 60 res://tests/TestRunner.tscn
## --fixed-fps makes each frame exactly one 1/60s physics tick, so movement
## tests are deterministic and run faster than real time.
## Exit code 0 = all passed, 1 = failures (skipped tests never fail a run).
## Run a subset: append `-- --filter=<substring>` (matches file::method).

const TEST_DIR := "res://tests/unit"


func _ready() -> void:
	# Deferred so autoloads and this scene finish entering the tree first.
	_run.call_deferred()


func _run() -> void:
	var total := 0
	var failed := 0
	var skipped := 0
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.trim_prefix("--filter=")
	# A fresh CI machine has no settings.cfg: no test may write the real
	# settings file through the title's first-run path (M9).
	Settings.first_run = false
	# A developer's saved language (or --locale) never reaches a test (M9 D5).
	reset_locale()
	var files := DirAccess.get_files_at(TEST_DIR)
	files.sort()
	for file in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		var script := load("%s/%s" % [TEST_DIR, file]) as GDScript
		if script == null or not script.can_instantiate():
			# A broken test file must fail loudly, not hang the run.
			total += 1
			failed += 1
			print("FAIL %s (script failed to load/parse)" % file)
			continue
		var suite: RedlineTestCase = script.new()
		add_child(suite)
		for method in suite.get_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			if filter != "" and not ("%s::%s" % [file.get_basename(), method_name]).contains(filter):
				continue
			total += 1
			var result: Dictionary = await run_one(suite, "%s::%s" % [file.get_basename(), method_name], method_name)
			if result["status"] == "FAIL":
				failed += 1
			elif result["status"] == "SKIP":
				skipped += 1
			print(result_line(result))
		for f in suite.failures:
			printerr("  - " + f)
		suite.queue_free()
	print("\n" + summary(total, failed, skipped))
	get_tree().quit(1 if failed > 0 else 0)


## Runs one test with its before/after hooks and the global teardown, and
## returns {status: "PASS" | "FAIL" | "SKIP", name, reason}. A test skips by
## calling `set_meta("skip_reason", reason)` on its suite and returning
## (R06.6); a skip counts apart, never as passed or failed. A failure
## recorded before the skip still fails.
static func run_one(suite: RedlineTestCase, test_name: String, method_name: String) -> Dictionary:
	suite._current_test = test_name
	var before := suite.failures.size()
	await suite.before_each()
	await suite.call(method_name)
	await suite.after_each()
	# No scene (sequence, memory) or cinematic mode leaks into the next test.
	CinematicMode.teardown()
	reset_global_state()
	var reason := str(suite.get_meta("skip_reason", ""))
	if suite.has_meta("skip_reason"):
		suite.remove_meta("skip_reason")
	var status := "PASS"
	if suite.failures.size() != before:
		status = "FAIL"
	elif reason != "":
		status = "SKIP"
	return {"status": status, "name": test_name, "reason": reason}


static func result_line(result: Dictionary) -> String:
	if result["status"] == "SKIP":
		return "SKIP %s (%s)" % [result["name"], result["reason"]]
	return "%s %s" % [result["status"], result["name"]]


static func summary(total: int, failed: int, skipped: int) -> String:
	return "%d tests, %d failed, %d skipped" % [total, failed, skipped]


## M9 global state no test may leak into the next: the platform store and its
## headless opt-in, a forced run or demo, the demo bypass, the sandbox leave
## guard, the tour store sandbox and the display language.
static func reset_global_state() -> void:
	Platform.reset_after_tests()
	Challenges.reset_for_tests()
	BuildInfo.set_force_demo(-1)
	BuildInfo.force_allowed.clear()
	# BuildInfo.force_web lands with T05 (R05.8): reset it once it exists.
	var build_info: GDScript = BuildInfo
	if build_info.get("force_web") != null:
		build_info.set("force_web", -1)
	DemoGate.dev_bypass = false
	Game.suppress_leave_capture = false
	AtomicJson.remove_tree("user://tour_sandbox")
	reset_locale()


## Back to the source language with nothing registered or flagged (D5).
static func reset_locale() -> void:
	Loc.flag_missing = false
	Loc.set_locale(Loc.SOURCE_LOCALE)
