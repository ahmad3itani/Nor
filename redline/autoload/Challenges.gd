extends Node
## The run director (M9 D2/D3, D-147): boss rematches, time trials, no-hit and
## movement-only runs, the Pulse Pit and the Deep Rig strata all run here,
## each inside one ProfileSandbox, with one records store, one run HUD and one
## result card. It is a thin coordinator (§37.4): the rules live in RefCounted
## helpers (RunClock, CampaignClock, RuleWatch, RecordStore, the ghost engine)
## that tests build without the tree.
##
## A run: start() saves the profile (from a world room), freezes the world
## player and fades out; the sandbox is swapped in between rooms (room_leaving,
## R04.24) so no frame of either room ever runs on the wrong state; the run
## room gets its hooks on room_loaded (death override, hint presets, finish
## line, Anchor/NPC lockout, ghosts). finish() posts the record and opens the
## result card after a beat; quit() restores the same profile objects and
## returns to where the run began. Gameplay never calls in, except
## ChallengeGoal, the result card and the pause/title rows.
##
## No class_name (an autoload's script must not declare one, R01.27).

enum Phase { IDLE, STARTING, RUNNING, FINISHING, FINISHED, LEAVING }

const LOC_FIELDS := {}
const TAG_HITSTOP := "hitstop_reduced"
## Frames between checks for an owed group-open notice.
const OWED_CHECK_FRAMES := 6
## Assist tags a forced Core makes moot (the kit sets the mode, D-149).
const REACTOR_TAGS := ["reactor_assist", "no_burnout"]

## Test seam (T01): pretend a run is live.
var force_active: bool = false
## Test seam (T01; T03's Core-row test sets it): -1 = no forced mode.
var force_reactor_mode: int = -1
## Test seam (T01): pretend a run just ended (result card pending).
var force_finishing: bool = false
## CaptureTour sets it so the group-open notice never draws in a tour frame.
var quiet_notices: bool = false
## R04.26: () -> PackedStringArray, the neutral assist tags in use. Tests set
## a fixed provider; reset_for_tests restores the default.
var tag_provider: Callable = _default_tags

var session: RunSession = null
var clock := RunClock.new()
var campaign := CampaignClock.new()
var records := RecordStore.new()
var rules: RuleWatch = null
var recorder: GhostRecorder = null
var ghosts: Array[GhostPlayback] = []
var hud: RunTimerHud
## The last SubmitResult (the result card's context).
var last_result: Dictionary = {}

var _phase: Phase = Phase.IDLE
## [GameState, PlayerAbilities] waiting for the source room to leave.
var _pending_swap: Array = []
## A quit back to a world room: restore when the run room leaves.
var _pending_return: bool = false
## The next room_loaded follows a restart (true = a full new attempt).
var _restart_pending: bool = false
var _restart_full: bool = false
## After a restore between rooms: game_state_reset once the room is in.
var _reset_on_load: bool = false
## ROOM_READY: start the clock on the next counted tick.
var _start_next_tick: bool = false
var _actors: Array[GhostActor] = []
var _reset_down: bool = false
var _reset_hold: int = 0
var _hold_fired: bool = false
var _card_requested: bool = false
## Physics-time, pause-respecting: a death restart after the respawn beat.
var _death_timer: Timer
## Runs while paused: the result card's delay.
var _card_timer: Timer
## A live unlock notice check is queued for the end of the frame.
var _notice_pending: bool = false
## A live group-open notice was blocked by a passing state (see _announce).
var _notice_owed: bool = false
var _owed_tick: int = 0


func _ready() -> void:
	process_physics_priority = 100
	hud = RunTimerHud.new()
	hud.name = "RunTimerHud"
	add_child(hud)
	_death_timer = Timer.new()
	_death_timer.one_shot = true
	_death_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	_death_timer.timeout.connect(_on_death_timer)
	add_child(_death_timer)
	_card_timer = Timer.new()
	_card_timer.one_shot = true
	_card_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_card_timer.timeout.connect(_on_card_timer)
	add_child(_card_timer)
	_wire_campaign()
	EventBus.room_leaving.connect(_on_room_leaving)
	EventBus.room_loaded.connect(_on_room_loaded)
	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.boss_started.connect(_on_boss_started)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.style_changed.connect(_on_style_changed)
	EventBus.flag_changed.connect(_on_flag_changed)
	EventBus.room_entered.connect(_on_room_entered)
	EventBus.game_state_reset.connect(_on_game_state_reset)
	EventBus.settings_changed.connect(_on_settings_changed)
	DebugOverlay.providers.append(debug_lines)


func _wire_campaign() -> void:
	campaign.records = records
	campaign.tag_provider = func() -> PackedStringArray: return tag_provider.call()


func _default_tags() -> PackedStringArray:
	return Settings.active_assists()


# --- State queries ---------------------------------------------------------------

