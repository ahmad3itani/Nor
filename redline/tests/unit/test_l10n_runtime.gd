extends RedlineTestCase
## M9 D5 runtime (T06): Loc lookup, catalog registration (R06.1), locale
## switching, the --locale override, dev locale actions, and the TestRunner
## self-checks (skip support R06.6, global teardown R06.7).

const ZZ_PO := "res://tests/fixtures/l10n/zz.po"
const TMP_CFG := "user://test_l10n_settings.cfg"


func after_each() -> void:
	# Drops the test-only zz catalog; the runner then pins English again.
	Loc.clear_cache()
	DevActions.force_unavailable = false


func _use_zz() -> void:
	Loc.register_catalog("zz", load(ZZ_PO) as Translation)
	check(Loc.set_locale("zz") == "zz", "the zz fixture catalog applies")


func test_source_locale_is_identity() -> void:
	check(Loc.set_locale("en") == "en" and Loc.locale() == "en", "English applies")
	check(Loc.t("Resume") == "Resume", "t is identity in English")
	check(Loc.f("{a}/{b}", {"a": 1, "b": 2}) == "1/2", "f formats named placeholders")
	check(Loc.upper("Warden") == "WARDEN", "upper after translation")
	check(Loc.t("") == "", "empty stays empty")


func test_pseudo_catalog_loads() -> void:
	check(Loc.set_locale("en_XA") == "en_XA", "en_XA applies in a debug build")
	var r := Loc.t("Resume")
	check(r.begins_with("[") and r.ends_with("]") and r != "Resume", "Resume is pseudo: %s" % r)
	check(TranslationServer.get_locale() == "en_XA", "the server follows")
	check(Loc.info().code == "en_XA" and Loc.info().dev_only, "info() is the pseudo row")


func test_missing_falls_back_to_source() -> void:
	Loc.set_locale("en_XA")
	check(Loc.t("Not in any catalog zq") == "Not in any catalog zq", "missing -> source")
	Loc.flag_missing = true
	check(Loc.t("Not in any catalog zq") == "‹Not in any catalog zq›", "flag_missing marks it")
	check(not Loc.t("Resume").begins_with("‹"), "a translated string is not marked")
	Loc.set_locale("en")
	check(Loc.t("Not in any catalog zq") == "Not in any catalog zq", "English never marks")
	check(Loc.set_locale("xx_nowhere") == "en", "an unknown code falls back to English")


func test_context_is_strict() -> void:
	_use_zz()
	check(Loc.t("On", "toggle") == "Zon", "the context entry matches")
	check(Loc.t("On") == "On", "no context -> no match (strict msgctxt)")
	check(Loc.t("Resume") == "Zresume", "plain entry")
	check(Loc.t("Resume", "pause") == "Resume", "a context the catalog lacks -> source")
	check(Loc.t("Back") == "Back", "fuzzy entries are skipped by the loader")


func test_plural_forms() -> void:
	var s := "Recovered {n} Scrap"
	var p := "Recovered {n} Scraps"
	check(Loc.tn(s, p, 1) == "Recovered 1 Scrap" and Loc.tn(s, p, 5) == "Recovered 5 Scraps", "English forms")
	check(Loc.tn("{n} of {total}", "{n} of {total}", 3, {"total": 9}) == "3 of 9", "args plus n")
	_use_zz()
	check(Loc.tn(s, p, 1) == "Z1 one" and Loc.tn(s, p, 5) == "Z5 many", "catalog forms: %s / %s" % [Loc.tn(s, p, 1), Loc.tn(s, p, 5)])
	Loc.set_locale("en_XA")
	check(Loc.tn(s, p, 5) == "Recovered 5 Scraps", "no entry -> the English form")


func test_locale_changed_signal_once() -> void:
	var seen: Array = []
	var cb := func(code: String) -> void: seen.append(code)
	EventBus.locale_changed.connect(cb)
	Loc.set_locale("en")
	Loc.set_locale("en_XA")
	Loc.set_locale("en_XA")
	Loc.set_locale("en")
	Loc.set_locale("en")
	EventBus.locale_changed.disconnect(cb)
	check(seen == ["en_XA", "en"], "one emit per real change: %s" % [seen])


func test_cli_override_not_saved() -> void:
	check(Loc.parse_locale_arg(PackedStringArray(["--filter=x", "--locale=en_XA"])) == "en_XA", "--locale parsed")
	check(Loc.parse_locale_arg(PackedStringArray(["--subtitle-size=2"])) == "", "absent -> ''")
	var snap := Settings.snapshot()
	var first := Settings.first_run
	Settings.apply_defaults()
	Settings.load_settings(TMP_CFG)
	Settings._locale_override = "en_XA"
	if Settings.has_method("effective_locale"):
		check(str(Settings.call("effective_locale")) == "en_XA", "the override is the effective locale")
	check(Settings.save_settings() == OK, "saved")
	var cfg := ConfigFile.new()
	check(cfg.load(TMP_CFG) == OK, "the file reads back")
	check(str(cfg.get_value("ui", "locale", "")) == "", "the stored locale stays auto")
	for section in cfg.get_sections():
		for key in cfg.get_section_keys(section):
			check(str(cfg.get_value(section, key)) != "en_XA", "the override is never written ([%s] %s)" % [section, key])
	Settings._locale_override = ""
	DirAccess.remove_absolute(TMP_CFG)
	DirAccess.remove_absolute(TMP_CFG + ".bak")
	Settings.load_settings(Settings.SETTINGS_PATH)
	Settings.restore(snap)
	Settings.first_run = first


