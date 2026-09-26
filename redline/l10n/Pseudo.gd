class_name Pseudo
extends RefCounted
## The generated pseudo-locale en_XA (M9 D5 §7, D-163): accented, about 35-50 %
## longer and bracketed, so a capture shows at a glance which text is not
## routed through Loc (plain ASCII), what gets clipped (a missing bracket) and
## what does not fit (expansion). Godot's built-in pseudolocalization is not
## used: it mangles {named} placeholders. Deterministic, so en_XA.po is
## byte-stable for ExtractStrings --check.

## Spans copied verbatim: {named} placeholders, printf specs and BBCode tags.
const PROTECTED := "\\{[a-z_][a-z0-9_]*\\}|%[-+ 0#]*[0-9]*(?:\\.[0-9]+)?[sdfxXcoe%]|\\[/?[a-z_]+[^\\]]*\\]"

static var _rx: RegEx


static func pseudo(text: String, cfg: L10nConfig = null) -> String:
	if text == "":
		return ""
	var c := cfg if cfg != null else L10nConfig.shared()
	var lines := text.split("\n")
	var out := PackedStringArray()
	for line in lines:
		var mapped := _map_line(line, c)
		var visible := visible_length(line)
		if visible > 0:
			var ratio := c.pseudo_ratio_short if visible <= c.pseudo_short_len else c.pseudo_ratio_long
			var pad := maxi(c.pseudo_min_pad, ceili(visible * ratio))
			mapped += c.pseudo_pad_char.repeat(pad)
		out.append(mapped)
	return c.pseudo_prefix + "\n".join(out) + c.pseudo_suffix


## Characters a reader sees, placeholders and tags excluded.
static func visible_length(text: String) -> int:
	var n := text.length()
	for m in _regex().search_all(text):
		n -= m.get_string().length()
	return n


static func _map_line(line: String, c: L10nConfig) -> String:
	var out := ""
	var pos := 0
	for m in _regex().search_all(line):
		out += _map_letters(line.substr(pos, m.get_start() - pos), c)
		out += m.get_string()
		pos = m.get_end()
	out += _map_letters(line.substr(pos), c)
	return out


static func _map_letters(s: String, c: L10nConfig) -> String:
	var out := ""
	for i in s.length():
		var ch := s[i]
		out += str(c.pseudo_map.get(ch, ch))
	return out


static func _regex() -> RegEx:
	if _rx == null:
		_rx = RegEx.create_from_string(PROTECTED)
	return _rx


## Glyphs of `text` that no font in the chain has (the default font plus the
## locale's bundled fallbacks; system fonts never count: the Web build has
## none). Each missing glyph is listed once, in order of appearance.
## T13 swaps the base to UiTheme.font() when the locale font chain lands.
static func missing_glyphs(text: String, info: LocaleInfo = null) -> String:
	var chain: Array[Font] = [ThemeDB.fallback_font]
	if info != null:
		for p in info.font_paths:
			if ResourceLoader.exists(p):
				var fnt := load(p) as Font
				if fnt:
					chain.append(fnt)
	var out := ""
	for i in text.length():
		var ch := text[i]
		var cp := text.unicode_at(i)
		if cp < 32 or out.contains(ch):
			continue
		if not chain.any(func(fnt: Font) -> bool: return fnt != null and fnt.has_char(cp)):
			out += ch
	return out
