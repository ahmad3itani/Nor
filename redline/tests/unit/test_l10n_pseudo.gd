extends RedlineTestCase
## M9 D5 pseudo-locale en_XA (T06): protected placeholders, expansion,
## font-safe glyphs and a full generated catalog.


func test_placeholders_protected() -> void:
	var src := "Press {action} for %d at %.1f and 100%% [b]bold[/b] {n}"
	var p := Pseudo.pseudo(src)
	for token in ["{action}", "%d", "%.1f", "%%", "[b]", "[/b]", "{n}"]:
		check(p.contains(token), "%s survives: %s" % [token, p])
	check(not p.contains("Press") and p.contains("Ṕŕéšš") == false and p.contains("Pŕéšš"), "letters are mapped (p is kept): %s" % p)
	check(p.begins_with("[") and p.ends_with("]"), "bracketed")


func test_expansion_ratio() -> void:
	var long := "Recovered the lost relay keys"
	var short := "Talk"
	check(Pseudo.pseudo(long).length() >= ceili(long.length() * 1.35), "long strings grow >= 35%%: %s" % Pseudo.pseudo(long))
	check(Pseudo.pseudo(short).length() >= ceili(short.length() * 1.5), "short strings grow >= 50%%: %s" % Pseudo.pseudo(short))
	check(Pseudo.pseudo("Talk") == "[Ťáĺķ~~]", "the documented example: %s" % Pseudo.pseudo("Talk"))
	check(Pseudo.pseudo("") == "", "empty stays empty")
	var multi := Pseudo.pseudo("First line\nSecond")
	check(multi.begins_with("[") and multi.ends_with("]") and multi.count("[") == 1 and multi.contains("\n"),
		"one bracket pair around every line: %s" % multi)
	check(Pseudo.pseudo(long) == Pseudo.pseudo(long), "deterministic")


func test_pseudo_glyphs_in_font() -> void:
	var letters := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var p := Pseudo.pseudo(letters)
	check(Pseudo.missing_glyphs(p) == "", "every pseudo glyph is in the default font: missing '%s'" % Pseudo.missing_glyphs(p))
	check(Pseudo.missing_glyphs("‹›") == "", "the untranslated marks render too")
	check(Pseudo.missing_glyphs("日本") == "日本", "the check does find missing glyphs")


func test_every_msgid_has_pseudo() -> void:
	var pot := PoFile.load_file(ExtractStrings.POT_PATH)
	var xa := PoFile.load_file(ExtractStrings.PSEUDO_PATH)
	check(pot.errors.is_empty() and xa.errors.is_empty(), "both parse: %s %s" % [pot.errors, xa.errors])
	check(not pot.entries.is_empty() and pot.entries.size() == xa.entries.size(), "same entry count")
	for e in pot.entries:
		var t := xa.find(str(e["ctx"]), str(e["msgid"]))
		check(not t.is_empty() and PoFile.is_translated(t), "en_XA has \"%s\"" % str(e["msgid"]).c_escape())
		if not t.is_empty():
			check(PoFile.forms(t)[0] == Pseudo.pseudo(str(e["msgid"])), "the msgstr is Pseudo.pseudo(msgid)")
	check(xa.header_value("Language") == "en_XA" and pot.header_value("Language") == "", "headers")