func active() -> bool:
	return force_active or session != null


func current() -> ChallengeData:
	return session.challenge if session else null


func current_id() -> String:
	return session.challenge.id if session else ""


## The challenge title, plus the stage title in a staged run.
func current_title() -> String:
	if session == null:
		return ""
	var ch := session.challenge
	var t := Loc.t(ch.title)
	var st := ch.stage(session.stage_index)
	if has_stages() and st:
		t += "  ·  " + Loc.t(st.title)
	return t


## True when the live run has several stages (a descent).
func has_stages() -> bool:
	return session != null and session.challenge.stages.size() > 1


func phase() -> Phase:
	return _phase


func attempt() -> int:
	return session.attempt if session else 0


func stage_index() -> int:
	return session.stage_index if session else 0


func forced_reactor_mode() -> int:
	if force_reactor_mode >= 0:
		return force_reactor_mode
	if session and session.challenge.kit:
		return session.challenge.kit.reactor_mode
	return -1


## True between a run's end and its result card opening (R04.2): pause stays
## shut so the card is never dropped.
func finishing() -> bool:
	if force_finishing or _phase == Phase.FINISHING:
		return true
	return _phase == Phase.FINISHED and _card_pending()


func _card_pending() -> bool:
	if not _card_requested:
		return false
	var host := _host()
	if host == null:
		return false
	for q: Array in host.get("_queued"):
		if q.size() > 0 and q[0] == &"challenge_result":
			return true
	return false


## Whether any challenge is unlocked for this save data (title row gate).
func any_unlocked_for(data: Dictionary) -> bool:
	return ChallengeLibrary.any_unlocked_for(data)


# --- Start ------------------------------------------------------------------------

## Starts `ch`. return_to: {"room": path, "entry": id} (the Relay terminal),
## {"title": true} (the title row) or {} (tools: stay). Refused while a run,
## a transition or a locking scene is live, when a requirement fails on the
## profile, or when the build cannot reach the run's rooms.
func start(ch: ChallengeData, return_to: Dictionary = {}) -> bool:
	if ch == null or active() or SceneRouter.transitioning or Cinematics.locks_input() or Game.held_profile != null:
		return false
	if SceneRouter.world_root == null or not ChallengeLibrary.allowed(ch):
		return false
	for c in ch.requires:
		if not ChallengeLibrary.profile_holds(c):
			return false
	var from_title := bool(return_to.get("title", false))
	var room := _room()
	if from_title:
		_close_title()
	elif room and room.world_room and is_instance_valid(room.player):
		# The disk holds the pre-run profile: a crash mid-run loses nothing.
		Game.capture_from_player(room.player)
		Game.save_game()
	if room and is_instance_valid(room.player):
		_freeze(room.player)
	Game.suppress_leave_capture = true
	session = RunSession.new(ch, return_to, CinematicMode.theatre)
	session.profile_play_time = Game.state.play_time_sec
	CinematicMode.theatre = true
	var st := ProfileSandbox.kit_state(ch.kit, ch, Game.state)
	var ab := ProfileSandbox.kit_abilities(st)
	_phase = Phase.STARTING
	if is_instance_valid(SceneRouter.current_room) and SceneRouter.current_room.is_inside_tree():
		_pending_swap = [st, ab]
	else:
		session.sandbox = ProfileSandbox.begin(st, ab, false)
	_begin_attempt()
	hud.show_reset_chip()
	# Re-registered per run: a cache reset may have cleared the providers.
	if not DebugOverlay.providers.has(debug_lines):
		DebugOverlay.providers.append(debug_lines)
	SceneRouter.transition_to(ch.stage_room(0), ch.stage_entry(0))
	return true


func _begin_attempt() -> void:
	_stop_timers()
	var ch := session.challenge
	session.reset_attempt()
	clock.reset()
	_start_next_tick = false
	_reset_hold = 0
	_hold_fired = false
	if rules:
		rules.disconnect_all()
	rules = RuleWatch.new(ch, _on_rule_fail)
	rules.connect_bus()
	rules.armed = true
	recorder = GhostRecorder.new()
	recorder.begin(ch, Game.profile_id)
	_load_ghosts()


## The profile's PB ghost and/or the shipped rig ghost, per Settings.challenge_ghost
## (0 Off, 1 PB, 2 rig, 3 both).
func _load_ghosts() -> void:
	ghosts.clear()
	if session == null:
		return
	var ch := session.challenge
	var mode := Settings.challenge_ghost
	if mode == 1 or mode == 3:
		var pb := records.pb_ghost(ch.id, Game.profile_id, ch.revision)
		if pb:
			ghosts.append(GhostPlayback.new(pb, "pb"))
	if (mode == 2 or mode == 3) and ch.dev_ghost != "":
		var dev := GhostCodec.load_file(ch.dev_ghost)
		if dev and dev.challenge == ch.id and dev.revision == ch.revision:
			ghosts.append(GhostPlayback.new(dev, "dev"))


