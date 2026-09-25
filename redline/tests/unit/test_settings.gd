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


const M8_PATH := "user://test_m8_settings_roundtrip.cfg"


## M8 subtitle/scene settings persist and clamp like the others.
func test_subtitle_settings_persist() -> void:
	var snap := use_default_m8_settings()
	Settings.load_settings(M8_PATH)
	Settings.subtitle_size = 2
	Settings.subtitle_background = 0
	Settings.speaker_labels = false
	Settings.subtitle_speed = 1
	Settings.cinematic_skip_hold = false
	Settings.memories_at_anchors = false
	check(Settings.save_settings() == OK, "save failed")
	use_default_m8_settings()
	Settings.load_settings(M8_PATH)
	check(Settings.subtitle_size == 2, "subtitle_size not restored")
	check(Settings.subtitle_background == 0, "subtitle_background not restored")
	check(not Settings.speaker_labels, "speaker_labels not restored")
	check(Settings.subtitle_speed == 1, "subtitle_speed not restored")
	check(not Settings.cinematic_skip_hold, "cinematic_skip_hold not restored")
	check(not Settings.memories_at_anchors, "memories_at_anchors not restored")
	var cfg := ConfigFile.new()
	check(cfg.load(M8_PATH) == OK, "saved file unreadable")
	for section in cfg.get_sections():
		check(not cfg.has_section_key(section, "text_auto_advance"), "text_auto_advance must not be written (cut, D-110)")
	Settings.subtitle_size = 7
	check(Settings.subtitle_size == 2, "subtitle_size not clamped high")
	Settings.subtitle_size = -3
	check(Settings.subtitle_size == 0, "subtitle_size not clamped low")
	Settings.subtitle_background = 9
	check(Settings.subtitle_background == 2, "subtitle_background not clamped")
	Settings.subtitle_speed = -1
	check(Settings.subtitle_speed == 0, "subtitle_speed not clamped low")
	Settings.subtitle_speed = 5
	check(Settings.subtitle_speed == 2, "subtitle_speed not clamped high")
	DirAccess.remove_absolute(M8_PATH)
	Settings.load_settings(Settings.SETTINGS_PATH)
	restore_m8_settings(snap)


## --subtitle-size=N is a session override for captures and is never saved.
func test_subtitle_size_arg() -> void:
	check(Settings.parse_subtitle_size_arg(PackedStringArray(["--subtitle-size=2"])) == 2, "arg 2 not parsed")
	check(Settings.parse_subtitle_size_arg(PackedStringArray(["--tour=ui"])) == -1, "absent arg must be -1")
	check(Settings.parse_subtitle_size_arg(PackedStringArray()) == -1, "empty args must be -1")
	check(Settings.parse_subtitle_size_arg(PackedStringArray(["--subtitle-size=9"])) == 2, "high arg not clamped")
	check(Settings.parse_subtitle_size_arg(PackedStringArray(["--subtitle-size=-4"])) == 0, "low arg not clamped")
	var snap := use_default_m8_settings()
	Settings.load_settings(M8_PATH)
	Settings.subtitle_size = 0
	Settings._subtitle_size_override = 2
	check(Settings.effective_subtitle_size() == 2, "override not effective")
	check(Settings.save_settings() == OK, "save failed")
	var cfg := ConfigFile.new()
	cfg.load(M8_PATH)
	check(int(cfg.get_value("accessibility", "subtitle_size", -1)) == 0, "the override must never be persisted")
	Settings._subtitle_size_override = -1
	check(Settings.effective_subtitle_size() == 0, "stored size not used without override")
	DirAccess.remove_absolute(M8_PATH)
	Settings.load_settings(Settings.SETTINGS_PATH)
	restore_m8_settings(snap)
