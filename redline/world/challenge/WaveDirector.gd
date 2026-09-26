class_name WaveDirector
extends Node
## Runs a Pulse Pit WaveSet (M9 D2 §2.3) inside its room. Deterministic: no
## RNG, round-robin spawn markers, frame-counted delays, so the same inputs
## always meet the same pit (records and ghosts compare).
##
## It is the room's score provider for Challenges (group challenge_score,
## score() -> int, `wave` for the HUD). It ARMS itself when its room is built
## inside a run whose ChallengeData.waves is one of its wave_sets: in _ready
## and on player_spawned, because challenge_started fires only after the
## room exists (Challenges.start -> SceneRouter.transition_to waits for the
## fade, then goto_room runs deferred; a fast reset also reloads the room
## with goto_room.call_deferred). challenge_started and challenge_reset only
## re-arm a director that is already loaded. Waves run only while the run
## clock runs (never in a fade, the pause or after the finish). A cleared
## non-looping set finishes the run (Challenges.finish(FINISHED)).
##
## Enemies are instanced like EnemySpawner.spawn and placed under the room's
## Enemies node, so the EncounterDirector and the combat rules see them as
## any authored enemy.

signal wave_started(number: int)
signal wave_cleared(number: int)
## A non-looping set has no waves and no enemies left.
signal set_cleared

const LOC_FIELDS := {}
const FPS := 60.0

## The WaveSets this room may run (roomgen writes both Pulse Pit sets).
## Typed as Resource so the scene never needs the WaveSet script id.
@export var wave_sets: Array[Resource] = []

## Test seam: tick without a live challenge (the deterministic-order test).
var free_run: bool = false

var wave_set: WaveSet = null
var armed: bool = false
## Waves started so far (1-based for the HUD; it keeps counting across loops).
var wave: int = 0
var kills: int = 0
var waves_cleared: int = 0
## Loops completed (each adds loop_count_bonus per entry).
var loop: int = 0
## Spawn log for tests: [wave number, scene path, spawn point], in order.
var spawn_log: Array = []

var _started: bool = false
var _finished: bool = false
var _frames: int = 0
var _wave_frames: int = 0
## 0-based index into the set of the current wave.
var _index: int = -1
## [{"scene": String, "point": int, "at": int (frame of _frames), "seq": int}]
var _pending: Array[Dictionary] = []
## [[Enemy, seq]]
var _alive: Array = []
## seq -> true once its wave was counted cleared.
var _cleared: Dictionary = {}
var _scenes: Dictionary = {}


func _ready() -> void:
	add_to_group(&"challenge_score")
	EventBus.challenge_started.connect(_on_challenge_event)
	EventBus.challenge_reset.connect(_on_challenge_event)
	EventBus.player_spawned.connect(_on_player_spawned)
	try_arm()


## Arms for the live run's set when this room runs it. True when armed.
func try_arm() -> bool:
	var ws := _run_set()
	if ws == null:
		return false
	arm(ws)
	return true


func _run_set() -> WaveSet:
	if not Challenges.active():
		return null
	var ch := Challenges.current()
	if ch == null:
		return null
	var ws := ch.waves as WaveSet
	return ws if ws != null and accepts(ws) else null


## Whether this room runs `ws` (by identity or by its file: a duplicated
## challenge in a test still names the same set file).
func accepts(ws: WaveSet) -> bool:
	if wave_sets.is_empty():
		return true
	for s in wave_sets:
		if s == ws or (s != null and s.resource_path != "" and s.resource_path == ws.resource_path):
			return true
	return false


## Fresh state for `ws`: nothing spawned yet; wave 1 starts on the first
## counted tick. Re-arming frees the enemies this director spawned.
func arm(ws: WaveSet) -> void:
	for pair: Array in _alive:
		var e: Node = pair[0]
		if is_instance_valid(e):
			e.queue_free()
	wave_set = ws
	armed = true
	wave = 0
	kills = 0
	waves_cleared = 0
	loop = 0
	spawn_log = []
	_started = false
	_finished = false
	_frames = 0
	_wave_frames = 0
	_index = -1
	_pending = []
	_alive = []
	_cleared = {}


func disarm() -> void:
	arm(wave_set)
	armed = false


func _on_challenge_event(_id: String, _extra: Variant) -> void:
	if armed or is_inside_tree():
		try_arm()


func _on_player_spawned(_p: Node2D) -> void:
	if not armed:
		try_arm()


func _can_tick() -> bool:
	if free_run:
		return true
	return Challenges.phase() == Challenges.Phase.RUNNING and Challenges.clock.running and not SceneRouter.transitioning


func _physics_process(_delta: float) -> void:
	if not armed or wave_set == null or _finished or not _can_tick():
		return
	tick()


## One counted frame (public so tests can step it without the tree clock).
func tick() -> void:
	if not _started:
		_started = true
		_start_wave(0)
	_frames += 1
	_wave_frames += 1
	_prune()
	_spawn_due()
	_check_cleared()
	_maybe_advance()