func _close_title() -> void:
	var host := _host()
	if host == null:
		return
	var title: Variant = host.get("title")
	if title is MenuScreen and (title as MenuScreen).visible:
		(title as MenuScreen).close_menu()


## From the title (R01.16): load the profile WITHOUT a playtest session (the
## list reads unlocks from Game.state), then open the list.
func open_from_title() -> void:
	if not Game.load_game(1):
		return
	var host := _host()
	if host and host.has_method("open_with"):
		host.call("open_with", &"challenges", {"from": "title"})
	else:
		MenuHost.context = {"from": "title"}
		EventBus.menu_requested.emit(&"challenges")


# --- Room hooks ------------------------------------------------------------------

func _on_room_leaving(_room_node: Node) -> void:
	if not _pending_swap.is_empty() and session:
		# The screen is black and remove_child follows at once: the swap is
		# silent; game_state_reset waits for the new room (R04.24). The fade
		# frames never count as profile play time.
		Game.state.play_time_sec = session.profile_play_time
		session.sandbox = ProfileSandbox.begin(_pending_swap[0], _pending_swap[1], false)
		_pending_swap = []
	elif _pending_return:
		_pending_return = false
		_leave_run(false)
		_reset_on_load = true


func _on_room_loaded(room_node: Node) -> void:
	# Only Challenges sets the leave guard; the old room is gone now and the
	# new one already read the right state in _ready.
	Game.suppress_leave_capture = false
	if session == null:
		if _reset_on_load:
			_reset_on_load = false
			EventBus.game_state_reset.emit()
		return
	var started := false
	if _phase == Phase.STARTING:
		_phase = Phase.RUNNING
		EventBus.game_state_reset.emit()
		started = true
	elif _restart_pending:
		_restart_pending = false
		EventBus.game_state_reset.emit()
		started = _restart_full
	var room := room_node as Room
	if room:
		_hook_room(room)
	if started:
		_union_tags()
		EventBus.challenge_started.emit(session.challenge.id, session.attempt)


func _hook_room(room: Room) -> void:
	var ch := session.challenge
	room.death_override = _on_run_death
	# D2 §3.2: every tip in a run room is already "seen": a run never stops
	# for a tutorial. Written straight into the sandbox (no flag_changed).
	for n in room.find_children("*", "HintTrigger", true, false):
		Game.state.flags["hint_" + (n as HintTrigger).hint_id] = true
	# R04.4: no rest heal, Core refill, Loadout, shop or Transit mid-run.
	for n in room.find_children("*", "Anchor", true, false) + room.find_children("*", "NPC", true, false):
		n.process_mode = Node.PROCESS_MODE_DISABLED
		(n as Area2D).monitorable = false
	# Doors never carry a run into another room: stages move on goals, and
	# an EXIT run ends at its finish line (the next room never loads).
	var path := SceneRouter.current_room_path
	for n in room.find_children("*", "RoomExit", true, false):
		var exit := n as RoomExit
		exit.monitoring = false
		if ch.end_on == ChallengeData.EndOn.EXIT and path == ch.finish_room_path() and exit.target_room == ch.finish_exit_target:
			var line := FinishLine.new(exit.size, _on_finish_line)
			line.name = "FinishLine"
			line.position = exit.position
			exit.get_parent().add_child(line)
	if rules:
		rules.bind_player(room.player)
	_actors.clear()
	for pb in ghosts:
		var a := GhostActor.new(pb, path)
		a.name = "Ghost_" + pb.kind
		room.add_child(a)
		a.show_frame(clock.frames)
		_actors.append(a)
	if ch.start_on == ChallengeData.StartOn.ROOM_READY and not clock.running:
		_start_next_tick = true


func _on_player_spawned(p: Node2D) -> void:
	var player := p as Player
	if session == null or player == null:
		return
	var mode := forced_reactor_mode()
	if mode >= 0:
		player.reactor.apply_mode(mode)
		if Game.state.reactor_charge < 0.0:
			player.reactor.charge = player.reactor.config.start_charge


# --- Per tick ----------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if session == null:
		campaign.tick()
		if _notice_owed:
			_poll_owed_notice()
		return
	if _phase == Phase.RUNNING and not SceneRouter.transitioning:
		_tick_run()
	# Reset also works in the beat before the result card (an instant retry).
	if _phase in [Phase.RUNNING, Phase.FINISHING, Phase.FINISHED] and not SceneRouter.transitioning:
		_poll_reset()


