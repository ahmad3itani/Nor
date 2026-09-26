extends RedlineTestCase
## M9 D6 §3.5 (D-166): the checked-in export presets hold EX-1..EX-11, each
## rule catches its own drift, tools/build/build.py checks the same rule ids,
## and the build probe's minimums hold in the editor.

const BUILD_PY := "res://tools/build/build.py"


func _cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	check(cfg.load(ExportRules.PRESETS_PATH) == OK, "export_presets.cfg loads as a ConfigFile")
	return cfg


func _project() -> String:
	return FileAccess.get_file_as_string(ExportRules.PROJECT_PATH)


func _gitignore() -> String:
	return FileAccess.get_file_as_string(ExportRules.GITIGNORE_PATH)


## The section of the preset named `n`.
func _sec(cfg: ConfigFile, n: String) -> String:
	for s in ExportRules.presets(cfg):
		if cfg.get_value(s, "name", "") == n:
			return s
	return ""


## Runs the rules on a mutated copy and expects `rule` among the errors.
func _expect(rule: String, cfg: ConfigFile, project: String = "", gitignore: String = "") -> void:
	var errs := ExportRules.check(cfg, project if project != "" else _project(), gitignore if gitignore != "" else _gitignore())
	check(Array(errs).any(func(e: String) -> bool: return e.begins_with("[%s] " % rule)), "%s caught (%s)" % [rule, errs])


func test_invariants_hold_on_checked_in_file() -> void:
	var errs := ExportRules.check(_cfg(), _project(), _gitignore())
	check(errs.is_empty(), "no drift: %s" % [errs])
	check(ExportRules.presets(_cfg()).size() == 8, "8 presets")


func test_ex1_missing_preset() -> void:
	var cfg := _cfg()
	cfg.set_value(_sec(cfg, "Web Demo"), "name", "Web Demo 2")
	_expect("EX-1", cfg)


func test_ex2_demo_feature() -> void:
	var cfg := _cfg()
	cfg.set_value(_sec(cfg, "Linux Demo"), "custom_features", "")
	_expect("EX-2", cfg)
	cfg = _cfg()
	cfg.set_value(_sec(cfg, "Linux"), "custom_features", "steam")
	_expect("EX-2", cfg)


func test_ex3_runnable() -> void:
	var cfg := _cfg()
	cfg.set_value(_sec(cfg, "Windows Demo"), "runnable", true)
	_expect("EX-3", cfg)


func test_ex4_excludes() -> void:
	var cfg := _cfg()
	cfg.set_value(_sec(cfg, "Linux"), "exclude_filter", "tests/*, build/*")
	_expect("EX-4", cfg)
	cfg = _cfg()
	cfg.set_value(_sec(cfg, "Linux"), "exclude_filter", "tests/*, tools/*, build/*, devtools/*")
	_expect("EX-4", cfg)


func test_ex5_secrets() -> void:
	var cfg := _cfg()
	cfg.set_value(_sec(cfg, "macOS") + ".options", "codesign/identity", "Developer ID Application: X")
	_expect("EX-5", cfg)
	cfg = _cfg()
	cfg.set_value(_sec(cfg, "Linux"), "encrypt_pck", true)
	_expect("EX-5", cfg)


func test_ex6_web_nothreads() -> void:
	var cfg := _cfg()
	cfg.set_value(_sec(cfg, "Web") + ".options", "variant/thread_support", true)
	_expect("EX-6", cfg)
	cfg = _cfg()
	cfg.set_value(_sec(cfg, "Web Demo") + ".options", "progressive_web_app/enabled", true)
	_expect("EX-6", cfg)


func test_ex7_macos() -> void:
	var cfg := _cfg()
	cfg.set_value(_sec(cfg, "macOS") + ".options", "application/short_version", "1.0.0")
	_expect("EX-7", cfg)
	cfg = _cfg()
	cfg.set_value(_sec(cfg, "macOS Demo") + ".options", "application/bundle_identifier", "dev.redline.game")
	_expect("EX-7", cfg)
	_expect("EX-7", _cfg(), _project().replace("import_etc2_astc=true", "import_etc2_astc=false"))


