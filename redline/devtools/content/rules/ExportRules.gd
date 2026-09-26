class_name ExportRules
extends RefCounted
## Export preset invariants EX-1..EX-11 (M9 D6 §3.5, D-166). The same list
## lives in tools/build/build.py (--check, and every build refuses to start on
## drift), because Python cannot call GDScript: keep both in step (the test
## test_build_py_lists_same_rule_ids checks the ids match).

const PRESETS_PATH := "res://export_presets.cfg"
const PROJECT_PATH := "res://project.godot"
const GITIGNORE_PATH := "res://.gitignore"
const RULE_IDS: PackedStringArray = ["EX-1", "EX-2", "EX-3", "EX-4", "EX-5", "EX-6", "EX-7", "EX-8", "EX-9", "EX-10", "EX-11"]
## name -> platform, full presets first; each has a " Demo" twin.
const PLATFORMS := {"Windows": "Windows Desktop", "Linux": "Linux", "macOS": "macOS", "Web": "Web"}
const REQUIRED_EXCLUDES: PackedStringArray = ["tests/*", "tools/*", "build/*"]
## SliceStats reads ContentValidator at runtime, so devtools/ must ship.
const FORBIDDEN_EXCLUDES: PackedStringArray = ["devtools/*"]
## Files only include_filter packs (not resources): shipped ghosts, catalogs.
const REQUIRED_INCLUDES: PackedStringArray = ["data/challenges/ghosts/*.ghost", "locale/*.po"]
const SECRET_KEY_RE := "(?i)password|keystore|identity|apple_id|team_id|api_?key|certificate|p12|provisioning"


## The validator pass: skipped with a warning when the presets are absent.
static func run(v: ContentValidator) -> void:
	if not FileAccess.file_exists(PRESETS_PATH):
		v.warnings.append("[EX-1] %s is missing; export checks skipped" % PRESETS_PATH)
		return
	var cfg := ConfigFile.new()
	if cfg.load(PRESETS_PATH) != OK:
		v.errors.append("[EX-1] %s does not parse" % PRESETS_PATH)
		return
	for e in check(cfg, FileAccess.get_file_as_string(PROJECT_PATH), FileAccess.get_file_as_string(GITIGNORE_PATH)):
		v.errors.append(e)


static func report(_v: ContentValidator) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(PRESETS_PATH) != OK:
		return ""
	var md: PackedStringArray = ["## Export presets", "", "| Preset | Platform | Features | Runnable | Exclude |", "|---|---|---|---|---|"]
	for s in presets(cfg):
		md.append("| %s | %s | %s | %s | %s |" % [cfg.get_value(s, "name", ""), cfg.get_value(s, "platform", ""),
			cfg.get_value(s, "custom_features", ""), cfg.get_value(s, "runnable", false), cfg.get_value(s, "exclude_filter", "")])
	return "\n".join(md)


## Preset section names ("preset.0", ...) in file order.
static func presets(cfg: ConfigFile) -> PackedStringArray:
	var out := PackedStringArray()
	for s in cfg.get_sections():
		if s.begins_with("preset.") and not s.ends_with(".options"):
			out.append(s)
	return out


