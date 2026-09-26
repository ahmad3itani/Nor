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
	Settings.remove_settings_files(PATH)
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
	# M9 (R03.12): text auto-advance is back as an [accessibility] key (D-110 closed).
	check(cfg.has_section_key("accessibility", "text_auto_advance"), "text_auto_advance is written under [accessibility]")
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
	Settings.remove_settings_files(M8_PATH)
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
	check(SubtitleStyle.font_size() == 11, "SubtitleStyle must read the override")
	check(Settings.save_settings() == OK, "save failed")
	var cfg := ConfigFile.new()
	cfg.load(M8_PATH)
	check(int(cfg.get_value("accessibility", "subtitle_size", -1)) == 0, "the override must never be persisted")
	Settings._subtitle_size_override = -1
	check(Settings.effective_subtitle_size() == 0, "stored size not used without override")
	Settings.remove_settings_files(M8_PATH)
	Settings.load_settings(Settings.SETTINGS_PATH)
	restore_m8_settings(snap)


# --- M9 (T03): catalog-driven store ------------------------------------------

const TMP := "user://test_settings_m9.cfg"
const V1_FIXTURE := "res://tests/fixtures/settings_v1_m8.cfg"
const SettingsRules := preload("res://devtools/content/rules/SettingsRules.gd")

var _snap: Dictionary = {}


func before_each() -> void:
	_snap = snapshot_settings()


func after_each() -> void:
	Settings.remove_settings_files(TMP)
	restore_settings(_snap)


func _cat() -> SettingsCatalog:
	return Settings.settings_catalog()


## A value different from the row's current one (for round trips).
func _other_value(d: SettingDef, current: Variant) -> Variant:
	match d.kind:
		SettingDef.Kind.TOGGLE:
			return not bool(current)
		SettingDef.Kind.CHOICE:
			return (int(current) + 1) % d.choices.size()
		SettingDef.Kind.STEPS:
			return d.steps[(d.step_index(float(current)) + 1) % d.steps.size()]
	return "t03_probe" if current is String else current


func test_catalog_matches_properties() -> void:
	var errs := SettingsRules.catalog_errors(_cat(), Settings)
	check(errs.is_empty(), "SE-1 clean: %s" % "; ".join(errs))
	var keys := {}
	for d in _cat().stored_defs():
		keys[String(d.key)] = true
	for p in Settings.setting_properties():
		if p in ["bindings", "locale"]:
			check(not keys.has(p), "%s stays hand-written" % p)
		else:
			check(keys.has(p), "Settings.%s has a catalog row" % p)
	for k in ["ui_volume", "high_contrast", "achievement_toasts", "speedrun_timer", "challenge_ghost", "fast_reset_hold",
			"text_auto_advance", "rebind_wait", "pad_glyphs"]:
		check(keys.has(k), "contract key %s is a row" % k)


func test_every_def_roundtrips() -> void:
	Settings.apply_defaults()
	Settings.load_settings(TMP)
	var want := {}
	for d in _cat().stored_defs():
		var v: Variant = _other_value(d, Settings.get(d.key))
		Settings.set(d.key, v)
		want[String(d.key)] = Settings.get(d.key)
	Settings.bindings = {"jump": {"key": ["k74"]}}
	Settings.locale = "en_XA"
	check(Settings.save_settings() == OK, "save failed")
	Settings.apply_defaults()
	Settings.load_settings(TMP)
	for k: String in want:
		var got: Variant = Settings.get(k)
		var same: bool = is_equal_approx(float(got), float(want[k])) if want[k] is float else got == want[k]
		check(same, "%s round trip: want %s, got %s" % [k, want[k], got])
	check(Settings.bindings == {"jump": {"key": ["k74"]}}, "bindings round trip (%s)" % Settings.bindings)
	check(Settings.locale == "en_XA", "locale round trip")
	var cfg := ConfigFile.new()
	check(cfg.load(TMP) == OK and int(cfg.get_value("meta", "version", 0)) == Settings.VERSION, "[meta] version written")
	check(cfg.get_value("playtest", "recording", null) != null and cfg.get_value("playtest", "variant", null) != null,
		"the M4 playtest keys keep their cfg names")


func test_every_def_clamps() -> void:
	var errs := SettingsRules.clamp_errors(_cat(), Settings)
	check(errs.is_empty(), "SE-2 clean: %s" % "; ".join(errs))
	Settings.damage_assist = 9
	check(Settings.damage_assist == 3, "damage assist clamps high")
	Settings.ui_scale = -2
	check(Settings.ui_scale == 0, "ui scale clamps low")
	Settings.ui_volume = 4.0
	check(Settings.ui_volume == 1.0, "ui volume clamps")
	Settings.challenge_ghost = 7
	check(Settings.challenge_ghost == 3, "ghost choice clamps")


