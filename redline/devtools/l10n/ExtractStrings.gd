class_name ExtractStrings
extends Node
## The string extractor (M9 D5 §6). Run from redline/:
##   godot --headless res://devtools/l10n/ExtractStrings.tscn -- --write   # regenerate redline.pot + en_XA.po
##   godot --headless res://devtools/l10n/ExtractStrings.tscn -- --check   # exit 1 on drift or string-lint errors
##   godot --headless res://devtools/l10n/ExtractStrings.tscn -- --merge [--new=fr]  # update translator files
##   godot --headless res://devtools/l10n/ExtractStrings.tscn -- --stats   # per-locale coverage (Markdown)
##
## GDScript rather than Python (the roomgen tools): it must LOAD resources
## (sub-resources, typed arrays, inherited LOC_FIELDS consts, SceneState),
## and StringRules reuses the same code in-process, so there is no second
## .tres parser to keep correct. Everything but _run is pure (no writes).
## Only T06 (first) and T13 (final) regenerate the checked-in catalogs.

const POT_PATH := "res://locale/redline.pot"
const PSEUDO_CODE := "en_XA"
const PSEUDO_PATH := "res://locale/en_XA.po"
const DEFAULT_PLURAL_FORMS := "nplurals=2; plural=(n != 1);"
const CALL_PATTERN := "(?<![A-Za-z0-9_])Loc\\.(t|f|tn|upper)\\s*\\("
## "# l10n" or "# l10n(ctx)" at the end of a line: every literal on it is catalogued.
const TAG_PATTERN := "^#\\s*l10n(?:\\(([A-Za-z0-9_.]+)\\))?\\s*$"
const POT_HEADER := [
	"Project-Id-Version: REDLINE",
	"Content-Type: text/plain; charset=UTF-8",
	"Content-Transfer-Encoding: 8bit",
	"Language: ",
	"Plural-Forms: nplurals=2; plural=(n != 1);",
]

static var _call_rx: RegEx
static var _tag_rx: RegEx


func _ready() -> void:
	var code := _run(OS.get_cmdline_user_args())
	get_tree().quit(code)


# --- Catalog -------------------------------------------------------------------

## The whole catalog, sorted (by first reference, then order of appearance).
static func build_catalog(cfg: L10nConfig = null) -> Array[CatalogEntry]:
	var c := cfg if cfg != null else L10nConfig.shared()
	var out := {}
	scan_resources(c.resource_dirs, out, c)
	scan_scenes(c.scene_dirs, out, c)
	scan_code(c.code_dirs, c.code_exempt, out)
	return entries_of(out)


## CatalogEntry values of a scan dictionary (bookkeeping keys dropped), sorted.
static func entries_of(out: Dictionary) -> Array[CatalogEntry]:
	var scripts: Dictionary = out.get("__scripts", {})
	var paths: Array = scripts.keys()
	paths.sort()
	for p: String in paths:
		LocFields.script_defaults(scripts[p], out)
	var list: Array[CatalogEntry] = []
	for k: String in out:
		if not k.begins_with("__"):
			list.append(out[k])
	CatalogEntry.sort_entries(list)
	return list


## Sorted, de-duplicated paths of every .<ext> under `dirs` (recursive),
## minus the config's exempt prefixes. Source tree only: the tool never runs
## in an exported build.
static func files_under(dirs: PackedStringArray, ext: String, cfg: L10nConfig = null) -> PackedStringArray:
	var seen := {}
	for d in dirs:
		for f in ContentValidator._files(d, [ext]):
			if cfg == null or not cfg.is_exempt(f):
				seen[f] = true
	var out := PackedStringArray(seen.keys())
	out.sort()
	return out


static func scan_resources(dirs: PackedStringArray, out: Dictionary, cfg: L10nConfig = null) -> void:
	for path in files_under(dirs, "tres", cfg):
		var res := load(path)
		if res is Resource:
			LocFields.walk(res, path.trim_prefix("res://"), out)


static func scan_scenes(dirs: PackedStringArray, out: Dictionary, cfg: L10nConfig = null) -> void:
	var scripts: Dictionary = out.get("__scripts", {})
	for path in files_under(dirs, "tscn", cfg):
		var ps := load(path) as PackedScene
		if ps == null:
			continue
		for s in LocFields.walk_scene(ps.get_state(), path.trim_prefix("res://"), out):
			if s.resource_path != "" and (cfg == null or not cfg.is_exempt(s.resource_path)):
				scripts[s.resource_path] = s
	out["__scripts"] = scripts


