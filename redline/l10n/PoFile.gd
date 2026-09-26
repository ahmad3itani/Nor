class_name PoFile
extends RefCounted
## A minimal gettext PO/POT reader and writer (M9 D5 §5): header, comments,
## msgctxt, plurals, the fuzzy flag and obsolete (#~) entries. Output is
## byte-deterministic (no dates), so a generated catalog can be diffed and
## checked (ExtractStrings --check). Godot loads the same files itself
## (TranslationPO, no import step); this class exists for the tools.
##
## An entry is a Dictionary:
##   ctx, msgid, msgid_plural: String
##   msgstr: String                 (singular entries)
##   msgstr_plural: PackedStringArray (plural entries, one per form)
##   extracted: PackedStringArray   ("#." lines, without the marker)
##   refs: PackedStringArray        ("#:" paths)
##   flags: PackedStringArray       ("#," flags, e.g. "fuzzy")
##   translator: PackedStringArray  ("# " lines)
##   obsolete: bool                 ("#~" entries)

## Comment lines above the header entry ("# ..." without the "# ").
var header_comments: PackedStringArray = []
## The header msgstr split into "Key: value" lines (no trailing \n).
var header: PackedStringArray = []
var entries: Array[Dictionary] = []
## Parse problems ("line N: ...").
var errors: PackedStringArray = []


static func new_entry(ctx: String = "", msgid: String = "", msgid_plural: String = "") -> Dictionary:
	return {"ctx": ctx, "msgid": msgid, "msgid_plural": msgid_plural, "msgstr": "",
		"msgstr_plural": PackedStringArray(), "extracted": PackedStringArray(), "refs": PackedStringArray(),
		"flags": PackedStringArray(), "translator": PackedStringArray(), "obsolete": false}


## Appends to a PackedStringArray field of an entry. Packed arrays are values
## inside a Dictionary, so the field is written back.
static func push(e: Dictionary, key: String, value: String) -> void:
	var a: PackedStringArray = e[key]
	a.append(value)
	e[key] = a


static func load_file(path: String) -> PoFile:
	if not FileAccess.file_exists(path):
		var missing := PoFile.new()
		missing.errors.append("file not found: %s" % path)
		return missing
	return parse(FileAccess.get_file_as_string(path))


# --- Reading --------------------------------------------------------------------

static func parse(text: String) -> PoFile:
	var po := PoFile.new()
	var cur := new_entry()
	var has_cur := false
	# The keyword a bare continuation line ("...") appends to; "" between entries.
	var field := ""
	var lines := text.split("\n")
	for i in lines.size():
		var line := lines[i].strip_edges()
		var obsolete := false
		if line.begins_with("#~"):
			obsolete = true
			line = line.substr(2).strip_edges()
		if line == "":
			if has_cur:
				po._finish(cur)
				cur = new_entry()
				has_cur = false
			field = ""
			continue
		if not obsolete and line.begins_with("#"):
			if field != "":
				# A comment after a msgstr starts the next entry.
				po._finish(cur)
				cur = new_entry()
				has_cur = false
				field = ""
			if line.begins_with("#."):
				push(cur, "extracted", line.substr(2).strip_edges())
			elif line.begins_with("#:"):
				for r in line.substr(2).strip_edges().split(" ", false):
					push(cur, "refs", r)
			elif line.begins_with("#,"):
				for fl in line.substr(2).split(",", false):
					push(cur, "flags", fl.strip_edges())
			elif line.begins_with("#|"):
				pass  # previous-msgid lines are not kept
			elif po.header.is_empty() and po.entries.is_empty():
				po.header_comments.append(line.substr(2) if line.length() > 1 else "")
				continue
			else:
				push(cur, "translator", line.substr(2) if line.length() > 1 else "")
			has_cur = true
			continue
		var kw := field
		var rest := line
		if not line.begins_with("\""):
			var sp := line.find(" ")
			kw = line.substr(0, sp) if sp > 0 else line
			rest = line.substr(sp + 1).strip_edges() if sp > 0 else ""
			if not (kw in ["msgctxt", "msgid", "msgid_plural", "msgstr"] or kw.begins_with("msgstr[")):
				po.errors.append("line %d: unknown keyword '%s'" % [i + 1, kw])
				continue
			# A new msgctxt/msgid after a msgstr without a blank line: next entry.
			if (kw == "msgctxt" or kw == "msgid") and field.begins_with("msgstr"):
				po._finish(cur)
				cur = new_entry()
			field = kw
		if kw == "":
			po.errors.append("line %d: string with no keyword" % (i + 1))
			continue
		if rest.length() < 2 or not rest.begins_with("\"") or not rest.ends_with("\""):
			po.errors.append("line %d: badly quoted string" % (i + 1))
			continue
		has_cur = true
		cur["obsolete"] = obsolete
		var value := unquote(rest.substr(1, rest.length() - 2))
		match kw:
			"msgctxt", "msgid", "msgid_plural", "msgstr":
				var key := "ctx" if kw == "msgctxt" else kw
				cur[key] = str(cur[key]) + value
			_:
				var idx := kw.trim_prefix("msgstr[").trim_suffix("]").to_int()
				var forms: PackedStringArray = cur["msgstr_plural"]
				while forms.size() <= idx:
					forms.append("")
				forms[idx] = forms[idx] + value
				cur["msgstr_plural"] = forms
	if has_cur:
		po._finish(cur)
	return po


