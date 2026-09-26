class_name LocaleDevActions
extends RefCounted
## Dev helpers for localization (M9 D5 §12.3), used by the DevConsole Locale
## page and tests. Every change is session only: Settings never saves a
## locale chosen here, so a developer's pseudo-locale never becomes the
## player's language (and TestRunner/CaptureTour pin English anyway).


## Every enabled locale row with a loaded catalog (dev-only rows included),
## the source language first.
static func locales() -> PackedStringArray:
	if Loc.loaded_catalogs().is_empty():
		Loc.load_catalogs()
	var loaded := Loc.loaded_catalogs()
	var out := PackedStringArray([Loc.SOURCE_LOCALE])
	for row in LocaleTable.shared().rows:
		if row != null and row.enabled and loaded.has(row.code) and not out.has(row.code):
			out.append(row.code)
	return out


static func set_locale(code: String) -> String:
	return Loc.set_locale(code)


## The next locale after the current one (wraps), applied.
static func cycle_locale() -> String:
	var list := locales()
	var i := list.find(Loc.locale())
	return Loc.set_locale(list[(i + 1) % list.size()])


static func toggle_flag_missing() -> bool:
	Loc.flag_missing = not Loc.flag_missing
	return Loc.flag_missing


## The catalog report, built once from the checked-in POT (no repo scan and
## no code lint, so nothing is loaded or instanced inside a live session):
## "summary" fits the console's detail line, "report" is the --stats table
## for stdout. The full lints run in ValidateContent and ExtractStrings --check.
static func catalog_report() -> Dictionary:
	var cfg := L10nConfig.shared()
	var entries := ExtractStrings.entries_from_pot()
	var rows := ExtractStrings.stats(entries, cfg)
	var parts := PackedStringArray()
	for row: Dictionary in rows:
		parts.append("%s %d/%d (fuzzy %d)" % [row["locale"], row["translated"], row["entries"], row["fuzzy"]])
	var summary := "%d entries · %s" % [entries.size(), " · ".join(parts) if not parts.is_empty() else "no catalogs"]
	var report := "%s\n%d entries in %s (checked in). Lints: ExtractStrings -- --check" % [
		ExtractStrings.stats_table(rows), entries.size(), ExtractStrings.POT_PATH]
	return {"summary": summary, "report": report}
