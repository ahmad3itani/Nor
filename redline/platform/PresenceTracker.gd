class_name PresenceTracker
extends Node
## Rich presence (M9 D1 §3.5): one status line derived from where the player
## is and what is happening, pushed to the backend when it changes. Locally it
## only feeds the DebugOverlay PRESENCE line (§37.5 debug visibility).
##
## Priority: a manual override (Platform.set_presence, until the next event),
## a challenge run, a memory, a scripted scene, a boss fight, then the room
## (world room, Act I done, or a lab), else the menus.

var table: PresenceTable
var key: String = ""
var text: String = ""
var _boss_title: String = ""
var _memory: bool = false
var _challenge_name: String = ""
var _override: Array = []
var _queued: bool = false


func _ready() -> void:
	if table == null:
		table = load("res://data/platform/presence.tres") as PresenceTable
	var changed := func() -> void: _changed()
	EventBus.room_entered.connect(func(_d: String, _r: String) -> void: changed.call())
	EventBus.room_loaded.connect(func(_r: Node) -> void: changed.call())
	EventBus.room_leaving.connect(func(_r: Node) -> void:
		_boss_title = ""
		changed.call())
	EventBus.boss_started.connect(func(_b: Node2D, title: String) -> void:
		_boss_title = title
		changed.call())
	EventBus.boss_defeated.connect(func(_id: String) -> void:
		_boss_title = ""
		changed.call())
	EventBus.player_died.connect(func() -> void:
		_boss_title = ""
		changed.call())
	EventBus.memory_scene_started.connect(func(_id: String, _s: StringName) -> void:
		_memory = true
		changed.call())
	EventBus.memory_playback_finished.connect(func(_s: StringName) -> void:
		_memory = false
		changed.call())
	EventBus.memory_playback_aborted.connect(func(_s: StringName) -> void:
		_memory = false
		changed.call())
	EventBus.sequence_started.connect(func(_id: String, _f: bool) -> void: changed.call())
	EventBus.sequence_finished.connect(
		func(_i: String, _s: bool, _t: float, _x: int, _c: int, _n: float) -> void: changed.call())
	EventBus.challenge_started.connect(func(id: String, _a: int) -> void:
		var t: String = Challenges.current_title()
		_challenge_name = t if t != "" else id
		changed.call())
	EventBus.challenge_finished.connect(func(_i: String, _o: int, _v: int, _m: int, _b: bool) -> void: changed.call())
	EventBus.game_state_reset.connect(func() -> void:
		_boss_title = ""
		_memory = false
		changed.call())
	EventBus.flag_changed.connect(func(id: String, _v: Variant) -> void:
		if id == "act1_complete":
			changed.call())


## [key, args] for the current moment.
func derive() -> Array:
	if not _override.is_empty():
		return _override
	if Challenges.active():
		return ["challenge", {"name": _challenge_name if _challenge_name != "" else Challenges.current_id()}]
	if _memory or MemoryScenePlayer.active_instance != null:
		return ["memory", {}]
	if Cinematics.is_playing():
		return ["cinematic", {}]
	if _boss_title != "":
		return ["boss", {"boss": _boss_title}]
	var r := SceneRouter.current_room
	if is_instance_valid(r) and r is Room:
		var room := r as Room
		if not room.world_room:
			return ["lab", {"room": room.room_name}]
		if Game.has_flag("act1_complete"):
			return ["act_done", {"room": room.room_name}]
		return ["room", {"district": room.district_name, "room": room.room_name}]
	return ["title", {}]


## The display line right now (derived live, so it is never stale).
func current_text() -> String:
	var d := derive()
	return table.text(String(d[0]), d[1] as Dictionary)


func current_key() -> String:
	return String(derive()[0])


## Manual status (dev tools, tests) until the next presence event. `arg`
## fills the key's placeholders; the room's district stays the live one.
func override(p_key: String, arg: String) -> void:
	var district := ""
	var r := SceneRouter.current_room
	if is_instance_valid(r) and r is Room:
		district = (r as Room).district_name
	_override = [p_key, {"district": district, "room": arg, "boss": arg, "name": arg}]
	_push()


func reset() -> void:
	_boss_title = ""
	_memory = false
	_challenge_name = ""
	_override = []
	key = ""
	text = ""


func _changed() -> void:
	_override = []
	if not _queued:
		_queued = true
		_push_deferred.call_deferred()


func _push_deferred() -> void:
	_queued = false
	_push()


func _push() -> void:
	var d := derive()
	var t := table.text(String(d[0]), d[1] as Dictionary)
	if String(d[0]) == key and t == text:
		return
	key = String(d[0])
	text = t
	Platform.backend.set_presence(key, text)
