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


## Short enough for the console's detail line: coverage per catalog and the
## string-lint totals.
static func l10n_summary() -> String:
	var cfg := L10nConfig.shared()
	var entries := ExtractStrings.build_catalog(cfg)
	var parts := PackedStringArray()
	for row: Dictionary in ExtractStrings.stats(entries, cfg):
		parts.append("%s %d/%d (fuzzy %d)" % [row["locale"], row["translated"], row["entries"], row["fuzzy"]])
	var r := StringRules.lint(cfg, entries)
	return "%s · lint %d errors, %d warnings" % [" · ".join(parts) if not parts.is_empty() else "no catalogs",
		(r["errors"] as PackedStringArray).size(), (r["warnings"] as PackedStringArray).size()]


## The --stats table plus the first 20 string-lint findings (L-*), for stdout.
static func l10n_report() -> String:
	var cfg := L10nConfig.shared()
	var entries := ExtractStrings.build_catalog(cfg)
	var lines := PackedStringArray([ExtractStrings.stats_table(ExtractStrings.stats(entries, cfg))])
	var r := StringRules.lint(cfg, entries)
	var findings: PackedStringArray = r["errors"] + r["warnings"]
	lines.append("%d entries · %d lint errors · %d warnings" % [entries.size(), (r["errors"] as PackedStringArray).size(),
		(r["warnings"] as PackedStringArray).size()])
	for i in mini(20, findings.size()):
		lines.append(findings[i])
	return "\n".join(lines)
