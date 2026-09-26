class_name BossArena
extends Area2D
## Boss encounter controller (bible §17 rules): the Anchor sits just outside
## (short runback), gates close on entry, the intro plays once and is skipped
## on later attempts, defeat sets a flag, opens the gates and spawns the reward.
## The reward can never be missed: a room re-entered after the win spawns it
## again, and the pickup frees itself once it has been taken (a Collectible
## by persist_id, an AbilityPickup by its flag).
## Origin: top-left of the trigger area.

@export var size: Vector2 = Vector2(400, 200)
@export var boss_id: String = "warden_krail"
@export var boss_title: String = "WARDEN KRAIL"
@export var boss_subtitle: String = "Lowlight Enforcement"
@export var boss_path: NodePath
@export var gate_paths: Array[NodePath] = []
@export var reward_scene: PackedScene
## Where the reward lands, in the arena parent's space (room space in
## generated rooms): on the floor, never mid-air. INF = where the boss died.
@export var reward_position: Vector2 = Vector2.INF
## Seconds of intro banner before the boss acts (first attempt only).
@export var intro_time: float = 2.2
@export var retry_intro_time: float = 0.6
## M8: the scripted intro (data/sequences). First attempt: it locks and plays
## in full, then the boss acts after post_intro_delay. Retries play its
## repeat steps as a non-locking overlay and the boss acts after
## retry_intro_time, as in M7 (§17 "fast restart"). In INSTANT mode
## (headless) the M7 banner and timers run unchanged. null = the M7 intro.
@export var intro_sequence: SequenceData
## Free movement between the letterbox leaving and the first boss decision.
@export var post_intro_delay: float = 1.0

var boss: Enemy
var started: bool = false
## True once the boss was handed its AI (tests: an aborted intro never is).
var released: bool = false
var _reward: Node2D


func _ready() -> void:
	collision_layer = 0
	collision_mask = CombatLayers.PLAYER_BODY
	monitoring = true
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = size * 0.5
	add_child(shape)
	boss = get_node_or_null(boss_path) as Enemy
	if Game.has_flag(defeated_flag()):
		if boss:
			boss.queue_free()
		_set_gates(false)
		# Left before picking the reward up: it waits here on the next visit.
		_spawn_reward.call_deferred(Vector2.INF)
		return
	if boss:
		boss.ai_enabled = false
		if not boss.died.is_connected(_on_boss_died):
			boss.died.connect(_on_boss_died)
	_set_gates(false)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func defeated_flag() -> String:
	return "%s_defeated" % boss_id


func _on_body_entered(body: Node2D) -> void:
	if started or not body is Player or boss == null:
		return
	started = true
	_set_gates(true)
	# Read before it is set: a death mid-fight gives the short intro on retry.
	var seen := Game.has_flag("%s_intro_seen" % boss_id)
	Game.set_flag("%s_intro_seen" % boss_id)
	_start_fight(seen)


## The intro, then the boss's AI. Three paths with a sequence (see
## intro_sequence); without one, exactly the M7 banner and timer.
func _start_fight(seen: bool) -> void:
	EventBus.boss_started.emit(boss, boss_title)
	if intro_sequence == null:
		await _legacy_intro(seen)
		_release_boss()
		return
	# The context carries the view: the seen flag was just set above.
	var ctx := SequenceContext.for_arena(self, not seen)
	if CinematicMode.current() == CinematicMode.Mode.INSTANT:
		# Headless: the play resolves in this call; keep the M7 timing. It
		# shows nothing, so it leaves the camera alone too: the restore
		# contract's snap would reset the look-ahead of a Rook walking in
		# and shift every later frame (CaptureTour s_boss_fight).
		ctx.camera = null
		await Cinematics.play(intro_sequence, ctx)
		# Locals live as long as a suspended coroutine; drop them before the
		# timers so a quit mid-timer leaks nothing at exit.
		ctx = null
		await _legacy_intro(seen)
		_release_boss()
		return
	if seen:
		# Repeat: a non-locking overlay (repeat_locks_input = false). Rook
		# never loses control on a retry; the boss acts on the M7 timer.
		_play_overlay(ctx)
		ctx = null
		await _timer(retry_intro_time)
		_release_boss()
		return
	var res := await Cinematics.play(intro_sequence, ctx)
	ctx = null
	if res.refused:
		# Another locking play owns Cinematics (a preview, the story tour):
		# the gates are already shut, so fall back to the M7 intro rather
		# than leave a sealed arena with a sleeping boss.
		res = null
		await _legacy_intro(seen)
		_release_boss()
		return
	if res.aborted() or not is_inside_tree() or not is_instance_valid(boss):
		if res.aborted() and not seen:
			# The only first view was cut (Save & Quit, room left): replay it
			# in full next time. A finished or skipped intro stays seen.
			Game.set_flag("%s_intro_seen" % boss_id, false)
		return
	res = null
	await _timer(post_intro_delay)
	_release_boss()


