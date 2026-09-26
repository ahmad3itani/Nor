class_name StringRules
extends RefCounted
## Localization lints L-1..L-9 (M9 D5 §9), a ContentValidator rule module.
## ExtractStrings --check runs the same lint(). Levels:
## - always errors: L-4 placeholder parity and L-5 PO integrity (duplicates,
##   header, parse), and L-7's glyph check for dev pseudo-locales (en_XA is
##   generated from glyphs the font has, so a miss is a tool bug);
## - ENFORCED (errors once ENFORCE is true, warnings until then): L-1 catalog
##   up to date, L-2 field coverage, L-3 hard-coded literals, L-6 source over
##   its max, L-9 two or more % specs. T13 flips ENFORCE after migrating the
##   pre-M9 strings; until then the findings are its worklist;
## - always warnings: L-7 translation health of real locales (over-length,
##   glyphs), L-8 logic comparing display strings, L-9 Loc.f args.
## The repo-wide passes (L-1/2/3/6/8/9) run only in a full content pass (after
## scan_references), so unit tests of other modules on an empty validator
## stay cheap and quiet.

## T13 sets this to true (then test_catalog_up_to_date and --check gate).
const ENFORCE := false
## Display-type fields that logic must not compare with a literal (L-8).
const DISPLAY_COMPARE := "\\.(district_name|room_name|display_name|boss_title|title)\\s*[!=]=\\s*[\"']"

enum Level { ERROR, ENFORCED, WARN }


static func run(v: ContentValidator) -> void:
	var cfg := L10nConfig.shared()
	var full := int(v.stats.get("files", 0)) > 0
	var entries: Array[CatalogEntry] = []
	if full:
		entries = ExtractStrings.build_catalog(cfg)
	var r := lint(cfg, entries, full)
	v.errors.append_array(r["errors"])
	v.warnings.append_array(r["warnings"])
	if full:
		v.set_meta("l10n_stats", ExtractStrings.stats(entries, cfg))
		v.set_meta("l10n_counts", r["counts"])


static func report(v: ContentValidator) -> String:
	if not v.has_meta("l10n_stats"):
		return ""
	var md := PackedStringArray(["## Localization", ""])
	md.append(ExtractStrings.stats_table(v.get_meta("l10n_stats")))
	md.append("")
	var counts: Dictionary = v.get_meta("l10n_counts", {})
	var ids: Array = counts.keys()
	ids.sort()
	var parts := PackedStringArray()
	for id: String in ids:
		parts.append("%s %d" % [id, counts[id]])
	md.append("String lint findings: %s. ENFORCE is %s%s." % [", ".join(parts) if not parts.is_empty() else "none",
		str(ENFORCE).to_lower(), "" if ENFORCE else " (L-1/2/3/6/9 are warnings until the T13 migration)"])
	return "\n".join(md)


## Every string lint. `entries` is the built catalog (empty when not full).
## Returns {errors, warnings, counts: rule id -> findings}.
static func lint(cfg: L10nConfig, entries: Array[CatalogEntry], full: bool = true) -> Dictionary:
	var r := {"errors": PackedStringArray(), "warnings": PackedStringArray(), "counts": {}}
	for path in DataDir.list_files(LocaleTable.CATALOG_DIR, "po"):
		_add(r, "L-4", check_po(PoFile.load_file(path), path), Level.ERROR)
	for row in LocaleTable.shared().rows:
		if row == null or not row.enabled or row.code == Loc.SOURCE_LOCALE:
			continue
		var path := "%s/%s.po" % [LocaleTable.CATALOG_DIR, row.code]
		if not FileAccess.file_exists(path):
			continue
		var h := check_health(PoFile.load_file(path), row, entries, cfg)
		_add(r, "L-7", h["errors"], Level.ERROR)
		_add(r, "L-7", h["warnings"], Level.WARN)
	if not full:
		return r
	_add(r, "L-1", check_catalog_current(entries, cfg), Level.ENFORCED)
	_add(r, "L-2", check_coverage(ExtractStrings.files_under(ContentValidator.SCAN_DIRS, "gd", cfg), cfg), Level.ENFORCED)
	_add(r, "L-6", check_source_limits(entries), Level.ENFORCED)
	_add(r, "L-9", check_templates(entries), Level.ENFORCED)
	for path in ExtractStrings.files_under(cfg.code_dirs, "gd", cfg):
		var source := FileAccess.get_file_as_string(path)
		_add(r, "L-3", check_literals(source, path, cfg), Level.ENFORCED)
		_add(r, "L-8", check_display_logic(source, path), Level.WARN)
		if source.contains("Loc."):
			_add(r, "L-9", check_format_args(source, path), Level.WARN)
	return r


static func _add(r: Dictionary, id: String, msgs: PackedStringArray, level: Level) -> void:
	if msgs.is_empty():
		return
	var counts: Dictionary = r["counts"]
	counts[id] = int(counts.get(id, 0)) + msgs.size()
	var to_errors := level == Level.ERROR or (level == Level.ENFORCED and ENFORCE)
	var key := "errors" if to_errors else "warnings"
	var list: PackedStringArray = r[key]
	list.append_array(msgs)
	r[key] = list