func _tick_run() -> void:
	var room := _room()
	if room == null or not is_instance_valid(room.player):
		return
	var ch := session.challenge
	if not clock.running:
		var go := false
		match ch.start_on:
			ChallengeData.StartOn.FIRST_INPUT:
				go = _has_input(room.player.last_input)
			ChallengeData.StartOn.ROOM_READY:
				go = _start_next_tick
		if go:
			_start_next_tick = false
			clock.start()
	if not clock.running:
		return
	clock.tick()
	session.tick_stage()
	recorder.sample(room.player, room, SceneRouter.current_room_path)
	for a in _actors:
		if is_instance_valid(a):
			a.show_frame(clock.frames)
	_check_split_lines(room)
	if rules.time_up(clock.frames):
		finish(ChallengeData.Outcome.FINISHED)


static func _has_input(f: PlayerInputFrame) -> bool:
	if f == null:
		return false
	return f.move_x != 0 or f.down_held or f.up_held or f.jump_pressed or f.jump_held or f.dodge_pressed \
		or f.light_pressed or f.heavy_pressed or f.ranged_pressed or f.interact_pressed or f.heal_pressed


func _check_split_lines(room: Room) -> void:
	var xs := session.challenge.split_xs
	if session.next_split_x >= xs.size():
		return
	var x := room.player.global_position.x - room.global_position.x
	if x >= xs[session.next_split_x]:
		session.next_split_x += 1
		_split()


## A live split: the clock and the recorder mark it; the HUD shows the delta
## against this profile's best run.
func _split() -> void:
	var i := clock.splits.size()
	var f := clock.split()
	recorder.split()
	var best := records.best(session.challenge.id, Game.profile_id, session.challenge.revision)
	var best_splits: Array = best.get("splits", [])
	if i < best_splits.size():
		hud.show_split(f - int(best_splits[i]))


# --- Fast reset (D2 §3.5, R04.7) ------------------------------------------------

## A reset past the tap window (and before the player has used reset once)
## needs a short hold, so a long run is never lost to a stray press.
func reset_needs_hold() -> bool:
	if not Settings.fast_reset_hold:
		return false
	var cfg := ChallengeConfig.shared()
	return clock.frames >= roundi(cfg.fast_reset_tap_window_s * RunClock.FPS) or not records.reset_used()


## 0..1 while a needed hold is in progress (the HUD arc).
func reset_hold_fraction() -> float:
	if session == null or _reset_hold <= 0 or not reset_needs_hold():
		return 0.0
	return clampf(float(_reset_hold) / _hold_frames(), 0.0, 1.0)


func _hold_frames() -> int:
	return maxi(1, roundi(ChallengeConfig.shared().fast_reset_hold_s * RunClock.FPS))


func _poll_reset() -> void:
	var down := Input.is_action_pressed("reset")
	if not down:
		_reset_down = false
		_reset_hold = 0
		_hold_fired = false
		return
	var pressed := not _reset_down
	_reset_down = true
	_reset_hold += 1
	if reset_needs_hold():
		if _reset_hold >= _hold_frames() and not _hold_fired:
			_hold_fired = true
			_reset_by_key()
	elif pressed:
		_reset_by_key()


func _reset_by_key() -> void:
	records.mark_reset_used()
	restart(&"reset")


# --- Restart ------------------------------------------------------------------------

## Fast reset (D2 §3.5): a fresh sandbox from the kit (a secret opened last
## attempt is closed again), the clock and recorder reset, ghosts rewound, and
## the room reloaded directly with goto_room (no fade). A staged run restarts
## its current stage only, and a death restart keeps the run clock running.
func restart(reason: StringName = &"reset") -> void:
	if session == null or SceneRouter.transitioning:
		return
	if _phase != Phase.RUNNING and _phase != Phase.FINISHING and _phase != Phase.FINISHED:
		return
	var ch := session.challenge
	var death := reason == &"death"
	# After a finish, Retry is always a whole new attempt (a descent too).
	var full := _phase != Phase.RUNNING or (not death and ch.stages.size() <= 1)
	CinematicMode.abort_all()
	_cancel_card()
	_stop_timers()
	Game.suppress_leave_capture = true
	if full:
		session.attempt += 1
		_begin_attempt()
	else:
		session.reset_stage(death)
		if rules:
			# A death restart keeps the stage's hits: the rank charges each
			# hit and each death separately (D3 §3.3-3.5).
			if not death:
				rules.hits = 0
			rules.armed = true
		if not clock.running and clock.frames > 0:
			clock.start()
	var st := ProfileSandbox.kit_state(ch.kit, ch, session.sandbox.profile if session.sandbox else Game.state)
	if session.sandbox:
		session.sandbox.replace_sandbox(st, ProfileSandbox.kit_abilities(st))
	_phase = Phase.RUNNING
	_restart_pending = true
	_restart_full = full
	var i := session.stage_index
	SceneRouter.goto_room.call_deferred(ch.stage_room(i), ch.stage_entry(i))
	EventBus.challenge_reset.emit(ch.id, reason)