func _finish(e: Dictionary) -> void:
	if str(e["msgid"]) == "" and str(e["ctx"]) == "" and not bool(e["obsolete"]):
		# The header: the first entry with an empty msgid and no context.
		if header.is_empty() and entries.is_empty() and str(e["msgstr"]) != "":
			for l in str(e["msgstr"]).split("\n", false):
				header.append(l)
			return
		if str(e["msgstr"]) == "" and (e["msgstr_plural"] as PackedStringArray).is_empty():
			return  # stray comments with no entry
		errors.append("an entry has an empty msgid")
		return
	entries.append(e)


## GDScript-side unescape of a PO string body: \n \t \r \" \\ and \uXXXX.
static func unquote(s: String) -> String:
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
				"\"":
					out += "\""
				"\\":
					out += "\\"
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


static func quote(s: String) -> String:
	return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\t", "\\t").replace("\r", "\\r").replace("\n", "\\n") + "\""


# --- Queries --------------------------------------------------------------------

func header_value(key: String) -> String:
	for l in header:
		if l.begins_with(key + ":"):
			return l.substr(key.length() + 1).strip_edges()
	return ""


func set_header_value(key: String, value: String) -> void:
	for i in header.size():
		if header[i].begins_with(key + ":"):
			header[i] = "%s: %s" % [key, value]
			return
	header.append("%s: %s" % [key, value])


## The live (non-obsolete) entry for (ctx, msgid), or {}.
func find(ctx: String, msgid: String) -> Dictionary:
	for e in entries:
		if not bool(e["obsolete"]) and str(e["ctx"]) == ctx and str(e["msgid"]) == msgid:
			return e
	return {}


## "(ctx) msgid" of every live entry listed more than once (L-5).
func duplicates() -> PackedStringArray:
	var seen := {}
	var out := PackedStringArray()
	for e in entries:
		if bool(e["obsolete"]):
			continue
		var k := CatalogEntry.key_of(str(e["ctx"]), str(e["msgid"]))
		if seen.has(k) and not out.has(_label(e)):
			out.append(_label(e))
		seen[k] = true
	return out


static func is_fuzzy(e: Dictionary) -> bool:
	return (e["flags"] as PackedStringArray).has("fuzzy")


## Every translated form (empty = untranslated).
static func forms(e: Dictionary) -> PackedStringArray:
	if str(e["msgid_plural"]) != "":
		return e["msgstr_plural"]
	return PackedStringArray([str(e["msgstr"])])


static func is_translated(e: Dictionary) -> bool:
	var fs := forms(e)
	if fs.is_empty():
		return false
	for f in fs:
		if f == "":
			return false
	return true


static func _label(e: Dictionary) -> String:
	var c := str(e["ctx"])
	return ("(%s) " % c if c != "" else "") + "\"%s\"" % str(e["msgid"]).c_escape()


# --- Writing --------------------------------------------------------------------

func render() -> String:
	var out := PackedStringArray()
	for c in header_comments:
		out.append(("# " + c).strip_edges(false, true))
	out.append("msgid \"\"")
	out.append("msgstr \"\"")
	for h in header:
		out.append(quote(h + "\n"))
	for e in entries:
		if bool(e["obsolete"]):
			continue
		out.append("")
		_render_entry(e, out, "")
	for e in entries:
		if not bool(e["obsolete"]):
			continue
		out.append("")
		_render_entry(e, out, "#~ ")
	return "\n".join(out) + "\n"


static func _render_entry(e: Dictionary, out: PackedStringArray, prefix: String) -> void:
	for c in e["translator"]:
		out.append(("# " + c).strip_edges(false, true))
	for c in e["extracted"]:
		out.append("#. " + c)
	var refs: PackedStringArray = e["refs"]
	if not refs.is_empty():
		out.append("#: " + " ".join(refs))
	var flags: PackedStringArray = e["flags"]
	if not flags.is_empty():
		out.append("#, " + ", ".join(flags))
	if str(e["ctx"]) != "":
		_render_string(prefix + "msgctxt", str(e["ctx"]), out, prefix)
	_render_string(prefix + "msgid", str(e["msgid"]), out, prefix)
	if str(e["msgid_plural"]) != "":
		_render_string(prefix + "msgid_plural", str(e["msgid_plural"]), out, prefix)
		var fs: PackedStringArray = e["msgstr_plural"]
		if fs.is_empty():
			fs = PackedStringArray(["", ""])
		for i in fs.size():
			_render_string(prefix + "msgstr[%d]" % i, fs[i], out, prefix)
	else:
		_render_string(prefix + "msgstr", str(e["msgstr"]), out, prefix)


## One keyword line; text with inner line breaks is split gettext-style
## (an empty first line, then one quoted line per \n-terminated segment).
static func _render_string(kw: String, s: String, out: PackedStringArray, prefix: String) -> void:
	var nl := s.find("\n")
	if nl < 0 or nl == s.length() - 1:
		out.append(kw + " " + quote(s))
		return
	out.append(kw + " \"\"")
	var parts := s.split("\n")
	for i in parts.size():
		var seg := parts[i] + ("\n" if i < parts.size() - 1 else "")
		if seg != "":
			out.append(prefix + quote(seg))