static func scan_code(dirs: PackedStringArray, exempt: PackedStringArray, out: Dictionary) -> void:
	var cfg := L10nConfig.new()
	cfg.code_exempt = exempt
	var scripts: Dictionary = out.get("__scripts", {})
	for path in files_under(dirs, "gd", cfg):
		var source := FileAccess.get_file_as_string(path)
		var rel := path.trim_prefix("res://")
		if source.contains("Loc.") or source.contains("l10n"):
			for s: Dictionary in code_strings(source, path):
				if s.get("triple", false) or str(s["msgid"]) == "":
					continue
				var key := "%s::%s" % [rel, "l10n" if s["kind"] == "tag" else "Loc." + str(s["kind"])]
				LocFields.add(out, s["msgid"], s["ctx"], rel, key, 0, "", s["plural"])
		if source.contains("LOC_FIELDS"):
			var script := load(path) as Script
			if script != null:
				scripts[path] = script
	out["__scripts"] = scripts


## Every catalogued string of one source file, in source order:
## {msgid, ctx, plural, kind ("t"/"f"/"tn"/"upper"/"tag"), line (1-based),
##  offset, triple, arg_keys (Loc.f/tn literal dict keys), has_arg_dict}.
## A call whose text is not a literal (Loc.t(data.title)) is skipped: that
## text comes from data and is extracted there.
static func code_strings(source: String, _path: String = "") -> Array[Dictionary]:
	if _call_rx == null:
		_call_rx = RegEx.create_from_string(CALL_PATTERN)
		_tag_rx = RegEx.create_from_string(TAG_PATTERN)
	var g := GdSource.parse(source)
	var out: Array[Dictionary] = []
	for m in _call_rx.search_all(g.masked):
		var kind := m.get_string(1)
		var args := g.call_args(m.get_end() - 1)
		if args.is_empty():
			continue
		var msg := g.literal_exact(args[0][0], args[0][1])
		if msg.is_empty():
			continue
		var plural := {}
		var ctx_i := 1
		var dict_i := -1
		match kind:
			"f":
				ctx_i = 2
				dict_i = 1
			"tn":
				plural = g.literal_exact(args[1][0], args[1][1]) if args.size() > 1 else {}
				ctx_i = 4
				dict_i = 3
		var ctx: Dictionary = g.literal_exact(args[ctx_i][0], args[ctx_i][1]) if args.size() > ctx_i else {}
		var keys := PackedStringArray()
		var has_dict := false
		if dict_i >= 0 and args.size() > dict_i:
			keys = g.dict_keys(args[dict_i][0], args[dict_i][1])
			has_dict = g.masked.substr(args[dict_i][0], args[dict_i][1] - args[dict_i][0]).strip_edges().begins_with("{")
		out.append({"msgid": str(msg["value"]), "ctx": str(ctx.get("value", "")), "plural": str(plural.get("value", "")),
			"kind": kind, "line": g.line_of(m.get_start()) + 1, "offset": m.get_start(), "triple": bool(msg["triple"]),
			"arg_keys": keys, "has_arg_dict": has_dict})
	for line: int in g.comments:
		var tm := _tag_rx.search(str(g.comments[line]))
		if tm == null:
			continue
		for off: int in g.literals:
			if g.line_of(off) != line:
				continue
			var lit: Dictionary = g.literals[off]
			out.append({"msgid": str(lit["value"]), "ctx": tm.get_string(1), "plural": "", "kind": "tag", "line": line + 1,
				"offset": off, "triple": bool(lit["triple"]), "arg_keys": PackedStringArray(), "has_arg_dict": false})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["offset"]) < int(b["offset"]))
	return out


# --- Rendering -----------------------------------------------------------------

static func render_pot(entries: Array[CatalogEntry]) -> String:
	var po := PoFile.new()
	po.header_comments = PackedStringArray([
		"REDLINE string catalog. GENERATED by devtools/l10n/ExtractStrings — do not edit.",
		"Source language: English (en). Regenerate: godot --headless res://devtools/l10n/ExtractStrings.tscn -- --write"])
	po.header = PackedStringArray(POT_HEADER)
	for c in entries:
		var e := _po_entry(c, true)
		if c.msgid_plural != "":
			e["msgstr_plural"] = PackedStringArray(["", ""])
		po.entries.append(e)
	return po.render()


