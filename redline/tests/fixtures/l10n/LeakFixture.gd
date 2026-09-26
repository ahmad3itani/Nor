extends RedlineTestCase
## Runner self-test fixture: a test that leaves global state set. The
## TestRunner teardown must put all of it back before the next test.


func test_leaks_global_state() -> void:
	Challenges.force_active = true
	BuildInfo.set_force_demo(1)
	BuildInfo.force_allowed["res://nowhere.tscn"] = false
	Platform.allow_headless = true
	DemoGate.dev_bypass = true
	Loc.set_locale("en_XA")
	Loc.flag_missing = true