func test_old_settings_file_loads() -> void:
	var snap := Settings.snapshot()
	var first := Settings.first_run
	Settings.apply_defaults()
	var old := ConfigFile.new()
	old.set_value("audio", "master_volume", 0.5)
	old.save(TMP_CFG)
	Settings.load_settings(TMP_CFG)
	check(Settings.locale == "", "no [ui] locale -> '' (auto)")
	check(Loc.set_locale(Settings.locale) == "en", "auto resolves to English here")
	DirAccess.remove_absolute(TMP_CFG)
	Settings.load_settings(Settings.SETTINGS_PATH)
	Settings.restore(snap)
	Settings.first_run = first


func test_available_locales_release_hides_dev() -> void:
	check(Loc.available_locales().has("en_XA"), "debug builds offer the pseudo-locale")
	DevActions.force_unavailable = true
	check(Loc.available_locales() == PackedStringArray(["en"]), "release: only English (%s)" % [Loc.available_locales()])
	DevActions.force_unavailable = false


func test_en_unaffected_with_pseudo_loaded() -> void:
	Loc.load_catalogs()
	check(Loc.loaded_catalogs().has("en_XA"), "the pseudo catalog is loaded")
	Loc.set_locale("en")
	var l := Label.new()
	check(l.tr("Resume") == "Resume", "Label.tr stays English: %s" % l.tr("Resume"))
	check(String(TranslationServer.translate("Resume")) == "Resume", "the server stays English")
	l.free()


func test_switch_back_removes_translation() -> void:
	Loc.set_locale("en_XA")
	check(String(TranslationServer.translate("Resume")) != "Resume", "pseudo registered while active")
	Loc.set_locale("en")
	var l := Label.new()
	check(String(TranslationServer.translate("Resume")) == "Resume" and l.tr("Resume") == "Resume", "back to English removes it")
	l.free()
	Loc.set_locale("en_XA")
	Loc.clear_cache()
	check(Loc.locale() == "en" and String(TranslationServer.translate("Resume")) == "Resume", "clear_cache removes it too")


func test_dev_locale_actions() -> void:
	var list := LocaleDevActions.locales()
	check(list[0] == "en" and list.has("en_XA"), "dev list: %s" % [list])
	check(LocaleDevActions.cycle_locale() == "en_XA", "cycle to the pseudo-locale")
	check(LocaleDevActions.cycle_locale() == "en", "cycle wraps")
	check(LocaleDevActions.toggle_flag_missing() and Loc.flag_missing, "flag on")
	check(not LocaleDevActions.toggle_flag_missing(), "flag off")
	var report := LocaleDevActions.l10n_report()
	check(report.contains("| en_XA |") and report.contains("entries"), "report has the stats table")


func test_dev_locale_page_builds() -> void:
	var c: DevConsole = load("res://ui/menus/DevConsole.gd").new()
	add_child(c)
	c.open_menu()
	c.go(&"locale")
	var labels: Array = []
	for n in c._body.get_children():
		if n is Button and not n.is_queued_for_deletion():
			labels.append((n as Button).text)
	check(labels.any(func(t: String) -> bool: return t.begins_with("Locale: [en]")), "locale row: %s" % [labels])
	check(labels.has("Mark untranslated ‹›: Off") and labels.has("Catalog report") and labels.has("Reset to en"), "rows %s" % [labels])
	var h := await menu_height(c)
	check(h <= 270.0, "the page fits (%.0f px)" % h)
	c.close_menu()
	c.queue_free()


# --- TestRunner self-checks ------------------------------------------------------

func _fixture(path: String) -> RedlineTestCase:
	var s: RedlineTestCase = (load(path) as GDScript).new()
	add_child(s)
	return s


func test_runner_skip_reported() -> void:
	var runner: GDScript = load("res://tests/TestRunner.gd")
	var s := _fixture("res://tests/fixtures/l10n/SkipFixture.gd")
	var skip: Dictionary = await runner.run_one(s, "fixture::test_skips", "test_skips")
	check(skip["status"] == "SKIP" and skip["reason"] == "fixture skip", "a skip is reported as SKIP: %s" % [skip])
	check(runner.result_line(skip) == "SKIP fixture::test_skips (fixture skip)", "printed as SKIP name (reason)")
	check(not s.has_meta("skip_reason"), "the meta is removed after the test")
	var failed: Dictionary = await runner.run_one(s, "fixture::test_fails_then_skips", "test_fails_then_skips")
	check(failed["status"] == "FAIL", "a failure before the skip still fails")
	var passed: Dictionary = await runner.run_one(s, "fixture::test_passes", "test_passes")
	check(passed["status"] == "PASS" and runner.result_line(passed) == "PASS fixture::test_passes", "a pass stays PASS")
	check(runner.summary(3, 1, 1) == "3 tests, 1 failed, 1 skipped", "the summary counts skips apart")
	s.queue_free()


func test_runner_teardown_resets_global_state() -> void:
	var runner: GDScript = load("res://tests/TestRunner.gd")
	var s := _fixture("res://tests/fixtures/l10n/LeakFixture.gd")
	var r: Dictionary = await runner.run_one(s, "fixture::test_leaks_global_state", "test_leaks_global_state")
	check(r["status"] == "PASS", "the fixture ran")
	check(not Challenges.force_active, "Challenges.force_active reset")
	check(BuildInfo.force_demo == -1 and BuildInfo.force_allowed.is_empty(), "BuildInfo forcing reset")
	check(not Platform.allow_headless, "Platform.allow_headless reset")
	check(not DemoGate.dev_bypass, "DemoGate.dev_bypass reset")
	check(Loc.locale() == "en" and not Loc.flag_missing, "the locale is back to English")
	check(String(TranslationServer.translate("Resume")) == "Resume", "no pseudo text leaks")
	s.queue_free()
