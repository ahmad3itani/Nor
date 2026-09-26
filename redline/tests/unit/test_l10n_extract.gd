extends RedlineTestCase
## M9 D5 extractor (T06): code scan, the LOC_FIELDS resource walk, the scene
## scan without instancing, dedupe, deterministic rendering, the catalog
## gate (ENFORCE-gated, R06.2) and msgmerge-like merging.

const FIX := "res://tests/fixtures/l10n"


func _find(entries: Array, msgid: String, ctx: String = "") -> CatalogEntry:
	for e: CatalogEntry in entries:
		if e.msgid == msgid and e.ctx == ctx:
			return e
	return null


func test_code_strings_parses_calls() -> void:
	var src := FileAccess.get_file_as_string(FIX + "/code_fixture.txt")
	var got := ExtractStrings.code_strings(src, FIX + "/code_fixture.txt")
	var ids := got.map(func(s: Dictionary) -> String: return "%s|%s|%s|%s" % [s["kind"], s["ctx"], s["msgid"], s["plural"]])
	var want := [
		"tag||Small|", "tag||Large|", "tag|size|Skip|",
		"t||A b|", "t|toggle|On|", "f||x {n} of {m}|", "tn||s {n}|p {n}",
		"t||Say \"hi\"\nnow|", "upper|banner|Boss (phase 2)|", "f|chat|{who} says {what}|",
	]
	check(ids == want, "entries in source order:\n%s\nwant\n%s" % [ids, want])
	var f: Dictionary = got[5]
	check(f["has_arg_dict"] and Array(f["arg_keys"]) == ["n", "m"], "Loc.f literal arg keys: %s" % [f["arg_keys"]])
	check(int(got[3]["line"]) == 10, "line numbers are 1-based source lines (%d)" % int(got[3]["line"]))
	check(not ids.any(func(s: String) -> bool: return s.contains("commented") or s.contains("inside a string") or s.contains("R E D")),
		"comments, strings and ignore-marked lines are not calls")


func _res(path: String) -> Resource:
	return (load(FIX + "/" + path) as GDScript).new()


func test_walk_resource_recurses() -> void:
	var seq := _res("fixture_seq.gd")
	var line := _res("fixture_line.gd")
	line.set("speaker_id", "pa")
	line.set("text", "Hello there")
	var card := _res("fixture_card.gd")
	card.set("text", "ACT ONE")
	card.set("subtitle", "The Undercity")
	var choice := _res("fixture_choice.gd")
	choice.set("label", "Ask")
	var reply := _res("fixture_line.gd")
	reply.set("text", "An answer")
	var replies: Array[Resource] = [reply]
	choice.set("reply", replies)
	seq.set("id", "not_text")
	var steps: Array[Resource] = [line, card]
	seq.set("steps", steps)
	var choices: Array[Resource] = [choice]
	seq.set("choices", choices)
	seq.set("names", {"uc": "Undercity"})
	seq.set("labels", PackedStringArray(["One", ""]))
	var out := {}
	LocFields.walk(seq, "data/fx.tres", out)
	var entries := ExtractStrings.entries_of(out)
	var keys := {}
	for e in entries:
		for k in e.keys:
			keys[k] = e.msgid
	check(keys.get("data/fx.tres::steps[0].text") == "Hello there", "nested step: %s" % [keys])
	check(keys.get("data/fx.tres::steps[1].text") == "ACT ONE", "inherited LOC_FIELDS on a subclass")
	check(keys.get("data/fx.tres::steps[1].subtitle") == "The Undercity", "LOC_FIELDS_EXTRA")
	check(keys.get("data/fx.tres::choices[0].label") == "Ask", "choice label")
	check(keys.get("data/fx.tres::choices[0].reply[0].text") == "An answer", "reply inside a choice")
	check(keys.get("data/fx.tres::names[uc]") == "Undercity", "dictionary values")
	check(keys.get("data/fx.tres::labels[0]") == "One" and not keys.has("data/fx.tres::labels[1]"), "array items, empties skipped")
	check(not keys.values().has("not_text") and not keys.values().has("pa"), "exempt and undeclared fields are not extracted")
	var hello := _find(entries, "Hello there")
	check(hello.max_chars == 20 and hello.notes.has("fixture_line · speaker: pa"), "limit and notes: %s %s" % [hello.max_chars, hello.notes])
	check(_find(entries, "The Undercity", "card") != null, "LOC_CONTEXT becomes msgctxt")


