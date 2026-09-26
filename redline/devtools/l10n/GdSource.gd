class_name GdSource
extends RefCounted
## A GDScript source file prepared for the string tools (M9 D5 §6, §9): the
## extractor finds Loc.* calls in it and the lints find literals that reach
## the screen. `masked` is the source with comments blanked and string
## contents replaced by "_" (quotes and line breaks kept), so parentheses,
## commas and keywords can be scanned without being fooled by text inside
## strings; `literals` maps each literal's opening-quote offset to its value.
## Tokenized with one regex pass (fast enough for the whole tree).

const TOKENS := "\"\"\"[\\s\\S]*?\"\"\"|'''[\\s\\S]*?'''|\"(?:[^\"\\\\\\n]|\\\\.)*\"|'(?:[^'\\\\\\n]|\\\\.)*'|#[^\\n]*"

var text: String = ""
var masked: String = ""
## opening-quote offset -> {"end": offset after the closing quote, "value": String, "triple": bool}
var literals: Dictionary = {}
## line index (0-based) -> the comment text on that line (with "#").
var comments: Dictionary = {}
var _line_starts: PackedInt32Array = []

static var _rx: RegEx
static var _nonl: RegEx


static func parse(source: String) -> GdSource:
	if _rx == null:
		_rx = RegEx.create_from_string(TOKENS)
		_nonl = RegEx.create_from_string("[^\\n]")
	var g := GdSource.new()
	g.text = source
	var starts := PackedInt32Array([0])
	var p := source.find("\n")
	while p >= 0:
		starts.append(p + 1)
		p = source.find("\n", p + 1)
	g._line_starts = starts
	var parts := PackedStringArray()
	var pos := 0
	for m in _rx.search_all(source):
		var s := m.get_start()
		var tok := m.get_string()
		parts.append(source.substr(pos, s - pos))
		if tok.begins_with("#"):
			g.comments[g.line_of(s)] = tok
			parts.append(" ".repeat(tok.length()))
		else:
			var triple := tok.begins_with("\"\"\"") or tok.begins_with("'''")
			var q := 3 if triple else 1
			var body := tok.substr(q, tok.length() - 2 * q)
			g.literals[s] = {"end": m.get_end(), "value": body if triple else unescape(body), "triple": triple}
			parts.append(tok.substr(0, q) + _nonl.sub(body, "_", true) + tok.substr(tok.length() - q))
		pos = m.get_end()
	parts.append(source.substr(pos))
	g.masked = "".join(parts)
	return g


## GDScript escapes: \n \t \r \" \' \\ and \uXXXX.
static func unescape(s: String) -> String:
	if not s.contains("\\"):
		return s
	var out := ""
	var i := 0
	while i < s.length():
		var ch := s[i]
		if ch == "\\" and i + 1 < s.length():
			var n := s[i + 1]
			match n:
				"n":
					out += "\n"
				"t":
					out += "\t"
				"r":
					out += "\r"
				"\"", "'", "\\":
					out += n
				"u":
					if i + 6 <= s.length() and s.substr(i + 2, 4).is_valid_hex_number():
						out += String.chr(s.substr(i + 2, 4).hex_to_int())
						i += 6
						continue
					out += "\\u"
				_:
					out += "\\" + n
			i += 2
			continue
		out += ch
		i += 1
	return out


## 0-based line of an offset.
func line_of(offset: int) -> int:
	var lo := 0
	var hi := _line_starts.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if _line_starts[mid] <= offset:
			lo = mid
		else:
			hi = mid - 1
	return lo


func line_text(line: int) -> String:
	if line < 0 or line >= _line_starts.size():
		return ""
	var s := _line_starts[line]
	var e := _line_starts[line + 1] - 1 if line + 1 < _line_starts.size() else text.length()
	return text.substr(s, e - s)


func comment_on(line: int) -> String:
	return str(comments.get(line, ""))


## Top-level argument spans [start, end) of the call whose "(" is at
## `open`, and the offset of its closing ")" as the last element's "close".
## Returns [] when the parenthesis never closes.
func call_args(open: int) -> Array:
	var spans: Array = []
	var depth := 0
	var start := open + 1
	var i := open + 1
	var n := masked.length()
	while i < n:
		var c := masked[i]
		if c == "\"" or c == "'":
			# Jump over a whole literal (its masked quotes are not brackets).
			var lit: Dictionary = literals.get(i, {})
			if not lit.is_empty():
				i = int(lit["end"])
				continue
		if c == "(" or c == "[" or c == "{":
			depth += 1
		elif c == ")" or c == "]" or c == "}":
			if depth == 0:
				if c == ")":
					if masked.substr(start, i - start).strip_edges() != "" or not spans.is_empty():
						spans.append([start, i])
					return spans
				return []
			depth -= 1
		elif c == "," and depth == 0:
			spans.append([start, i])
			start = i + 1
		i += 1
	return []


## The literal that spans exactly [start, end) after trimming, or {}.
func literal_exact(start: int, end: int) -> Dictionary:
	var s := skip_space(start, end)
	var lit: Dictionary = literals.get(s, {})
	if lit.is_empty():
		return {}
	if masked.substr(int(lit["end"]), end - int(lit["end"])).strip_edges() != "":
		return {}
	return lit


## The literal the expression in [start, end) begins with (a bare literal, a
## "..." % x format or a "..." + x concatenation), or {}.
func literal_leading(start: int, end: int) -> Dictionary:
	return literals.get(skip_space(start, end), {})


## Keys of a dictionary literal spanning [start, end) ({"a": 1, "b": x}):
## literals directly followed by ":" at the top level. Best effort.
func dict_keys(start: int, end: int) -> PackedStringArray:
	var out := PackedStringArray()
	var s := skip_space(start, end)
	if s >= end or masked[s] != "{":
		return out
	for off: int in literals:
		if off <= s or off >= end:
			continue
		var after := skip_space(int(literals[off]["end"]), end)
		if after < end and masked[after] == ":":
			out.append(str(literals[off]["value"]))
	return out


func skip_space(start: int, end: int) -> int:
	var i := start
	while i < end and masked[i] in [" ", "\t", "\n", "\r", "\\"]:
		i += 1
	return i