## A descent from its first stage (the pause row "Restart descent").
func restart_run() -> void:
	if session == null or SceneRouter.transitioning:
		return
	if _phase != Phase.RUNNING and _phase != Phase.FINISHING and _phase != Phase.FINISHED:
		return
	var ch := session.challenge
	CinematicMode.abort_all()
	_cancel_card()
	Game.suppress_leave_capture = true
	session.attempt += 1
	_begin_attempt()
	var st := ProfileSandbox.kit_state(ch.kit, ch, session.sandbox.profile if session.sandbox else Game.state)
	if session.sandbox:
		session.sandbox.replace_sandbox(st, ProfileSandbox.kit_abilities(st))
	_phase = Phase.RUNNING
	_restart_pending = true
	_restart_full = true
	SceneRouter.goto_room.call_deferred(ch.stage_room(0), ch.stage_entry(0))
	EventBus.challenge_reset.emit(ch.id, &"menu")


# --- Run events ----------------------------------------------------------------------

## Room.death_override: the run owns every death (no Game.on_player_death, no
## scrap drop, no Anchor respawn).
func _on_run_death(player: Player) -> bool:
	if session == null:
		return false
	if _phase != Phase.RUNNING:
		return true
	match session.challenge.on_death:
		ChallengeData.OnDeath.END_RUN:
			finish(ChallengeData.Outcome.DIED)
		ChallengeData.OnDeath.FINISH:
			finish(ChallengeData.Outcome.FINISHED)
		ChallengeData.OnDeath.RESTART_STAGE:
			session.stage_deaths += 1
			_restart_after_death(player.combat.config.respawn_delay)
	return true


## Timer nodes, not SceneTreeTimers: they die with this node, so a quit
## mid-wait leaks nothing at exit.
func _restart_after_death(delay: float) -> void:
	_death_timer.start(maxf(delay, 0.01))


func _on_death_timer() -> void:
	if session and _phase == Phase.RUNNING:
		restart(&"death")


func _on_rule_fail(outcome: int, cause: String) -> void:
	if session == null or _phase != Phase.RUNNING:
		return
	session.cause = cause
	finish(outcome)


func _on_finish_line() -> void:
	if session and _phase == Phase.RUNNING:
		if not clock.running:
			clock.start()
		finish(ChallengeData.Outcome.FINISHED)


func _on_boss_started(boss: Node2D, _title: String) -> void:
	if session == null or _phase != Phase.RUNNING or clock.running:
		return
	var ch := session.challenge
	if ch.start_on != ChallengeData.StartOn.BOSS_STARTED:
		return
	var want := ch.boss_id
	var st := ch.stage(session.stage_index)
	if st and st.boss_id != "":
		want = st.boss_id
	if want == "" or BossArena.id_of(boss) == want:
		clock.start()


func _on_boss_defeated(boss_id: String) -> void:
	if session == null or _phase != Phase.RUNNING:
		return
	var ch := session.challenge
	if ch.end_on == ChallengeData.EndOn.BOSS_DEFEATED and boss_id == ch.boss_id:
		finish(ChallengeData.Outcome.FINISHED)
	elif ch.split_boss and clock.running and not _goal_owns_boss_split(boss_id):
		_split()


## A staged run (or a stage or ChallengeGoal tied to this boss) splits in
## goal_reached; a boss split here too would count one kill twice.
func _goal_owns_boss_split(boss_id: String) -> bool:
	var ch := session.challenge
	if ch.stages.size() > 1:
		return true
	var st := ch.stage(session.stage_index)
	if st and st.boss_id != "":
		return true
	var room := _room()
	if room:
		for g in room.find_children("*", "ChallengeGoal", true, false):
			if (g as ChallengeGoal).on_boss == boss_id:
				return true
	return false


func _on_style_changed(points: float, rank: int) -> void:
	if session and _phase == Phase.RUNNING:
		session.on_style(points, rank)


## A stage goal (ChallengeGoal): the stage's split and rank, then the next
## stage, or the finish.
func goal_reached(goal: Node) -> void:
	if session == null or _phase != Phase.RUNNING:
		return
	var ch := session.challenge
	var st := ch.stage(session.stage_index)
	var goal_stage := str(goal.get("stage_id")) if goal else ""
	if st and goal_stage != "" and goal_stage != st.id:
		return
	if not clock.running:
		clock.start()
	var result := stage_result()
	session.stage_results.append(result)
	_split()
	if st:
		records.submit_stage(ch, Game.profile_id, st.id, result)
	EventBus.challenge_stage_cleared.emit(ch.id, str(result["id"]), int(result["frames"]), int(result["hits"]),
		int(result["deaths"]), int(result["tier"]))
	if session.stage_index + 1 < ch.stage_count():
		session.stage_index += 1
		session.reset_stage(false)
		if rules:
			rules.hits = 0
		var room := _room()
		if room and is_instance_valid(room.player):
			_freeze(room.player)
		SceneRouter.transition_to(ch.stage_room(session.stage_index), ch.stage_entry(session.stage_index))
	else:
		finish(ChallengeData.Outcome.FINISHED)