func test_scene_state_scan_without_instancing() -> void:
	var hint: GDScript = load(FIX + "/fixture_hint.gd")
	hint.set("ready_count", 0)
	var out := {}
	ExtractStrings.scan_scenes(PackedStringArray([FIX]), out)
	var entries := ExtractStrings.entries_of(out)
	var scene := "tests/fixtures/l10n/l10n_scene.tscn"
	var h := _find(entries, "Scene hint {action}")
	check(h != null and h.keys.has(scene + "::Hint.text") and h.max_chars == 110, "the scene override is extracted")
	var decor := _find(entries, "Mind the gap")
	check(decor != null and decor.keys.has(scene + "::Decor.text"), "a decor Label (engine fields)")
	var zone := _find(entries, "Zone default hint")
	check(zone != null and zone.keys == PackedStringArray(["tests/fixtures/l10n/fixture_zone.gd::first_entry_hint"]),
		"a script default is extracted once, at the script: %s" % [zone.keys if zone else "missing"])
	check(_find(entries, "fixture_scene") == null, "exempt hint_id is not extracted")
	check(int(hint.get("ready_count")) == 0, "the scene was never instanced")


func test_dedupe_merges_refs() -> void:
	var out := {}
	LocFields.add(out, "Same text", "", "b.tres", "b.tres::title", 40, "B")
	LocFields.add(out, "Same text", "", "a.tres", "a.tres::name", 20, "A")
	LocFields.add(out, "Same text", "verb", "a.tres", "a.tres::verb", 0, "A")
	var entries := ExtractStrings.entries_of(out)
	check(entries.size() == 2, "one entry per (ctx, msgid)")
	var e := _find(entries, "Same text")
	check(e.refs.size() == 2 and e.first_ref() == "a.tres" and e.max_chars == 20, "refs merged, max = min: %s %d" % [e.refs, e.max_chars])
	check(_find(entries, "Same text", "verb") != null, "a context splits entries")


func test_render_is_deterministic() -> void:
	var a := ExtractStrings.build_catalog()
	var b := ExtractStrings.build_catalog()
	check(not a.is_empty(), "the catalog has entries")
	check(ExtractStrings.render_pot(a) == ExtractStrings.render_pot(b), "POT stable")
	check(ExtractStrings.render_pseudo(a) == ExtractStrings.render_pseudo(b), "pseudo stable")
	check(not ExtractStrings.render_pot(a).contains("Creation-Date"), "no timestamps")


## The build gate once T13 migrates the strings and flips ENFORCE (R06.2).
func test_catalog_up_to_date() -> void:
	if not StringRules.ENFORCE:
		set_meta("skip_reason", "StringRules.ENFORCE is false until the T13 migration")
		return
	var entries := ExtractStrings.build_catalog()
	var pot := FileAccess.get_file_as_string(ExtractStrings.POT_PATH)
	var xa := FileAccess.get_file_as_string(ExtractStrings.PSEUDO_PATH)
	check(ExtractStrings.first_difference(pot, ExtractStrings.render_pot(entries)) == "", "redline.pot is current")
	check(ExtractStrings.first_difference(xa, ExtractStrings.render_pseudo(entries)) == "", "en_XA.po is current")


func _entry(msgid: String, key: String) -> CatalogEntry:
	var e := CatalogEntry.new()
	e.msgid = msgid
	e.add_location(key.get_slice("::", 0), key, 0, "", 0)
	return e


