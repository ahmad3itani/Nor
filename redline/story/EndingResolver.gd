class_name EndingResolver
extends RefCounted
## Which ending the current profile plays (D-126). Static and pure: it reads
## only Game.check_condition, owns no nodes and emits nothing. No caller in
## Act I play: the future Act V finale calls resolve() and then
## EndingDirector.play() (§37.2: no finale trigger in M8). The M8 callers are
## the dev theatre, tests and reports.

const DIR := "res://data/endings"

static var _all: Array[EndingData] = []
static var _loaded: bool = false


## Every ending, sorted by priority (highest first), then id. Loaded once
## through DataDir (exported .tres.remap); other resources in the folder
## (credits.tres) are skipped.
static func all() -> Array[EndingData]:
	if not _loaded:
		_loaded = true
		_all.clear()
		for path in DataDir.list(DIR):
			var e := load(path) as EndingData
			if e != null and e.id != "":
				_all.append(e)
		_all.sort_custom(func(a: EndingData, b: EndingData) -> bool:
			return a.priority > b.priority if a.priority != b.priority else a.id < b.id)
	return _all.duplicate()


static func by_id(id: String) -> EndingData:
	for e in all():
		if e.id == id:
			return e
	return null


static func requirements_met(e: EndingData) -> bool:
	for c in e.requirements():
		if not Game.check_condition(c):
			return false
	return true


## What the finale may offer, in priority order.
static func offered() -> Array[EndingData]:
	var out: Array[EndingData] = []
	for e in all():
		if requirements_met(e):
			out.append(e)
	return out


## The first offered ending whose choice was made; null if none. If two
## choice flags were ever set, the higher priority wins (deterministic).
static func resolve() -> EndingData:
	for e in offered():
		if Game.check_condition(e.choice_condition):
			return e
	return null


## Each condition with its group (Choice / Story / Memories / People), its
## current result and whether it reads a future flag (the theatre shows
## "x (Act N)" instead of a bare x).
static func explain(e: EndingData) -> Array[Dictionary]:
	var future := FutureFlagSet.shared()
	var out: Array[Dictionary] = []
	var add := func(group: String, expr: String) -> void:
		if expr == "":
			return
		var flag := expr.trim_prefix("!").get_slice(":", 1)
		out.append({"group": group, "expr": expr, "ok": Game.check_condition(expr),
			"future": future.is_future_condition(expr), "act": future.act_of(flag)})
	add.call("Choice", e.choice_condition)
	for c in e.requires:
		add.call("Story", c)
	add.call("Memories", e.requires_memories)
	for c in e.requires_arcs:
		add.call("People", c)
	return out


## Drops the static cache (Cinematics clears every story cache at exit, so
## no Resource outlives its script and the engine reports no leaks).
static func clear_cache() -> void:
	_all = []
	_loaded = false