## The current stage's numbers: {id, title, frames, hits, deaths, style,
## score, tier}. score/tier come from the rank table for RANK runs.
func stage_result() -> Dictionary:
	var ch := session.challenge
	var st := ch.stage(session.stage_index)
	var frames := session.stage_frames
	var hits := rules.hits if rules else session.stage_hits
	var deaths := session.stage_deaths
	var avg := session.avg_style_rank()
	var score := -1
	var tier := 0
	if ch.score_kind == ChallengeData.ScoreKind.RANK and ch.rank_table:
		var secs := float(frames) / RunClock.FPS
		score = ch.rank_table.score(secs, hits, deaths, avg, st)
		tier = ch.rank_table.rank_of(score, secs, hits, deaths, st)
	return {"id": st.id if st else ch.id, "title": st.title if st else ch.title, "frames": frames, "hits": hits,
		"deaths": deaths, "style": snappedf(avg, 0.01), "score": score, "tier": tier}


## The live projection for the HUD (a RANK stage's tier so far; for others
## the medal the current value would earn).
func projected_rank() -> int:
	if session == null:
		return -1
	var ch := session.challenge
	match ch.score_kind:
		ChallengeData.ScoreKind.RANK:
			return int(stage_result()["tier"])
		ChallengeData.ScoreKind.SCORE:
			return ch.medal_for(score_value())
	return ch.medal_for(clock.frames)


## SCORE runs: the room's score provider (group challenge_score, T10's
## WaveDirector), else the style score (the positive style deltas).
func score_value() -> int:
	var provider := _score_provider()
	if provider:
		return int(provider.call("score"))
	return roundi(session.style_score) if session else 0


## The provider's current wave (1-based), 0 when there is none.
func wave_number() -> int:
	var provider := _score_provider()
	if provider == null:
		return 0
	var w: Variant = provider.get("wave")
	return int(w) if w != null else 0


func _score_provider() -> Node:
	if not is_inside_tree():
		return null
	var room := _room()
	if room == null:
		return null
	for n in get_tree().get_nodes_in_group(&"challenge_score"):
		if n.has_method("score") and room.is_ancestor_of(n):
			return n
	return null


# --- Finish --------------------------------------------------------------------------

## Ends the attempt: the value and medal, the record (with the neutral tags),
## the PB ghost on a new best, the platform mirror, challenge_finished, then
## the result card after a beat. A score provider (the Pulse Pit waves) may
## call it with FINISHED when its set is cleared.
func finish(outcome: int) -> void:
	if session == null or _phase != Phase.RUNNING:
		return
	_phase = Phase.FINISHING
	clock.stop()
	if rules:
		rules.armed = false
	var ch := session.challenge
	var value := -1
	var medal := -1
	if outcome == ChallengeData.Outcome.FINISHED:
		match ch.score_kind:
			ChallengeData.ScoreKind.TIME:
				value = clock.frames
				medal = ch.medal_for(value)
			ChallengeData.ScoreKind.SCORE:
				value = score_value()
				medal = ch.medal_for(value)
			ChallengeData.ScoreKind.RANK:
				if session.stage_results.is_empty():
					session.stage_results.append(stage_result())
				var scores: Array = session.stage_results.map(func(r: Dictionary) -> int: return int(r["score"]))
				value = RankTable.mean_score(scores)
				medal = ch.rank_table.run_rank(session.stage_results) if ch.rank_table else 0
	_union_tags()
	var extra := {"medal": medal, "cause": session.cause, "stages": session.stage_results.duplicate(true),
		"score_kind": ch.score_kind, "title": ch.title, "frames": clock.frames, "splits": Array(clock.splits)}
	last_result = records.submit(ch, Game.profile_id, value, outcome, clock.splits, session.tags(), extra)
	var g := recorder.finish(outcome) if recorder else null
	if bool(last_result.get("new_best", false)) and g:
		records.save_pb_ghost(ch.id, Game.profile_id, g)
	if value >= 0:
		Platform.submit_score("ch_" + ch.id, value, {"medal": medal, "profile": Game.profile_id,
			"assists": Array(session.assists), "timing": Array(session.timing)})
	session.last_outcome = outcome
	if outcome == ChallengeData.Outcome.FINISHED:
		session.finished_once = true
	EventBus.challenge_finished.emit(ch.id, outcome, value, medal, bool(last_result.get("new_best", false)))
	var room := _room()
	if room and is_instance_valid(room.player):
		_freeze(room.player)
	_open_card_later()


## The card timer runs while paused too: an open screen delays the card (the
## host's open_when_free queue), it never drops it (R04.2).
func _open_card_later() -> void:
	_card_timer.start(maxf(ChallengeConfig.shared().finish_card_delay_s, 0.01))