## Started without await: the fight timer runs beside it.
func _play_overlay(ctx: SequenceContext) -> void:
	await Cinematics.play(intro_sequence, ctx)


## The M7 intro: banner (subtitle on the first attempt only), roar, timer.
func _legacy_intro(seen: bool) -> void:
	EventBus.room_entered.emit(boss_title, boss_subtitle if not seen else "")
	AudioManager.play_sfx(&"boss_roar")
	await _timer(retry_intro_time if seen else intro_time)


func _timer(seconds: float) -> void:
	await get_tree().create_timer(seconds, false, true).timeout


func _release_boss() -> void:
	if not is_inside_tree() or not is_instance_valid(boss) or boss.is_dead():
		return
	released = true
	boss.ai_enabled = true
	boss.set_ai(Enemy.AI.ENGAGE)


func _on_boss_died(e: Enemy) -> void:
	# The boss is freed at death_time, before the delay below ends: read
	# everything needed from it now.
	var died_at := e.global_position
	var delay := e.data.death_time + 0.2
	Game.set_flag(defeated_flag())
	EventBus.boss_defeated.emit(boss_id)
	await get_tree().create_timer(delay, false, true).timeout
	_set_gates(false)
	_spawn_reward(died_at)


## `fallback` (global) is used when reward_position is INF; with no fallback
## either, the arena centre.
func _spawn_reward(fallback: Vector2) -> void:
	if reward_scene == null or not is_inside_tree() or is_instance_valid(_reward):
		return
	var parent := get_parent()
	var reward := reward_scene.instantiate() as Node2D
	if reward_position != Vector2.INF:
		reward.position = reward_position
	else:
		var at := fallback if fallback != Vector2.INF else global_position + size * 0.5
		reward.position = (parent as Node2D).to_local(at) if parent is Node2D else at
	_reward = reward
	parent.add_child(reward)


## Closing seals every listed gate. Opening skips a Gate whose own open_flag
## is not set yet: an exit gate that keys on the reward (D-100) is listed so a
## re-armed fight (DevActions.quick_boss_restart with the reward owned) seals
## it too, but the win alone must not open it.
func _set_gates(closed: bool) -> void:
	for p in gate_paths:
		var g := get_node_or_null(p)
		if g == null or not g.has_method("set_closed"):
			continue
		if not closed and g is Gate and (g as Gate).open_flag != "" and not Game.has_flag((g as Gate).open_flag):
			continue
		g.set_closed(closed)


## ContentValidator protocol: the reward's pickup flag is produced here (the
## reward is spawned at runtime, so no room node carries it). Doors may key
## on it: Collector Bay and Warden Tower open their way out on the reward,
## not on the win, so nobody leaves before it lands (D-100).
func content_flags() -> Dictionary:
	var out: Array = []
	if reward_scene != null:
		var r := reward_scene.instantiate()
		if r.has_method("content_flags"):
			out.append_array(r.content_flags().get("produces", []))
		r.free()
	var d := {"produces": out, "consumes": [], "conditions": []}
	if intro_sequence:
		var s := intro_sequence.content_flags()
		d["produces"].append_array(s.get("produces", []))
		d["consumes"].append_array(s.get("consumes", []))
		d["conditions"].append_array(s.get("conditions", []))
	return d


## ContentValidator protocol: the intro is authored for this room.
func content_errors(room: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if intro_sequence and intro_sequence.room != room.scene_file_path:
		out.append("intro sequence %s is authored for %s, not this room" % [intro_sequence.id, intro_sequence.room if intro_sequence.room != "" else "no room"])
	return out