## Where a finding goes at the current ENFORCE setting (tests read it).
static func level_is_error(level: Level) -> bool:
	return level == Level.ERROR or (level == Level.ENFORCED and ENFORCE)


# --- L-1 -----------------------------------------------------------------------

static func check_catalog_current(entries: Array[CatalogEntry], cfg: L10nConfig) -> PackedStringArray:
	var out := PackedStringArray()
	for pair: Array in [[ExtractStrings.POT_PATH, ExtractStrings.render_pot(entries)],
			[ExtractStrings.PSEUDO_PATH, ExtractStrings.render_pseudo(entries, cfg)]]:
		var disk := FileAccess.get_file_as_string(pair[0]) if FileAccess.file_exists(pair[0]) else ""
		var diff := ExtractStrings.first_difference(disk, pair[1])
		if diff != "":
			out.append("[L-1] %s is out of date (%s); run godot --headless res://devtools/l10n/ExtractStrings.tscn -- --write"
				% [pair[0].trim_prefix("res://"), diff])
	return out


# --- L-2 -----------------------------------------------------------------------

static func check_coverage(paths: PackedStringArray, cfg: L10nConfig) -> PackedStringArray:
	var out := PackedStringArray()
	var rx := RegEx.create_from_string(cfg.text_field_pattern)
	for path in paths:
		if not FileAccess.get_file_as_string(path).contains("@export"):
			continue
		var script := load(path) as Script
		var missing := LocFields.unclassified(script, rx)
		if not missing.is_empty():
			out.append(coverage_message(path, missing))
	return out


static func coverage_message(path: String, fields: PackedStringArray) -> String:
	return "[L-2] %s: text fields not classified: %s (declare LOC_FIELDS or LOC_EXEMPT)" % [path.trim_prefix("res://"), ", ".join(fields)]


# --- L-3 -----------------------------------------------------------------------

## String literals with a letter that reach a screen sink without Loc.
## Allowed: "", literals without letters, all-caps up to 3 chars ("A", "LB"),
## and lines marked `# l10n: ignore(<reason>)` (on the line or the line above).
static func check_literals(source: String, path: String, cfg: L10nConfig) -> PackedStringArray:
	var found: Array = []  # [offset, message], sorted into source order below
	var g := GdSource.parse(source)
	var rel := path.trim_prefix("res://")
	for sink in cfg.literal_sinks:
		var call := sink.ends_with("(")
		var pat := _escape(sink.trim_suffix("(").strip_edges())
		if call:
			pat = ("(?<![A-Za-z0-9_])" if _ident_start(sink) else "") + pat + "\\s*\\("
		else:
			pat = pat + "(?!=)"
		for m in RegEx.create_from_string(pat).search_all(g.masked):
			var spans: Array = []
			if call:
				spans = g.call_args(m.get_end() - 1)
			else:
				var eol := g.masked.find("\n", m.get_end())
				spans = [[m.get_end(), eol if eol >= 0 else g.masked.length()]]
			for a: Array in spans:
				var lit := g.literal_leading(a[0], a[1])
				if lit.is_empty() or not flaggable(str(lit["value"])):
					continue
				var at := g.skip_space(a[0], a[1])
				var line := g.line_of(at)
				if _ignored(g, line) or _ignored(g, g.line_of(m.get_start())):
					continue
				found.append([at, "[L-3] %s:%d: hard-coded text \"%s\" reaches %s (wrap it in Loc.t/Loc.f or mark # l10n: ignore(<reason>))"
					% [rel, line + 1, str(lit["value"]).left(48).c_escape(), sink.strip_edges()]])
	for s: Dictionary in ExtractStrings.code_strings(source, path):
		if s["triple"]:
			found.append([int(s["offset"]), "[L-3] %s:%d: Loc.%s with a triple-quoted string (the extractor cannot read it)"
				% [rel, s["line"], s["kind"]]])
	found.sort_custom(func(x: Array, y: Array) -> bool: return int(x[0]) < int(y[0]))
	var out := PackedStringArray()
	for f: Array in found:
		out.append(f[1])
	return out


static func flaggable(text: String) -> bool:
	if text == "" or RegEx.create_from_string("[A-Za-z]").search(text) == null:
		return false
	return RegEx.create_from_string("^[A-Z0-9]{1,3}$").search(text) == null


static func _ignored(g: GdSource, line: int) -> bool:
	if g.comment_on(line).contains("l10n: ignore("):
		return true
	return line > 0 and g.comment_on(line - 1).contains("l10n: ignore(") and g.line_text(line - 1).strip_edges().begins_with("#")


static func _ident_start(s: String) -> bool:
	return s != "" and RegEx.create_from_string("^[A-Za-z_]").search(s) != null


static func _escape(s: String) -> String:
	var out := ""
	for ch in s:
		out += ("\\" + ch) if "\\.^$|?*+()[]{}".contains(ch) else ch
	return out


# --- L-4 / L-5 -----------------------------------------------------------------

