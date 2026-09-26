extends RefCounted
## DevConsole "Locale…" page (M9 D5 §12.3), built by DevConsole._m9_page_script.
## Rows: cycle the display language (session only), mark untranslated text
## as ‹…›, a catalog report, and back to English. The console itself stays
## English (dev tooling is never translated, D-163). No Godot built-in
## pseudolocalization rows: the generated en_XA replaces them.


static func build(c: DevConsole) -> void:
	var list := LocaleDevActions.locales()
	var shown := PackedStringArray()
	for code in list:
		shown.append(("[%s]" % code) if code == Loc.locale() else code)
	c.add_button("Locale: %s" % " ▸ ".join(shown), func() -> void:
		LocaleDevActions.cycle_locale()
		_refresh(c))
	c.add_button("Mark untranslated ‹›: %s" % ("On" if Loc.flag_missing else "Off"), func() -> void:
		LocaleDevActions.toggle_flag_missing()
		_refresh(c))
	c.add_button("Catalog report", func() -> void:
		var r := LocaleDevActions.catalog_report()
		print(r["report"])
		c.set_detail(r["summary"]))
	c.add_button("Reset to en", func() -> void:
		Loc.flag_missing = false
		LocaleDevActions.set_locale(Loc.SOURCE_LOCALE)
		_refresh(c))


static func _refresh(c: DevConsole) -> void:
	var i := c.focused_index()
	c.rebuild()
	c.focus_index(i)