func test_v1_file_loads() -> void:
	var src := FileAccess.open(V1_FIXTURE, FileAccess.READ)
	check(src != null, "fixture readable")
	if src == null:
		return
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(src.get_as_text())
	f.close()
	Settings.apply_defaults()
	Settings.load_settings(TMP)
	check_near(Settings.screen_shake_scale, 0.5, 0.0001, "shake")
	check_near(Settings.hitstop_scale, 0.5, 0.0001, "hitstop")
	check(Settings.flash_reduction and not Settings.currency_loss and Settings.show_debug_overlay, "toggles")
	check_near(Settings.vibration_strength, 0.7, 0.0001, "vibration")
	check_near(Settings.master_volume, 0.9, 0.0001, "master")
	check_near(Settings.sfx_volume, 0.5, 0.0001, "sfx")
	check_near(Settings.music_volume, 0.3, 0.0001, "music")
	check(Settings.reactor_mode == 1, "reactor mode")
	check(not Settings.playtest_recording and Settings.playtest_variant == "baseline", "playtest keys")
	check(Settings.subtitle_size == 2 and Settings.subtitle_background == 0 and not Settings.speaker_labels
		and Settings.subtitle_speed == 1 and not Settings.cinematic_skip_hold and not Settings.memories_at_anchors, "M8 subtitle keys")
	check(Settings.ui_scale == 0 and Settings.bindings.is_empty() and Settings.locale == "" and Settings.text_auto_advance == 0,
		"new keys take their defaults")
	check(Settings.save_settings() == OK, "save")
	var cfg := ConfigFile.new()
	cfg.load(TMP)
	check(int(cfg.get_value("meta", "version", 0)) == 2, "version becomes 2 on save")
	check(is_equal_approx(float(cfg.get_value("accessibility", "screen_shake_scale", 0.0)), 0.5), "old values survive the save")
	check(str(cfg.get_value("playtest", "variant", "")) == "baseline", "variant survives")


func test_unknown_keys_ignored() -> void:
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("[accessibility]\nbogus_key=5\nscreen_shake_scale=\"loud\"\nui_scale=2\n\n[nonsense]\nx=1\n")
	f.close()
	Settings.apply_defaults()
	Settings.load_settings(TMP)
	check(Settings.ui_scale == 2, "known key read")
	check_near(Settings.screen_shake_scale, 1.0, 0.0001, "a wrongly typed value keeps the current one")
	Settings.save_settings()
	var cfg := ConfigFile.new()
	cfg.load(TMP)
	check(not cfg.has_section_key("accessibility", "bogus_key") and not cfg.has_section("nonsense"), "unknown keys are not written back")


func test_reset_page_only_touches_page() -> void:
	Settings.apply_defaults()
	Settings.screen_shake_scale = 0.2
	Settings.high_contrast = true
	Settings.master_volume = 0.3
	Settings.damage_assist = 2
	var visual := _cat().page(&"visual")
	Settings.reset_keys(_cat().page_keys(visual))
	check_near(Settings.screen_shake_scale, 1.0, 0.0001, "visual reset: shake")
	check(not Settings.high_contrast, "visual reset: contrast")
	check_near(Settings.master_volume, 0.3, 0.0001, "audio untouched")
	check(Settings.damage_assist == 2, "assists untouched")


func test_reset_all_keeps_locale_and_bindings() -> void:
	Settings.apply_defaults()
	Settings.locale = "en_XA"
	Settings.bindings = {"jump": {"key": ["k74"]}}
	Settings.pad_glyphs = 2
	Settings.ui_scale = 2
	Settings.damage_assist = 2
	Settings.subtitle_size = 1
	Settings.reset_keys(Settings.reset_all_keys())
	check(Settings.ui_scale == 0 and Settings.damage_assist == 0 and Settings.subtitle_size == 0, "reset all resets the pages")
	check(Settings.locale == "en_XA", "language is never reset")
	check(Settings.bindings == {"jump": {"key": ["k74"]}}, "controls are kept")
	check(Settings.pad_glyphs == 2, "the Controls page is kept")
	check(not Settings.reset_all_keys().has(&"locale") and not Settings.reset_all_keys().has(&"bindings"), "keys list")