## PO integrity: parse errors, duplicate (ctx, msgid), the Language header
## matching the file name (L-5), and placeholder parity of every translated
## form (L-4: a translator may reorder {names}, never drop or add them).
static func check_po(po: PoFile, path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var file := path.get_file()
	for e in po.errors:
		out.append("[L-5] %s: %s" % [file, e])
	for d in po.duplicates():
		out.append("[L-5] %s: %s is listed twice" % [file, d])
	if path.get_extension() == "po" and po.header_value("Language") != file.get_basename():
		out.append("[L-5] %s: header Language '%s' does not match the file name" % [file, po.header_value("Language")])
	for e in po.entries:
		if bool(e["obsolete"]):
			continue
		var forms := PoFile.forms(e)
		for i in forms.size():
			if forms[i] == "":
				continue
			var src := str(e["msgid"]) if i == 0 or str(e["msgid_plural"]) == "" else str(e["msgid_plural"])
			if CatalogEntry.placeholder_set(src) != CatalogEntry.placeholder_set(forms[i]):
				out.append("[L-4] %s: \"%s\" form %d has placeholders %s, the source %s" % [file, str(e["msgid"]).left(48).c_escape(), i,
					CatalogEntry.placeholder_set(forms[i]), CatalogEntry.placeholder_set(src)])
	return out


# --- L-6 -----------------------------------------------------------------------

static func check_source_limits(entries: Array[CatalogEntry]) -> PackedStringArray:
	var out := PackedStringArray()
	for e in entries:
		if e.max_chars > 0 and e.msgid.length() > e.max_chars:
			out.append("[L-6] \"%s\" is %d chars, over its max %d (%s)" % [e.msgid.left(48).c_escape(), e.msgid.length(), e.max_chars,
				", ".join(e.keys)])
	return out


# --- L-7 -----------------------------------------------------------------------

## Translation health of one locale: glyphs the font chain lacks (an error for
## a dev pseudo-locale), and translations far longer than their field allows.
## Missing and fuzzy counts are report numbers, not findings.
static func check_health(po: PoFile, row: LocaleInfo, entries: Array[CatalogEntry], cfg: L10nConfig) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var text := row.endonym + row.coverage_sample
	for e in po.entries:
		if not bool(e["obsolete"]) and not PoFile.is_fuzzy(e):
			for f in PoFile.forms(e):
				text += f
	var missing := Pseudo.missing_glyphs(text, row)
	if missing != "":
		var msg := "[L-7] %s: glyphs not in the font chain: %s" % [row.code, missing]
		if row.dev_only:
			errors.append(msg)
		else:
			warnings.append(msg)
	if row.dev_only:
		return {"errors": errors, "warnings": warnings}  # the pseudo-locale is longer on purpose
	for c in entries:
		if c.max_chars <= 0:
			continue
		var t := po.find(c.ctx, c.msgid)
		if t.is_empty() or PoFile.is_fuzzy(t):
			continue
		for f in PoFile.forms(t):
			if f.length() > c.max_chars * cfg.over_length_warn_ratio:
				warnings.append("[L-7] %s: \"%s\" translation is %d chars (max %d x %.1f)" % [row.code, c.msgid.left(40).c_escape(),
					f.length(), c.max_chars, cfg.over_length_warn_ratio])
				break
	return {"errors": errors, "warnings": warnings}


# --- L-8 -----------------------------------------------------------------------

static func check_display_logic(source: String, path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var g := GdSource.parse(source)
	for m in RegEx.create_from_string(DISPLAY_COMPARE).search_all(g.masked):
		out.append("[L-8] %s:%d: logic compares a display string (%s); compare ids instead" % [path.trim_prefix("res://"),
			g.line_of(m.get_start()) + 1, m.get_string(1)])
	return out


# --- L-9 -----------------------------------------------------------------------

## Two or more % specs cannot be reordered by a translator: use {names}.
static func check_templates(entries: Array[CatalogEntry]) -> PackedStringArray:
	var out := PackedStringArray()
	for e in entries:
		var n := 0
		for p in CatalogEntry.placeholders(e.msgid):
			if p.begins_with("%") and p != "%%":
				n += 1
		if n >= 2:
			out.append("[L-9] \"%s\" has %d %% placeholders; use named {placeholders} (%s)" % [e.msgid.left(48).c_escape(), n,
				", ".join(e.refs)])
	return out


## Loc.f/tn with a literal args dictionary must name every {placeholder}.
static func check_format_args(source: String, path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for s: Dictionary in ExtractStrings.code_strings(source, path):
		if not s["has_arg_dict"]:
			continue
		var keys: PackedStringArray = s["arg_keys"]
		for p in CatalogEntry.placeholders(str(s["msgid"]) + " " + str(s["plural"])):
			if not p.begins_with("{"):
				continue
			var name := p.substr(1, p.length() - 2)
			if not keys.has(name) and not (s["kind"] == "tn" and name == "n"):
				out.append("[L-9] %s:%d: Loc.%s args do not name {%s}" % [path.trim_prefix("res://"), s["line"], s["kind"], name])
				break
	return out
