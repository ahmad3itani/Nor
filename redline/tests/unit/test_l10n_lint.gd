extends RedlineTestCase
## M9 D5 string lints L-1..L-9 (T06, StringRules) on in-memory inputs, and
## the warn-mode contract until T13 flips ENFORCE.

const FIX := "res://tests/fixtures/l10n"


func _cfg() -> L10nConfig:
	return L10nConfig.shared()


func _po(lines: Array) -> PoFile:
	var head := ["msgid \"\"", "msgstr \"\"", "\"Language: fr\\n\"", ""]
	return PoFile.parse("\n".join(head + lines))


func _entry(msgid: String, max_chars: int = 0) -> CatalogEntry:
	var e := CatalogEntry.new()
	e.msgid = msgid
	e.add_location("x.tres", "x.tres::text", max_chars, "", 0)
	return e


func test_coverage_flags_unclassified_field() -> void:
	var rx := RegEx.create_from_string(_cfg().text_field_pattern)
	var bad := LocFields.unclassified(load(FIX + "/fixture_uncovered.gd"), rx)
	check(bad == PackedStringArray(["tooltip_text"]), "L-2 names the unclassified field: %s" % [bad])
	check(LocFields.unclassified(load(FIX + "/fixture_hint.gd"), rx).is_empty(), "declared fields pass")
	check(LocFields.unclassified(load(FIX + "/fixture_card.gd"), rx).is_empty(), "inherited declarations count")
	var msgs := StringRules.check_coverage(PackedStringArray([FIX + "/fixture_uncovered.gd"]), _cfg())
	check(msgs.size() == 1 and msgs[0].begins_with("[L-2]") and msgs[0].contains("tooltip_text"), "message: %s" % [msgs])


func test_literal_lint() -> void:
	var src := "\n".join([
		"func a() -> void:",
		"\tadd_button(\"Resume\", f)",
		"\tadd_button(Loc.t(\"Resume\"), f)",
		"\tadd_label(\"R E D L I N E\")  # l10n: ignore(brand)",
		"\t# l10n: ignore(brand)",
		"\tadd_label(\"R E D L I N E\")",
		"\tadd_button(\"LB\", f)",
		"\tadd_label(\"\")",
		"\tadd_label(\"—\")",
		"\tlabel.text = \"Hello there\"",
		"\tif label.text == \"Hello there\": pass",
		"\tdraw_string(font, pos, \"SCRAP %d\" % n)",
		"\tEventBus.hint_requested.emit(\"Find the lift\", 3.0)",
		"\t_add_label_helper(\"Not a sink\")",
		"\tadd_button(names[i], f)",
	])
	var msgs := StringRules.check_literals(src, "res://ui/menus/Fake.gd", _cfg())
	var lines := Array(msgs).map(func(m: String) -> int: return m.get_slice(":", 1).to_int())
	check(lines == [2, 10, 12, 13], "flagged lines: %s\n%s" % [lines, "\n".join(msgs)])
	check(msgs[0].begins_with("[L-3] ui/menus/Fake.gd:2:") and msgs[0].contains("Resume"), "message: %s" % msgs[0])
	check(StringRules.flaggable("Resume") and not StringRules.flaggable("LB") and not StringRules.flaggable("—")
		and not StringRules.flaggable(""), "allowed literals")


func test_placeholder_parity() -> void:
	var po := _po([
		"msgid \"Hello {name}\"", "msgstr \"Bonjour\"", "",
		"msgid \"{a} of {b}\"", "msgstr \"{b} sur {a}\"", "",
		"msgid \"%d left\"", "msgstr \"%s restant\"", "",
		"msgid \"{n} shard\"", "msgid_plural \"{n} shards\"", "msgstr[0] \"{n} éclat\"", "msgstr[1] \"éclats\"", "",
		"msgid \"Untranslated {x}\"", "msgstr \"\"", ""])
	var msgs := StringRules.check_po(po, "res://locale/fr.po")
	var l4 := Array(msgs).filter(func(m: String) -> bool: return m.begins_with("[L-4]"))
	check(l4.size() == 3, "missing {name}, %%d vs %%s and plural form 1: %s" % [l4])
	check(not l4.any(func(m: String) -> bool: return m.contains("of {b}")), "reordering is allowed")