static func render_pseudo(entries: Array[CatalogEntry], cfg: L10nConfig = null) -> String:
	var po := PoFile.new()
	po.header_comments = PackedStringArray([
		"REDLINE pseudo-locale en_XA (dev builds only). GENERATED by devtools/l10n/ExtractStrings — do not edit.",
		"Accented, about 40% longer and bracketed: plain ASCII on screen means the text skipped Loc."])
	po.header = PackedStringArray(POT_HEADER)
	po.set_header_value("Language", PSEUDO_CODE)
	for c in entries:
		var e := _po_entry(c, false)
		if c.msgid_plural != "":
			e["msgstr_plural"] = PackedStringArray([Pseudo.pseudo(c.msgid, cfg), Pseudo.pseudo(c.msgid_plural, cfg)])
		else:
			e["msgstr"] = Pseudo.pseudo(c.msgid, cfg)
		po.entries.append(e)
	return po.render()


## The checked-in catalog read back as entries (msgid, context, plural, refs
## and the "max N chars" limit): a cheap stand-in for build_catalog() where a
## full scan is too heavy, such as the in-game dev report.
static func entries_from_pot(path: String = POT_PATH) -> Array[CatalogEntry]:
	var out: Array[CatalogEntry] = []
	var re := RegEx.create_from_string("max (\\d+) chars")
	for e: Dictionary in PoFile.load_file(path).entries:
		if e.get("obsolete", false) or e["msgid"] == "":
			continue
		var c := CatalogEntry.new()
		c.ctx = e["ctx"]
		c.msgid = e["msgid"]
		c.msgid_plural = e["msgid_plural"]
		c.refs = e["refs"]
		for line: String in e["extracted"]:
			var m := re.search(line)
			if m != null:
				c.max_chars = m.get_string(1).to_int()
		out.append(c)
	return out


static func _po_entry(c: CatalogEntry, comments: bool) -> Dictionary:
	var e := PoFile.new_entry(c.ctx, c.msgid, c.msgid_plural)
	if comments:
		e["extracted"] = extracted_comments(c)
	var refs := c.refs.duplicate()
	refs.sort()
	e["refs"] = refs
	return e


## The "#." lines of an entry: every location key, the class/speaker notes,
## then the length limit and placeholders.
static func extracted_comments(c: CatalogEntry) -> PackedStringArray:
	var out := PackedStringArray()
	var keys := c.keys.duplicate()
	keys.sort()
	for k in keys:
		out.append("key: " + k)
	var notes := c.notes.duplicate()
	notes.sort()
	for n in notes:
		if n != "":
			out.append(n)
	var meta := PackedStringArray()
	if c.max_chars > 0:
		meta.append("max %d chars" % c.max_chars)
	var ph := CatalogEntry.placeholder_set(c.msgid + " " + c.msgid_plural)
	var uniq := PackedStringArray()
	for p in ph:
		if not uniq.has(p):
			uniq.append(p)
	if not uniq.is_empty():
		meta.append("placeholders: " + " ".join(uniq))
	if not meta.is_empty():
		out.append(" · ".join(meta))
	return out


# --- Merge (translator files) --------------------------------------------------

