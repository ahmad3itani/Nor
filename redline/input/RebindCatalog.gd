class_name RebindCatalog
extends Resource
## Which actions the player can rebind and the rules around them (D4 §4.1,
## data/input/rebind_catalog.tres). Menu keys (ui_*), cinematic_skip (a
## mirror) and debug_* are never listed, so Settings can always be reached
## (D-153) and a bad rebind can never lock the player out.

const PATH := "res://data/input/rebind_catalog.tres"
## Localization (D5): no player text here (labels live on RebindActionData;
## notices are worded in InputBindings through Loc).
const LOC_EXEMPT := ["allowed_overlaps", "mirrors", "reserved_pad", "reserved_soft", "web_locked_keys"]

@export var actions: Array[RebindActionData] = []
## Shipped overlaps that are intentional: {a, b, device: "key"|"pad"|"any",
## event: "" (any shared event) or one encoded event}.
@export var allowed_overlaps: Array[Dictionary] = []
## Actions rebuilt from others: {target, sources: [...], fixed_keys: [...],
## fixed_pad: [...]} (cinematic_skip = every jump event + Enter + pad A).
@export var mirrors: Array[Dictionary] = []
## Physical keycodes no action may take (Esc: pause lock and capture cancel;
## Backspace: ui_back and capture cancel, R03.17).
@export var reserved_keys: PackedInt32Array = []
## Encoded pad events no action may take ("b6" Start: pause lock, cancel).
@export var reserved_pad: PackedStringArray = []
## Fixed menu events a gameplay binding may share, with a neutral notice
## instead of a block (R03.14): {event: "k32", kind: "confirm"|"cancel"|"skip"}
## (InputBindings.soft_notice words it). The bind still happens; the notice
## only tells the player what else the key does.
@export var reserved_soft: Array[Dictionary] = []
## Extra key locks on web builds: {action, keys: [...]} (the browser eats Esc
## in fullscreen, so pause keeps P there, R03.6).
@export var web_locked_keys: Array[Dictionary] = []

static var _cache: RebindCatalog = null


static func get_catalog() -> RebindCatalog:
	if _cache == null:
		_cache = load(PATH) as RebindCatalog
	return _cache


static func clear_cache() -> void:
	_cache = null


func entry(action: StringName) -> RebindActionData:
	for a in actions:
		if a != null and a.action == action:
			return a
	return null


func has_action(action: StringName) -> bool:
	return entry(action) != null


func action_names() -> Array[StringName]:
	var out: Array[StringName] = []
	for a in actions:
		if a != null:
			out.append(a.action)
	return out


## Group headings in first-seen order.
func groups() -> PackedStringArray:
	var out := PackedStringArray()
	for a in actions:
		if a != null and not out.has(a.group):
			out.append(a.group)
	return out


## Whether actions `a` and `b` may share `encoded` (an event on `device`).
func overlap_allowed(a: StringName, b: StringName, device: StringName, encoded: String) -> bool:
	for o in allowed_overlaps:
		var pa := StringName(str(o.get("a", "")))
		var pb := StringName(str(o.get("b", "")))
		if not ((pa == a and pb == b) or (pa == b and pb == a)):
			continue
		var dev := str(o.get("device", "any"))
		if dev != "any" and dev != String(device):
			continue
		var ev := str(o.get("event", ""))
		if ev == "" or ev == encoded:
			return true
	return false


## The mirror whose target is `action`, or {}.
func mirror_of(target: StringName) -> Dictionary:
	for m in mirrors:
		if StringName(str(m.get("target", ""))) == target:
			return m
	return {}


## The soft notice kind of an encoded event ("" = none).
func soft_kind(encoded: String) -> String:
	for r in reserved_soft:
		if str(r.get("event", "")) == encoded:
			return str(r.get("kind", ""))
	return ""


func validate() -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	for a in actions:
		if a == null:
			out.append("empty rebind row")
			continue
		if seen.has(a.action):
			out.append("rebind action %s listed twice" % a.action)
		seen[a.action] = true
		if a.label.strip_edges() == "":
			out.append("rebind action %s has no label" % a.action)
		if a.key_slots < 1 or a.pad_slots < 1:
			out.append("rebind action %s needs at least one key and one pad slot" % a.action)
		if a.contexts.is_empty():
			out.append("rebind action %s has no context" % a.action)
	return out
