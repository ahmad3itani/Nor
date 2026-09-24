extends RedlineTestCase

const PATH := "user://test_settings.cfg"


func test_values_clamp() -> void:
	var old := Settings.screen_shake_scale
	Settings.screen_shake_scale = 5.0
	check(Settings.screen_shake_scale <= 1.5, "shake not clamped")
	Settings.screen_shake_scale = -1.0
	check(Settings.screen_shake_scale == 0.0, "shake not clamped at 0")
	Settings.screen_shake_scale = old


func test_persist_roundtrip() -> void:
	var old := Settings.screen_shake_scale
	Settings.load_settings(PATH)
	Settings.screen_shake_scale = 0.3
	check(Settings.save_settings() == OK, "save failed")
	Settings.screen_shake_scale = 1.0
	Settings.load_settings(PATH)
	check_near(Settings.screen_shake_scale, 0.3, 0.0001, "shake not restored")
	DirAccess.remove_absolute(PATH)
	Settings.load_settings(Settings.SETTINGS_PATH)
	Settings.screen_shake_scale = old