## msgmerge-like and pure: same (ctx, msgid) keeps its translation; a new
## entry at a location key whose old English vanished carries that
## translation marked fuzzy (Godot skips fuzzy entries, so the player sees
## English until a translator confirms); vanished translations that nothing
## re-matched are kept as obsolete #~ entries at the end.
static func merge(po: PoFile, entries: Array[CatalogEntry]) -> PoFile:
	var out := PoFile.new()
	out.header_comments = po.header_comments.duplicate()
	out.header = po.header.duplicate()
	var nplurals := plural_count(po.header_value("Plural-Forms"))
	var catalog_ids := {}
	for c in entries:
		catalog_ids[c.id()] = true
	var live := {}
	var by_key := {}
	for e in po.entries:
		if bool(e["obsolete"]):
			continue
		var id := CatalogEntry.key_of(str(e["ctx"]), str(e["msgid"]))
		live[id] = e
		if catalog_ids.has(id):
			continue
		for x: String in e["extracted"]:
			if x.begins_with("key: "):
				by_key[x.substr(5)] = e
	var used := {}
	for c in entries:
		var n := _po_entry(c, true)
		var old: Dictionary = live.get(c.id(), {})
		if not old.is_empty():
			_copy_translation(old, n)
			used[c.id()] = true
		else:
			var carried: Dictionary = {}
			var keys := c.keys.duplicate()
			keys.sort()
			for k in keys:
				if by_key.has(k):
					carried = by_key[k]
					break
			var carried_id := CatalogEntry.key_of(str(carried.get("ctx", "")), str(carried.get("msgid", "")))
			if not carried.is_empty() and not used.has(carried_id):
				_copy_translation(carried, n)
				if PoFile.is_translated(n) and not (n["flags"] as PackedStringArray).has("fuzzy"):
					PoFile.push(n, "flags", "fuzzy")
				used[carried_id] = true
			elif c.msgid_plural != "":
				var empty := PackedStringArray()
				for i in nplurals:
					empty.append("")
				n["msgstr_plural"] = empty
		out.entries.append(n)
	for e in po.entries:
		var id := CatalogEntry.key_of(str(e["ctx"]), str(e["msgid"]))
		if bool(e["obsolete"]):
			out.entries.append(e)
		elif not catalog_ids.has(id) and not used.has(id) and PoFile.is_translated(e):
			var o := e.duplicate(true)
			o["obsolete"] = true
			o["extracted"] = PackedStringArray()
			o["refs"] = PackedStringArray()
			out.entries.append(o)
	return out


static func _copy_translation(from: Dictionary, to: Dictionary) -> void:
	to["msgstr"] = str(from["msgstr"])
	to["msgstr_plural"] = (from["msgstr_plural"] as PackedStringArray).duplicate()
	to["translator"] = (from["translator"] as PackedStringArray).duplicate()
	to["flags"] = (from["flags"] as PackedStringArray).duplicate()


static func plural_count(forms: String) -> int:
	var rx := RegEx.create_from_string("nplurals\\s*=\\s*([0-9]+)")
	var m := rx.search(forms)
	return maxi(1, m.get_string(1).to_int()) if m else 2


## A new translator file for `code`: the POT header with its Language and
## Plural-Forms (from the LocaleTable row when there is one).
static func new_locale_file(code: String) -> PoFile:
	var po := PoFile.new()
	po.header_comments = PackedStringArray(["REDLINE translation: %s. Update with ExtractStrings --merge; translate msgstr only." % code])
	po.header = PackedStringArray(POT_HEADER)
	po.set_header_value("Language", code)
	var row := LocaleTable.shared().by_code(code)
	po.set_header_value("Plural-Forms", row.plural_forms if row else DEFAULT_PLURAL_FORMS)
	return po


# --- Stats ---------------------------------------------------------------------

## One row per locale/*.po: {locale, entries, translated, fuzzy, missing, over}.
static func stats(entries: Array[CatalogEntry], cfg: L10nConfig = null) -> Array[Dictionary]:
	var c := cfg if cfg != null else L10nConfig.shared()
	var rows: Array[Dictionary] = []
	for path in DataDir.list_files(LocaleTable.CATALOG_DIR, "po"):
		var po := PoFile.load_file(path)
		var r := {"locale": path.get_file().get_basename(), "entries": entries.size(), "translated": 0, "fuzzy": 0,
			"missing": 0, "over": 0}
		for e in entries:
			var t := po.find(e.ctx, e.msgid)
			if t.is_empty() or not PoFile.is_translated(t):
				r["missing"] += 1
				continue
			if PoFile.is_fuzzy(t):
				r["fuzzy"] += 1
				continue
			r["translated"] += 1
			if e.max_chars > 0:
				for form in PoFile.forms(t):
					if form.length() > e.max_chars * c.over_length_warn_ratio:
						r["over"] += 1
						break
		rows.append(r)
	return rows


static func stats_table(rows: Array[Dictionary]) -> String:
	var md := PackedStringArray(["| locale | entries | translated | fuzzy | missing | over-length |", "|---|---|---|---|---|---|"])
	for r in rows:
		md.append("| %s | %d | %d | %d | %d | %d |" % [r["locale"], r["entries"], r["translated"], r["fuzzy"], r["missing"], r["over"]])
	return "\n".join(md)