func test_new_locale_code_is_checked() -> void:
	check(ExtractStrings.new_code_error("") != "", "empty --new is rejected")
	check(ExtractStrings.new_code_error("../x") != "", "a path is not a code")
	check(ExtractStrings.new_code_error("en") != "" and ExtractStrings.new_code_error("en_XA") != "", "source and pseudo refused")
	check(ExtractStrings.new_code_error("fr").contains("no row"), "an unknown code needs a LocaleInfo row first")


func test_entries_from_pot_reads_the_catalog() -> void:
	var entries := ExtractStrings.entries_from_pot()
	check(not entries.is_empty(), "the checked-in POT has entries")
	check(entries.all(func(e: CatalogEntry) -> bool: return e.msgid != ""), "no header entry")
	var po := PoFile.parse(ExtractStrings.render_pot(entries))
	check(po.entries.size() == entries.size(), "round-trips the entry count")


func test_merge_carries_and_fuzzes() -> void:
	var po := PoFile.parse("\n".join([
		"msgid \"\"", "msgstr \"\"", "\"Language: fr\\n\"", "\"Plural-Forms: nplurals=2; plural=(n > 1);\\n\"", "",
		"#. key: data/d.tres::steps[0].text", "msgid \"Old line\"", "msgstr \"Vieille ligne\"", "",
		"#. key: data/d.tres::steps[1].text", "msgid \"Same line\"", "msgstr \"Même ligne\"", "",
		"#. key: data/d.tres::steps[9].text", "msgid \"Gone\"", "msgstr \"Parti\"", ""]))
	check(po.errors.is_empty() and po.entries.size() == 3, "fixture parses: %s" % [po.errors])
	var entries: Array[CatalogEntry] = [_entry("New line", "data/d.tres::steps[0].text"), _entry("Same line", "data/d.tres::steps[2].text"),
		_entry("Brand new", "data/d.tres::steps[3].text")]
	var merged := ExtractStrings.merge(po, entries)
	var carried := merged.find("", "New line")
	check(carried.get("msgstr") == "Vieille ligne" and PoFile.is_fuzzy(carried), "edited English: carried and fuzzy")
	var moved := merged.find("", "Same line")
	check(moved.get("msgstr") == "Même ligne" and not PoFile.is_fuzzy(moved), "moved key, same English: carried, not fuzzy")
	check(merged.find("", "Brand new").get("msgstr") == "", "new entry untranslated")
	check(merged.find("", "Old line").is_empty(), "the old English is not live")
	var text := merged.render()
	check(text.contains("#~ msgid \"Gone\"") and text.contains("#~ msgstr \"Parti\""), "vanished -> obsolete:\n%s" % text)
	check(not text.contains("#~ msgid \"Old line\""), "a carried entry is not also obsolete")
	check(merged.header_value("Language") == "fr" and merged.header_value("Plural-Forms").contains("n > 1"), "header kept")
	var again := PoFile.parse(text)
	check(again.errors.is_empty() and again.render() == text, "render -> parse -> render is stable")


func test_po_roundtrip_and_engine_load() -> void:
	var po := PoFile.new()
	po.header = PackedStringArray(ExtractStrings.POT_HEADER)
	po.set_header_value("Language", "en_XA")
	var multi := PoFile.new_entry("", "Line one\nLine \"two\"\tend")
	multi["msgstr"] = "[L1\nL2]"
	var plural := PoFile.new_entry("ctx", "{n} shard", "{n} shards")
	plural["msgstr_plural"] = PackedStringArray(["[{n} sh]", "[{n} shs]"])
	po.entries.append(multi)
	po.entries.append(plural)
	var text := po.render()
	var back := PoFile.parse(text)
	check(back.errors.is_empty(), "parses: %s" % [back.errors])
	check(back.find("", "Line one\nLine \"two\"\tend").get("msgstr") == "[L1\nL2]", "escapes and multi-line survive")
	check(back.find("ctx", "{n} shard").get("msgstr_plural") == PackedStringArray(["[{n} sh]", "[{n} shs]"]), "plural forms survive")
	var xa := load(ExtractStrings.PSEUDO_PATH) as Translation
	check(xa != null and xa.locale == "en_XA", "the engine loads the generated en_XA.po without import")