func test_macos_version_matches_config_version() -> void:
	var cfg := _cfg()
	var numeric := ExportRules._numeric(str(ProjectSettings.get_setting("application/config/version")))
	check(numeric == "0.8.0", "numeric config/version at this merge (%s)" % numeric)
	for n: String in ["macOS", "macOS Demo"]:
		var o := _sec(cfg, n) + ".options"
		check(cfg.get_value(o, "application/short_version") == numeric and cfg.get_value(o, "application/version") == numeric,
			"%s versions = %s" % [n, numeric])


func test_ex8_windows() -> void:
	var cfg := _cfg()
	cfg.set_value(_sec(cfg, "Windows") + ".options", "application/modify_resources", true)
	_expect("EX-8", cfg)


func test_ex9_demo_user_dir() -> void:
	_expect("EX-9", _cfg(), _project().replace("config/custom_user_dir_name.demo=\"REDLINE Demo\"\n", ""))
	_expect("EX-9", _cfg(), _project().replace("config/use_custom_user_dir.demo=true\n", ""))


func test_ex10_gitignore() -> void:
	_expect("EX-10", _cfg(), "", _gitignore() + "\nexport_presets.cfg\n")
	_expect("EX-10", _cfg(), "", _gitignore().replace("build/", "stage/"))


func test_ex11_include_filter() -> void:
	var cfg := _cfg()
	cfg.set_value(_sec(cfg, "Web Demo"), "include_filter", "locale/*.po")
	_expect("EX-11", cfg)


## build.py re-implements the list in Python: both name every rule id.
func test_build_py_lists_same_rule_ids() -> void:
	check(FileAccess.file_exists(BUILD_PY), "tools/build/build.py exists")
	var py := FileAccess.get_file_as_string(BUILD_PY)
	var gd := FileAccess.get_file_as_string("res://devtools/content/rules/ExportRules.gd")
	for id in ExportRules.RULE_IDS:
		check(py.contains("\"%s\"" % id), "build.py lists %s" % id)
		check(py.contains("[%s]" % id), "build.py reports %s" % id)
		check(gd.contains("[%s]" % id), "ExportRules reports %s" % id)
	check(py.contains("\"PY-NET\""), "build.py keeps the tools network ban (PY-NET)")


func test_build_probe_minimums() -> void:
	var info := BuildProbe.info()
	var data: Dictionary = info["data"]
	for key: String in BuildProbe.MINIMUMS:
		check(int(data.get(key, 0)) >= int(BuildProbe.MINIMUMS[key]), "%s: %d >= %d" % [key, data.get(key, 0), BuildProbe.MINIMUMS[key]])
	check(BuildProbe.problems(info).is_empty(), "the editor run is healthy: %s" % [BuildProbe.problems(info)])
	check(info["start_room_loads"], "the campaign start room loads")
	check(info["rooms"].get("undercity", 0) == 7 and info["rooms"].get("lowlight", 0) == 11, "rooms %s" % [info["rooms"]])
	check(info["demo"]["relay_allowed"] == true, "the full game allows the Relay")
	check(info["demo"]["id"] == "undercity" and info["demo"]["allowed"] == 8, "demo scope %s" % [info["demo"]])
	check((info["locales"] as Array).has("en"), "locales %s" % [info["locales"]])
	var line := "BUILD_INFO " + JSON.stringify(info)
	var parsed: Variant = JSON.parse_string(line.trim_prefix("BUILD_INFO "))
	check(parsed is Dictionary and parsed["kind"] == "full", "the line parses back")
	var bad := info.duplicate(true)
	bad["data"]["quests"] = 0
	check(not BuildProbe.problems(bad).is_empty(), "a missing data scan (0 quests) is a problem")
