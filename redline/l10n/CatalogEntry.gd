class_name CatalogEntry
extends RefCounted
## One translatable string in the catalog (M9 D5 §5): the lookup identity is
## (ctx, msgid); refs, location keys and notes are for translators, tools and
## fuzzy matching, never for lookup.

## Named {placeholders} and printf-style % specs (both are protected by the
## pseudo-locale and must survive every translation, L-4).
const PLACEHOLDER_PATTERN := "\\{[a-z_][a-z0-9_]*\\}|%[-+ 0#]*[0-9]*(?:\\.[0-9]+)?[sdfxXcoe%]"

var ctx: String = ""
var msgid: String = ""
var msgid_plural: String = ""
## Source files without "res://", sorted on output.
var refs: PackedStringArray = []
## Stable location keys ("data/sequences/x.tres::steps[3].text").
var keys: PackedStringArray = []
## Owning class, speaker and similar notes for translators.
var notes: PackedStringArray = []
## Smallest non-zero LOC_FIELDS max across locations (0 = no limit).
var max_chars: int = 0
## ref -> the scan order of the first time this entry was seen in that file
## (catalog order: by first ref, then order of appearance).
var first_seen: Dictionary = {}

static var _rx: RegEx


func id() -> String:
	return key_of(ctx, msgid)


static func key_of(c: String, m: String) -> String:
	return c + "\u0004" + m


## Every placeholder in `text`, in order (a multiset: repeats kept).
static func placeholders(text: String) -> PackedStringArray:
	if _rx == null:
		_rx = RegEx.create_from_string(PLACEHOLDER_PATTERN)
	var out := PackedStringArray()
	for m in _rx.search_all(text):
		out.append(m.get_string())
	return out


## Placeholders without the literal "%%" escape, sorted (for parity checks).
static func placeholder_set(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for p in placeholders(text):
		if p != "%%":
			out.append(p)
	out.sort()
	return out


## Adds a location. max 0 means "no limit" and never lowers a real limit.
func add_location(ref: String, key: String, max_len: int, note: String, seq: int) -> void:
	if not refs.has(ref):
		refs.append(ref)
		first_seen[ref] = seq
	if key != "" and not keys.has(key):
		keys.append(key)
	if note != "" and not notes.has(note):
		notes.append(note)
	if max_len > 0 and (max_chars == 0 or max_len < max_chars):
		max_chars = max_len


## Sort key for the catalog: the smallest ref, then its first appearance.
func first_ref() -> String:
	var r := refs.duplicate()
	r.sort()
	return r[0] if not r.is_empty() else ""


func order() -> int:
	return int(first_seen.get(first_ref(), 0))


static func sort_entries(entries: Array[CatalogEntry]) -> void:
	entries.sort_custom(func(a: CatalogEntry, b: CatalogEntry) -> bool:
		var ra := a.first_ref()
		var rb := b.first_ref()
		if ra != rb:
			return ra < rb
		if a.order() != b.order():
			return a.order() < b.order()
		return a.id() < b.id())