func _on_card_timer() -> void:
	if session == null or _phase != Phase.FINISHING:
		return
	_phase = Phase.FINISHED
	var host := _host()
	if host and host.has_method("open_when_free"):
		_card_requested = true
		host.call("open_when_free", &"challenge_result", {"result": last_result.duplicate(true)})


func _cancel_card() -> void:
	_card_requested = false
	var host := _host()
	if host == null:
		return
	var q: Array = host.get("_queued")
	for i in range(q.size() - 1, -1, -1):
		if (q[i] as Array).size() > 0 and q[i][0] == &"challenge_result":
			q.remove_at(i)


## R04.28: the record's tags are the union over the whole attempt.
func _union_tags() -> void:
	if session == null:
		return
	var assists := PackedStringArray()
	var provided: PackedStringArray = tag_provider.call() if tag_provider.is_valid() else PackedStringArray()
	var forced := session.challenge.kit != null and session.challenge.kit.reactor_mode >= 0
	for t in provided:
		if forced and REACTOR_TAGS.has(t):
			continue
		assists.append(t)
	var timing := PackedStringArray()
	if Settings.hitstop_scale < 1.0:
		timing.append(TAG_HITSTOP)
	session.add_tags(assists, timing)


# --- Quit ------------------------------------------------------------------------------

## Leaves the run: the profile objects come back, earned on_finish_flags are
## set on the PROFILE and saved, then Rook returns to where the run began (or
## the title). Never emits challenge_reset.
func quit() -> void:
	if session == null or _phase == Phase.STARTING or _phase == Phase.LEAVING or SceneRouter.transitioning:
		return
	var ch := session.challenge
	if _phase == Phase.RUNNING:
		EventBus.challenge_finished.emit(ch.id, ChallengeData.Outcome.QUIT, -1, -1, false)
	_cancel_card()
	CinematicMode.abort_all()
	var ret := session.return_to
	Game.suppress_leave_capture = true
	if bool(ret.get("title", false)):
		_leave_run(true)
		var host := _host()
		if host and host.has_signal("quit_to_title"):
			host.emit_signal("quit_to_title")
		else:
			Game.suppress_leave_capture = false
	elif str(ret.get("room", "")) != "" and SceneRouter.world_root != null:
		var room := _room()
		if room and is_instance_valid(room.player):
			_freeze(room.player)
		_phase = Phase.LEAVING
		_pending_return = true
		SceneRouter.transition_to(str(ret["room"]), StringName(str(ret.get("entry", ""))))
	else:
		_leave_run(true)
		Game.suppress_leave_capture = false


## Restores the profile, applies earned outcomes, saves, and ends the session.
func _leave_run(emit_reset: bool) -> void:
	if session == null:
		return
	var ch := session.challenge
	CinematicMode.theatre = session.theatre_was
	var sb := session.sandbox
	var earned := session.finished_once
	_end_session()
	if sb == null:
		return
	sb.restore(emit_reset)
	if earned and Game.state == sb.profile and not ch.on_finish_flags.is_empty():
		for f in ch.on_finish_flags:
			Game.set_flag(f)
		Game.save_game()


func _stop_timers() -> void:
	_death_timer.stop()
	_card_timer.stop()


func _end_session() -> void:
	_stop_timers()
	if rules:
		rules.disconnect_all()
	rules = null
	if recorder:
		recorder.discard()
	recorder = null
	ghosts.clear()
	_actors.clear()
	session = null
	_phase = Phase.IDLE
	_pending_swap = []
	_restart_pending = false
	_start_next_tick = false
	_card_requested = false
	clock.reset()
	hud.reset()


# --- Ghost mode ----------------------------------------------------------------------

func ghost_mode_label() -> String:
	var names := ChallengeConfig.shared().ghost_mode_names
	var m := clampi(Settings.challenge_ghost, 0, names.size() - 1)
	return Loc.t(names[m]) if names.size() > 0 else ""


## Off -> PB -> rig -> both; saved at once (the pause row and the result card).
func cycle_ghost_mode() -> void:
	Settings.challenge_ghost = (Settings.challenge_ghost + 1) % 4
	Settings.save_settings()
	if session == null:
		return
	_load_ghosts()
	for a in _actors:
		if is_instance_valid(a):
			a.queue_free()
	_actors.clear()
	var room := _room()
	if room:
		for pb in ghosts:
			var a := GhostActor.new(pb, SceneRouter.current_room_path)
			room.add_child(a)
			a.show_frame(clock.frames)
			_actors.append(a)


# --- Unlocks and the group-open notice (R04.6, R04.19, R04.25, R04.27) -----------

func _on_game_state_reset() -> void:
	campaign.refresh_tags()
	_note_unlocks(false)


