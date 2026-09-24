extends Node
## Headless test entry point. Run from the project folder:
##   godot --headless --fixed-fps 60 res://tests/TestRunner.tscn
## --fixed-fps makes each frame exactly one 1/60s physics tick, so movement
## tests are deterministic and run faster than real time.
## Exit code 0 = all passed, 1 = failures.
## Run a subset: append `-- --filter=<substring>` (matches file::method).

const TEST_DIR := "res://tests/unit"


func _ready() -> void:
	# Deferred so autoloads and this scene finish entering the tree first.
	_run.call_deferred()


func _run() -> void:
	var total := 0
	var failed := 0
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.trim_prefix("--filter=")
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
			suite._current_test = "%s::%s" % [file.get_basename(), method_name]
			var before := suite.failures.size()
			await suite.before_each()
			await suite.call(method_name)
			await suite.after_each()
			var ok := suite.failures.size() == before
			if not ok:
				failed += 1
			print("%s %s" % ["PASS" if ok else "FAIL", suite._current_test])
		for f in suite.failures:
			printerr("  - " + f)
		suite.queue_free()
	print("\n%d tests, %d failed" % [total, failed])
	get_tree().quit(1 if failed > 0 else 0)