func test_duplicate_po_entry() -> void:
	var po := _po(["msgid \"Back\"", "msgstr \"Retour\"", "", "msgid \"Back\"", "msgstr \"Arrière\"", "",
		"msgctxt \"nav\"", "msgid \"Back\"", "msgstr \"Retour\"", ""])
	var msgs := StringRules.check_po(po, "res://locale/fr.po")
	check(Array(msgs).filter(func(m: String) -> bool: return m.begins_with("[L-5]") and m.contains("twice")).size() == 1,
		"one duplicate (the context entry is distinct): %s" % [msgs])
	var wrong := StringRules.check_po(po, "res://locale/de.po")
	check(Array(wrong).any(func(m: String) -> bool: return m.contains("does not match the file name")), "Language header vs file")
	var broken := StringRules.check_po(PoFile.parse("msgid \"x\"\nmsgstr oops\n"), "res://locale/fr.po")
	check(Array(broken).any(func(m: String) -> bool: return m.begins_with("[L-5]") and m.contains("quoted")), "parse errors: %s" % [broken])
	for path in DataDir.list_files(LocaleTable.CATALOG_DIR, "po"):
		check(StringRules.check_po(PoFile.load_file(path), path).is_empty(), "%s is clean" % path)


func test_source_over_max() -> void:
	var entries: Array[CatalogEntry] = [_entry("Twelve chars", 10), _entry("Fits", 10), _entry("No limit at all here", 0)]
	var msgs := StringRules.check_source_limits(entries)
	check(msgs.size() == 1 and msgs[0].begins_with("[L-6]") and msgs[0].contains("Twelve chars"), "L-6: %s" % [msgs])


func test_named_placeholders_required() -> void:
	var entries: Array[CatalogEntry] = [_entry("%s of %d"), _entry("{a} of {b}"), _entry("%d%%"), _entry("%d left")]
	var msgs := StringRules.check_templates(entries)
	check(msgs.size() == 1 and msgs[0].begins_with("[L-9]") and msgs[0].contains("%s of %d"), "L-9 templates: %s" % [msgs])
	var src := "\n".join(["func a() -> void:", "\tLoc.f(\"x {a} {b}\", {\"a\": 1})", "\tLoc.f(\"y {a}\", {\"a\": 1})",
		"\tLoc.f(\"z {a}\", args)", "\tLoc.tn(\"{n} of {max}\", \"{n} of {max}\", 2, {\"max\": 3})"])
	var args := StringRules.check_format_args(src, "res://ui/Fake.gd")
	check(args.size() == 1 and args[0].contains("{b}") and args[0].contains("Fake.gd:2"), "L-9 args: %s" % [args])


func test_display_logic_warns() -> void:
	var src := "func a() -> void:\n\tif room.district_name == \"The Relay\":\n\t\tpass\n\tif id == \"relay\":\n\t\tpass\n"
	var msgs := StringRules.check_display_logic(src, "res://autoload/Fake.gd")
	check(msgs.size() == 1 and msgs[0].begins_with("[L-8] autoload/Fake.gd:2"), "L-8: %s" % [msgs])


func test_enforce_false_reports_warnings_only() -> void:
	check(not StringRules.ENFORCE, "T06 lands the lints in warn mode (T13 flips it)")
	check(not StringRules.level_is_error(StringRules.Level.ENFORCED), "enforced rules warn for now")
	check(StringRules.level_is_error(StringRules.Level.ERROR), "PO integrity is an error from the start")
	var r := StringRules.lint(_cfg(), ExtractStrings.build_catalog(), true)
	check((r["errors"] as PackedStringArray).is_empty(), "the repo has no string-lint errors: %s" % [r["errors"]])
	var warns := Array(r["warnings"])
	check(warns.any(func(w: String) -> bool: return w.begins_with("[L-3]")), "pre-migration literals are reported as warnings")
	check(warns.any(func(w: String) -> bool: return w.begins_with("[L-2]")), "unclassified pre-M9 fields are reported as warnings")
	# Catalog freshness (L-1) is not asserted here: until T13 regenerates the
	# catalog, later branches add Loc calls without --write (R06.2). The only
	# freshness gate is test_catalog_up_to_date, skipped while ENFORCE is off.
	var errs := Array(r["errors"])
	check(not errs.any(func(e: String) -> bool: return e.begins_with("[L-1]")), "a stale catalog is never an error in warn mode")


func test_module_quiet_outside_a_full_pass() -> void:
	var v := ContentValidator.new()
	StringRules.run(v)
	check(v.errors.is_empty() and v.warnings.is_empty(), "no repo-wide string lints on an empty validator: %s %s" % [v.errors, v.warnings])
	check(StringRules.report(v) == "", "no report section without a full pass")
