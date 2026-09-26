class_name ActLibrary
extends RefCounted
## The built acts (data/story/act<N>.tres) and the "where things stand"
## lines of an act card. Static and lazy; scanned through DataDir so an
## exported build finds the .tres.remap files too. Later acts only add data.

const DIR := "res://data/story"

static var _acts: Dictionary = {}
static var _loaded: bool = false


static func _scan() -> void:
	if _loaded:
		return
	_loaded = true
	_acts.clear()
	for path in DataDir.list(DIR):
		var a := load(path) as ActData
		if a != null:
			_acts[a.act] = a


## The act numbered n, or null when it is not built.
static func act(n: int) -> ActData:
	_scan()
	return _acts.get(n) as ActData


## Highest act whose complete_flag is set, + 1, capped at the last built act
## (Act I done with no Act II built stays 1).
static func current_act() -> int:
	_scan()
	var built: Array = _acts.keys()
	if built.is_empty():
		return 1
	built.sort()
	var n := 1
	for k: int in built:
		var a: ActData = _acts[k]
		if a.complete_flag != "" and Game.has_flag(a.complete_flag):
			n = k + 1
	return mini(n, int(built[-1]))


## Up to max_standing lines in authored order. The last line (condition "",
## the act's hook forward) always shows; the conditional lines before it fill
## the other max_standing - 1 slots, first passing first.
static func standing_lines(a: ActData) -> PackedStringArray:
	var out := PackedStringArray()
	if a == null or a.standing.is_empty():
		return out
	var last := a.standing[-1]
	var has_fallback := last != null and last.condition == ""
	var room := a.max_standing - (1 if has_fallback else 0)
	for i in a.standing.size() - (1 if has_fallback else 0):
		var l := a.standing[i]
		if out.size() >= room:
			break
		if l != null and Game.check_condition(l.condition):
			out.append(l.text)
	if has_fallback:
		out.append(last.text)
	return out


## Drops the static cache (Cinematics clears every story cache at exit, so
## no Resource outlives its script and the engine reports no leaks).
static func clear_cache() -> void:
	_acts = {}
	_loaded = false
