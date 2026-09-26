extends RedlineTestCase
## Runner self-test fixture (R06.6): run through TestRunner.run_one by
## test_l10n_runtime, never by the runner itself (it is not in tests/unit).


func test_skips() -> void:
	set_meta("skip_reason", "fixture skip")


func test_fails_then_skips() -> void:
	check(false, "fixture failure")
	set_meta("skip_reason", "too late")


func test_passes() -> void:
	check(true, "fixture pass")