static func check(cfg: ConfigFile, project_text: String, gitignore_text: String) -> PackedStringArray:
	var errs := PackedStringArray()
	var by_name := {}
	for s in presets(cfg):
		var n := str(cfg.get_value(s, "name", ""))
		if by_name.has(n):
			errs.append("[EX-1] duplicate preset name '%s'" % n)
		by_name[n] = s
	var expected := {}
	for base: String in PLATFORMS:
		expected[base] = PLATFORMS[base]
		expected[base + " Demo"] = PLATFORMS[base]
	if presets(cfg).size() != expected.size():
		errs.append("[EX-1] %d presets, expected %d" % [presets(cfg).size(), expected.size()])
	for n: String in expected:
		if not by_name.has(n):
			errs.append("[EX-1] preset '%s' is missing" % n)
		elif str(cfg.get_value(by_name[n], "platform", "")) != expected[n]:
			errs.append("[EX-1] preset '%s' platform is '%s', expected '%s'" % [n, cfg.get_value(by_name[n], "platform", ""), expected[n]])
	for n: String in by_name:
		if not expected.has(n):
			errs.append("[EX-1] unexpected preset '%s'" % n)
	var version := _numeric(_project_value(project_text, "application", "config/version"))
	var bundles := {}
	for n: String in by_name:
		var s: String = by_name[n]
		var o := s + ".options"
		var demo := n.ends_with(" Demo")
		var features := _list(str(cfg.get_value(s, "custom_features", "")))
		if demo != features.has("demo"):
			errs.append("[EX-2] '%s': custom_features must %scontain demo" % [n, "" if demo else "not "])
		for f in features:
			if f != "demo":
				errs.append("[EX-2] '%s': unexpected custom feature '%s'" % [n, f])
		if bool(cfg.get_value(s, "runnable", false)) == demo:
			errs.append("[EX-3] '%s': runnable must be %s" % [n, not demo])
		var excludes := _list(str(cfg.get_value(s, "exclude_filter", "")))
		for x in REQUIRED_EXCLUDES:
			if not excludes.has(x):
				errs.append("[EX-4] '%s': exclude_filter lacks %s" % [n, x])
		for x in FORBIDDEN_EXCLUDES:
			if excludes.has(x):
				errs.append("[EX-4] '%s': exclude_filter must not exclude %s (runtime code lives there)" % [n, x])
		var rx := RegEx.create_from_string(SECRET_KEY_RE)
		if cfg.has_section(o):
			for k in cfg.get_section_keys(o):
				var val: Variant = cfg.get_value(o, k)
				if rx.search(k) and val is String and (val as String) != "":
					errs.append("[EX-5] '%s': credential-like option %s has a value" % [n, k])
		if bool(cfg.get_value(s, "encrypt_pck", false)):
			errs.append("[EX-5] '%s': encrypt_pck must be false (no key is ever stored)" % n)
		var platform := str(cfg.get_value(s, "platform", ""))
		if platform == "Web":
			if bool(cfg.get_value(o, "variant/thread_support", true)):
				errs.append("[EX-6] '%s': variant/thread_support must be false (nothreads)" % n)
			if bool(cfg.get_value(o, "progressive_web_app/enabled", true)):
				errs.append("[EX-6] '%s': progressive_web_app/enabled must be false" % n)
		elif platform == "macOS":
			var sv := str(cfg.get_value(o, "application/short_version", ""))
			var vv := str(cfg.get_value(o, "application/version", ""))
			if sv != version or vv != version:
				errs.append("[EX-7] '%s': short_version '%s' / version '%s' must equal '%s' (config/version)" % [n, sv, vv, version])
			if str(cfg.get_value(o, "binary_format/architecture", "")) == "universal" \
					and _project_value(project_text, "rendering", "textures/vram_compression/import_etc2_astc") != "true":
				errs.append("[EX-7] '%s': a universal macOS build needs import_etc2_astc=true in project.godot" % n)
			var bundle := str(cfg.get_value(o, "application/bundle_identifier", ""))
			if bundles.has(bundle):
				errs.append("[EX-7] '%s': bundle id '%s' is also used by '%s'" % [n, bundle, bundles[bundle]])
			bundles[bundle] = n
		elif platform == "Windows Desktop":
			if bool(cfg.get_value(o, "application/modify_resources", true)):
				errs.append("[EX-8] '%s': application/modify_resources must be false (no rcedit)" % n)
			if bool(cfg.get_value(o, "codesign/enable", true)):
				errs.append("[EX-8] '%s': codesign/enable must be false" % n)
		var includes := _list(str(cfg.get_value(s, "include_filter", "")))
		for x in REQUIRED_INCLUDES:
			if not includes.has(x):
				errs.append("[EX-11] '%s': include_filter lacks %s" % [n, x])
	if _project_value(project_text, "application", "config/use_custom_user_dir.demo") != "true":
		errs.append("[EX-9] project.godot lacks config/use_custom_user_dir.demo=true")
	var demo_dir := _project_value(project_text, "application", "config/custom_user_dir_name.demo")
	var base_dir := _project_value(project_text, "application", "config/custom_user_dir_name")
	if demo_dir == "" or demo_dir == base_dir:
		errs.append("[EX-9] project.godot config/custom_user_dir_name.demo must be set and differ from the base name")
	var ignored := _list_lines(gitignore_text)
	if ignored.has("export_presets.cfg"):
		errs.append("[EX-10] .gitignore must not list export_presets.cfg (it is checked in)")
	if not (ignored.has("build/") or ignored.has("/build/")):
		errs.append("[EX-10] .gitignore must list build/")
	return errs


## "0.8.0-m8" -> "0.8.0".
static func _numeric(v: String) -> String:
	var m := RegEx.create_from_string("^(\\d+\\.\\d+\\.\\d+)").search(v)
	return m.get_string(1) if m else v


## The raw value of `key=` in `[section]` of a Godot cfg text, unquoted.
static func _project_value(text: String, section: String, key: String) -> String:
	var in_section := false
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("["):
			in_section = line == "[%s]" % section
		elif in_section and line.begins_with(key + "="):
			return line.substr(key.length() + 1).trim_prefix("\"").trim_suffix("\"")
	return ""


static func _list(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	for p in s.split(","):
		if p.strip_edges() != "":
			out.append(p.strip_edges())
	return out


static func _list_lines(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	for l in s.split("\n"):
		var t := l.strip_edges()
		if t != "" and not t.begins_with("#"):
			out.append(t)
	return out