# --- CLI -----------------------------------------------------------------------

func _run(args: PackedStringArray) -> int:
	var cfg := L10nConfig.shared()
	if args.has("--write"):
		var entries := build_catalog(cfg)
		if _write(POT_PATH, render_pot(entries)) != OK or _write(PSEUDO_PATH, render_pseudo(entries, cfg)) != OK:
			return 1
		print("ExtractStrings: wrote %d entries to %s and %s" % [entries.size(), POT_PATH, PSEUDO_PATH])
		return 0
	if args.has("--check"):
		var entries := build_catalog(cfg)
		var code := 0
		for pair: Array in [[POT_PATH, render_pot(entries)], [PSEUDO_PATH, render_pseudo(entries, cfg)]]:
			var diff := first_difference(FileAccess.get_file_as_string(pair[0]) if FileAccess.file_exists(pair[0]) else "", pair[1])
			if diff != "":
				printerr("ExtractStrings --check: %s is out of date (%s). Run ExtractStrings -- --write." % [pair[0], diff])
				code = 1
		var lint := StringRules.lint(cfg, entries)
		for w: String in lint["warnings"]:
			print("WARN " + w)
		for e: String in lint["errors"]:
			printerr("ERROR " + e)
			code = 1
		print("ExtractStrings --check: %d entries, %d lint errors, %d warnings -> %s" % [entries.size(),
			(lint["errors"] as PackedStringArray).size(), (lint["warnings"] as PackedStringArray).size(), "FAIL" if code else "OK"])
		return code
	if args.has("--merge"):
		for a in args:
			if a.begins_with("--new"):
				var bad := new_code_error(a.trim_prefix("--new").trim_prefix("="))
				if bad != "":
					printerr("ExtractStrings: " + bad)
					return 1
		var entries := build_catalog(cfg)
		for a in args:
			if a.begins_with("--new="):
				var code := a.trim_prefix("--new=")
				var path := "%s/%s.po" % [LocaleTable.CATALOG_DIR, code]
				if FileAccess.file_exists(path):
					printerr("ExtractStrings: %s already exists" % path)
					return 1
				if _write(path, new_locale_file(code).render()) != OK:
					return 1
		var failed := false
		for path in DataDir.list_files(LocaleTable.CATALOG_DIR, "po"):
			if path == PSEUDO_PATH:
				continue
			var merged := merge(PoFile.load_file(path), entries)
			if _write(path, merged.render()) != OK:
				failed = true
				continue
			print("ExtractStrings: merged %s" % path)
		return 1 if failed else 0
	if args.has("--stats"):
		print(stats_table(stats(build_catalog(cfg), cfg)))
		return 0
	print("usage: godot --headless res://devtools/l10n/ExtractStrings.tscn -- --write | --check | --merge [--new=<code>] | --stats")
	return 2


## "" when equal, else where the first differing line is.
static func first_difference(a: String, b: String) -> String:
	if a == b:
		return ""
	var la := a.split("\n")
	var lb := b.split("\n")
	for i in mini(la.size(), lb.size()):
		if la[i] != lb[i]:
			return "line %d: '%s' vs generated '%s'" % [i + 1, la[i].left(80), lb[i].left(80)]
	return "length differs (%d vs generated %d lines)" % [la.size(), lb.size()]


static func _write(path: String, text: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("ExtractStrings: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return FAILED
	f.store_string(text)
	var err := f.get_error()
	f.close()
	if err != OK:
		printerr("ExtractStrings: write failed for %s (%s)" % [path, error_string(err)])
	return err


## A --new=<code> value is usable: non-empty, a locale-code shape, not the
## source language or the pseudo-locale, and a row in the locale table.
static func new_code_error(code: String) -> String:
	if code == "":
		return "--new needs a locale code, e.g. --new=fr"
	if not RegEx.create_from_string("^[a-z]{2,3}(_[A-Z]{2}|_[A-Za-z]{4})?$").search(code):
		return "'%s' is not a locale code (expected e.g. fr, pt_BR)" % code
	if code == Loc.SOURCE_LOCALE or code == PSEUDO_CODE:
		return "'%s' is not a translatable locale" % code
	if LocaleTable.shared().by_code(code) == null:
		return "'%s' has no row in %s; add the LocaleInfo row first" % [code, LocaleTable.PATH]
	return ""