func _on_flag_changed(_id: String, _value: Variant) -> void:
	if session == null:
		campaign.check_splits()
	_note_unlocks(true)


func _on_room_entered(_district: String, _room_name: String) -> void:
	if session == null:
		campaign.note_room(SceneRouter.current_room_path)


func _on_settings_changed() -> void:
	campaign.refresh_tags()
	if session:
		_union_tags()


## Records newly met unlocks (silently on loads and resets). A live flag
## change in play may show one neutral hint the first time a group opens at
## the rig; a blocked notice is dropped, never queued.
func _note_unlocks(live: bool) -> void:
	if _unlock_blocked():
		return
	ChallengeLibrary.record_unlocks()
	if not live:
		_announce(false)
	elif not _notice_pending:
		# One check per frame: a flag and the flags it derives (act1_complete
		# -> null_open) open their groups in one hint.
		_notice_pending = true
		_flush_notice.call_deferred()


func _flush_notice() -> void:
	if not _notice_pending:
		return
	_notice_pending = false
	if not _unlock_blocked():
		_announce(true)


## Unlocks never record from fabricated states (R04.19) or the sandbox.
func _unlock_blocked() -> bool:
	return ChallengeLibrary.recording_blocked()


## Marks groups that opened at the rig; `show` = a live change in play.
## A live notice held back by a passing block (the Act I close sets
## act1_complete under its locking scene, a menu, the pause, a lab room) is
## owed: the groups stay unannounced and the notice shows once free play
## resumes (_poll_owed_notice). Tours (quiet_notices) drop it for good, and
## a load or reset marks everything silently.
func _announce(show: bool) -> void:
	if not ChallengeLibrary.rig_open():
		_notice_owed = false
		return
	var fresh: Array[int] = []
	for g in ChallengeLibrary.unlocked_groups():
		if not records.group_announced(g):
			fresh.append(g)
	if fresh.is_empty():
		_notice_owed = false
		return
	var speak := show and not quiet_notices
	if speak and not _notice_allowed():
		_notice_owed = true
		return
	_notice_owed = false
	var titles := PackedStringArray()
	for g in fresh:
		records.mark_group_announced(g)
		titles.append(Loc.t(ChallengeLibrary.group_title(g)))
	if speak:
		EventBus.hint_requested.emit(Loc.f("New at the Relay training rig: {group}", {"group": ", ".join(titles)}),
			ChallengeConfig.shared().suggest_new_group_hint_s)


## An owed notice shows on the first free-play frame (checked every few
## frames outside runs).
func _poll_owed_notice() -> void:
	_owed_tick += 1
	if _owed_tick < OWED_CHECK_FRAMES:
		return
	_owed_tick = 0
	if _unlock_blocked() or not _notice_allowed():
		return
	_announce(true)


func _notice_allowed() -> bool:
	if quiet_notices or Cinematics.locks_input() or (is_inside_tree() and get_tree().paused):
		return false
	var host := _host()
	if host and host.has_method("any_open") and bool(host.call("any_open")):
		return false
	var room := _room()
	return room != null and room.world_room and not CampaignClock._off_map(SceneRouter.current_room_path)


# --- Helpers ---------------------------------------------------------------------------

func _room() -> Room:
	if not is_instance_valid(SceneRouter.current_room):
		return null
	return SceneRouter.current_room as Room


func _host() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(&"menu_host")


## The same freeze Cinematics uses: no input, no damage, no prompt.
static func _freeze(p: Player) -> void:
	if p == null or not is_instance_valid(p):
		return
	p.input_override = ScriptedInputSource.new()
	p.cinematic_lock = true


## DebugOverlay provider (F1).
func debug_lines() -> PackedStringArray:
	if session == null:
		return PackedStringArray()
	var ch := session.challenge
	return PackedStringArray(["RUN %s stage %d/%d f=%d hits=%d proj=%s" % [ch.id, session.stage_index + 1,
		ch.stage_count(), clock.frames, rules.hits if rules else 0, RankLadder.name(projected_rank())]])


## TestRunner teardown: quits any live run without a transition, restores the
## held profile, and puts every seam back.
func reset_for_tests() -> void:
	force_active = false
	force_reactor_mode = -1
	force_finishing = false
	quiet_notices = false
	if session and session.sandbox:
		session.sandbox.restore(false)
	Game.held_profile = null
	_pending_return = false
	_reset_on_load = false
	_notice_pending = false
	_notice_owed = false
	_owed_tick = 0
	_end_session()
	_reset_down = false
	_reset_hold = 0
	_hold_fired = false
	last_result = {}
	tag_provider = _default_tags
	records = RecordStore.new()
	campaign = CampaignClock.new()
	_wire_campaign()
	ChallengeLibrary.data_dir = ChallengeLibrary.DEFAULT_DIR
	ChallengeLibrary.recording_holds = 0
	ChallengeLibrary.clear_cache()
