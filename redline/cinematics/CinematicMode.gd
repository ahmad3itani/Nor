class_name CinematicMode
extends RefCounted
## One switch for how scripted sequences AND memory vignettes play (M8, D-107).
##
## PLAY: real time, player paced. AUTO: timed lines advance on their own at
## `auto_speed` (sequence tests, the story capture tour). INSTANT: every step
## resolves at once (its finish() runs, nothing waits), so headless tests,
## RouteBot walks and probes can never hang on a scene. Headless defaults to
## INSTANT; `--cinematics=play|auto|instant` overrides the default.
##
## It also owns the shared "a scene is on screen" state the HUD reads, and the
## per-test teardown hook: teardown() lives here (T01) so every worktree can
## reset sequences and memories without knowing their classes.

enum Mode { PLAY, AUTO, INSTANT }

## Current mode; read through current() (resolved lazily on first use).
static var mode: Mode = Mode.PLAY
static var _mode_resolved: bool = false
## AUTO playback speed multiplier (tests/tours may speed it up).
static var auto_speed: float = 1.0
## True while any owner hides the HUD (recomputed by push/pop; CombatHud reads
## it; tests may write it directly).
static var hud_hidden: bool = false
## StringName owner -> true. Owners: &"sequence" (SequencePlayer), &"memory"
## (MemoryScenePlayer). Counted per owner because a memory can play from the
## journal in the middle of a locking sequence (which does not pause the
## tree); with one bool the memory's end would show the HUD and release queued
## hints under the resumed sequence.
static var _hud_owners: Dictionary = {}
## True while a non-letterboxed scene line (a radio bark) is on screen; the
## HUD keeps drawing but holds hints so the two never overlap.
static var bark_line: bool = false
## True during dev replays (Ending theatre): telemetry ignores sequence events
## and trigger autoplay is suppressed.
static var theatre: bool = false
static var _teardowns: Array[Callable] = []


static func current() -> Mode:
	if not _mode_resolved:
		mode = _default_mode()
		_mode_resolved = true
	return mode


## Explicit override, honoured by current() until reset().
static func set_mode(m: Mode) -> void:
	mode = m
	_mode_resolved = true


## Back to the default mode (headless INSTANT / PLAY, or the --cinematics= arg).
static func reset() -> void:
	_mode_resolved = false
	auto_speed = 1.0


static func _default_mode() -> Mode:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cinematics="):
			match a.trim_prefix("--cinematics="):
				"play":
					return Mode.PLAY
				"auto":
					return Mode.AUTO
				"instant":
					return Mode.INSTANT
	return Mode.INSTANT if DisplayServer.get_name() == "headless" else Mode.PLAY


static func push_hud_hide(owner: StringName) -> void:
	_hud_owners[owner] = true
	hud_hidden = not _hud_owners.is_empty()


## Popping an owner that never pushed is a no-op for the others.
static func pop_hud_hide(owner: StringName) -> void:
	_hud_owners.erase(owner)
	hud_hidden = not _hud_owners.is_empty()


## Scene players register their abort here once (Cinematics.abort,
## MemoryScenePlayer.abort_active); registering the same callable twice keeps one.
static func register_teardown(c: Callable) -> void:
	if not _teardowns.has(c):
		_teardowns.append(c)


## Stops every scene without running its effects (abort: no flags set, the
## scene replays later). Mode and theatre stay (PauseMenu quit to title).
static func abort_all() -> void:
	for c in _teardowns.duplicate():
		if c.is_valid():
			c.call()


## Per-test / per-run reset: abort every scene, then clear every shared flag
## and return to the default mode.
static func teardown() -> void:
	abort_all()
	_hud_owners.clear()
	hud_hidden = false
	bark_line = false
	theatre = false
	reset()