func test_active_assists() -> void:
	Settings.apply_defaults()
	check(Settings.active_assists().is_empty(), "none by default")
	Settings.reactor_mode = 1
	check(Settings.active_assists() == PackedStringArray(["reactor_assist"]), "Story / Assist core")
	Settings.reactor_mode = 2
	check(Settings.active_assists().is_empty(), "Redline Challenge core is not an assist")
	Settings.apply_defaults()
	Settings.damage_assist = 1
	check(Settings.active_assists() == PackedStringArray(["damage_assist"]), "damage assist")
	Settings.apply_defaults()
	Settings.aim_assist = 2
	check(Settings.active_assists() == PackedStringArray(["aim_assist"]), "aim assist")
	Settings.apply_defaults()
	Settings.burnout_hurts = false
	check(Settings.active_assists() == PackedStringArray(["no_burnout"]), "burnout off")
	# Comfort options never tag a run (D-149).
	Settings.apply_defaults()
	Settings.screen_shake_scale = 0.0
	Settings.hitstop_scale = 0.0
	Settings.flash_reduction = true
	Settings.high_contrast = true
	Settings.colorblind_mode = 2
	Settings.background_dim = 2
	Settings.ui_scale = 2
	Settings.subtitle_size = 2
	Settings.subtitle_speed = 2
	Settings.jump_hold_mode = 1
	Settings.map_hints = 2
	Settings.generous_checkpoints = true
	Settings.currency_loss = false
	Settings.text_auto_advance = 1
	check(Settings.active_assists().is_empty(), "comfort options are never assists (%s)" % Settings.active_assists())


func test_first_run_only_on_real_path() -> void:
	Settings.first_run = false
	Settings.remove_settings_files(TMP)
	Settings.load_settings(TMP)
	check(not Settings.first_run, "a missing temp file never raises first_run")
	check(Settings._path == TMP, "the temp path is the save target")


## R03.3: a settings.cfg that no longer parses falls back to its .bak.
func test_settings_bak_recovery() -> void:
	Settings.apply_defaults()
	Settings.load_settings(TMP)
	Settings.bindings = {"heal": {"key": ["k89"]}}
	Settings.ui_scale = 1
	check(Settings.save_settings() == OK, "first save")
	check(Settings.save_settings() == OK, "second save rotates a .bak")
	check(FileAccess.file_exists(TMP + ".bak"), ".bak exists")
	check(not FileAccess.file_exists(TMP + ".tmp"), "no .tmp left behind")
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("[[[ this is not a config file")
	f.close()
	Settings.apply_defaults()
	Settings.load_settings(TMP)
	check(Settings.bindings == {"heal": {"key": ["k89"]}}, "bindings recovered from the .bak (%s)" % Settings.bindings)
	check(Settings.ui_scale == 1, "values recovered from the .bak")
	Settings.remove_settings_files(TMP)
	check(not FileAccess.file_exists(TMP) and not FileAccess.file_exists(TMP + ".bak"), "remove_settings_files cleans both")


## R03.2: the locale catalogs load before the locale is applied.
func test_load_catalogs_called_on_ready() -> void:
	var trace := Settings._ready_trace
	var b := trace.find("bindings")
	var l := trace.find("load_catalogs")
	var s := trace.find("set_locale")
	check(b >= 0 and l > b and s > l, "ready order bindings < load_catalogs < set_locale (%s)" % str(trace))
	check(Settings.access_config != null and Settings.catalog != null, "config and catalog loaded in _ready")


func test_text_auto_advance_default_off_and_roundtrips() -> void:
	Settings.apply_defaults()
	check(Settings.text_auto_advance == 0, "default Off")
	var d := _cat().def(&"text_auto_advance")
	check(d != null and d.section == "accessibility" and d.choices == PackedStringArray(["Off", "On"]), "row in [accessibility], Off/On")
	check(d != null and d.description == "Lines move on by themselves after a reading pause. Choices always wait.", "description")
	Settings.load_settings(TMP)
	Settings.text_auto_advance = 1
	Settings.save_settings()
	Settings.text_auto_advance = 0
	Settings.load_settings(TMP)
	check(Settings.text_auto_advance == 1, "round trip")
	var cfg: AccessibilityConfig = Settings.access_config
	check_near(cfg.auto_advance_seconds(10), 1.2 + 10 * 0.045, 0.0001, "reading time = base + chars x per_char")
	check(cfg.jump_latch_max_frames == 40, "jump latch cap is data (R03.13)")


func test_session_fields_excluded_from_snapshot() -> void:
	var snap := Settings.snapshot()
	for k in ["_path", "first_run", "_subtitle_size_override", "_locale_override", "access_config", "catalog", "_ready_trace"]:
		check(not snap.has(k), "snapshot skips %s" % k)
	for k in ["bindings", "locale", "text_auto_advance", "rebind_wait", "ui_volume", "playtest_variant"]:
		check(snap.has(k), "snapshot has %s" % k)
	check(Settings.defaults().size() == snap.size(), "defaults() covers the same keys")