func _start_wave(index: int) -> void:
	_index = index
	wave += 1
	_wave_frames = 0
	var bonus := loop * wave_set.loop_count_bonus
	for e in wave_set.wave_entries(index + 1):
		var n := e.count + bonus
		for i in n:
			var point: int = e.spawn_points[i % e.spawn_points.size()] if not e.spawn_points.is_empty() else 1
			_pending.append({"scene": e.enemy_scene, "point": point, "at": _frames + roundi(e.delay_s * FPS), "seq": wave})
	wave_started.emit(wave)


func _spawn_due() -> void:
	var i := 0
	while i < _pending.size():
		var p := _pending[i]
		if int(p["at"]) > _frames:
			i += 1
			continue
		if _alive.size() >= wave_set.max_alive:
			return
		_pending.remove_at(i)
		_spawn(String(p["scene"]), int(p["point"]), int(p["seq"]))


func _spawn(scene_path: String, point: int, seq: int) -> void:
	var room := get_parent()
	var marker := room.get_node_or_null("WaveSpawns/WaveSpawn_%d" % point) as Node2D if room else null
	if marker == null:
		push_warning("WaveDirector: no WaveSpawn_%d in %s" % [point, room.name if room else "?"])
		return
	if not _scenes.has(scene_path):
		_scenes[scene_path] = load(scene_path) as PackedScene
	var packed := _scenes[scene_path] as PackedScene
	if packed == null:
		return
	var e := packed.instantiate() as Enemy
	if e == null:
		return
	var parent := room.get_node_or_null("Enemies") as Node2D
	if parent == null:
		parent = room as Node2D
	e.ai_enabled = true
	# Face the middle of the pit (the player's side), like an authored enemy.
	var center := (room as Room).bounds.get_center().x if room is Room else 0.0
	e.facing = -1 if marker.position.x > center else 1
	e.position = parent.to_local(marker.global_position)
	parent.add_child(e)
	_alive.append([e, seq])
	spawn_log.append([seq, scene_path, point])


func _prune() -> void:
	for i in range(_alive.size() - 1, -1, -1):
		var e: Variant = _alive[i][0]
		if not is_instance_valid(e) or (e as Enemy).is_dead():
			_alive.remove_at(i)
			kills += 1


func _left(seq: int) -> int:
	var n := 0
	for p in _pending:
		if int(p["seq"]) == seq:
			n += 1
	for pair: Array in _alive:
		if int(pair[1]) == seq:
			n += 1
	return n


func _check_cleared() -> void:
	for seq in range(1, wave + 1):
		if _cleared.has(seq):
			continue
		if _left(seq) == 0:
			_cleared[seq] = true
			waves_cleared += 1
			wave_cleared.emit(seq)


func _maybe_advance() -> void:
	var current_spawned := not _pending.any(func(p: Dictionary) -> bool: return int(p["seq"]) == wave)
	var thinned := current_spawned and _alive.size() <= wave_set.next_when_alive_at_most
	var stalled := _wave_frames >= roundi(wave_set.next_after_s * FPS)
	var next := _index + 1
	if next >= wave_set.wave_count():
		if not wave_set.loops():
			if _pending.is_empty() and _alive.is_empty():
				_finish()
			return
		if not (thinned or stalled):
			return
		loop += 1
		_start_wave(wave_set.loop_from)
		return
	if thinned or stalled:
		_start_wave(next)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	set_cleared.emit()
	if not free_run and Challenges.active():
		Challenges.finish(ChallengeData.Outcome.FINISHED)


## The live score (Challenges.score_value reads it): the style score for a
## STYLE set, the endurance formula for an ENDURANCE set.
func score() -> int:
	if wave_set == null:
		return 0
	if wave_set.score_mode == WaveSet.ScoreMode.STYLE:
		return roundi(Challenges.session.style_score) if Challenges.session else 0
	return wave_set.endurance_score(seconds(), kills, waves_cleared, multiplier())


## Run seconds (the run clock; the director's own frames in a free run).
func seconds() -> float:
	if not free_run and Challenges.active():
		return float(Challenges.clock.frames) / RunClock.FPS
	return float(_frames) / FPS


## The live Core's score multiplier (1.5 on the Challenge core, D2 §2.3).
func multiplier() -> float:
	var room := get_parent() as Room
	if room and is_instance_valid(room.player) and room.player.reactor and room.player.reactor.config:
		return room.player.reactor.config.score_multiplier
	return 1.0


func alive_count() -> int:
	return _alive.size()


## Node content protocol: every WaveSpawn a set names exists in this room
## (NU-6 also checks it from the challenge side).
func content_errors(room: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for s in wave_sets:
		var ws := s as WaveSet
		if ws == null:
			out.append("WaveDirector wave_sets entry is not a WaveSet")
			continue
		for i in ws.spawn_points():
			if room.get_node_or_null("WaveSpawns/WaveSpawn_%d" % i) == null:
				out.append("WaveDirector: %s names WaveSpawn_%d, which the room lacks" % [ws.resource_path.get_file(), i])
	return out
