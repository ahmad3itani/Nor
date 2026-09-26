extends Node
## M4 validation instrumentation (bible §36 M4: "measure deaths, completion
## time, confusion, favorite mechanics, control complaints and performance").
##
## Records one PlaytestSession per slice run to user://playtests/*.json, on
## the tester's own machine only: nothing is ever sent over the network.
## Recording is visible (title screen line) and can be switched off in
## Settings. It only listens to EventBus and polls the player; gameplay code
## never depends on it, so turning it off changes nothing about the game.

const CONFIG := preload("res://data/playtest/playtest_config.tres")
const DIR := "user://playtests"
## Flags worth a timeline entry (M7 Undercity onboarding beats). Every other
## flag is left out to keep session files small; hint_* flags are always kept.
## Tuning note: add a flag here when a new onboarding beat needs timing data.
const RECORDED_FLAGS: PackedStringArray = ["core_hud_hidden", "got_pulse_blade", "got_service_pistol", "met_orr_radio", "uc_ward_shutter"]

## Pre-M9 EventBus signals Playtest deliberately does not record, each with
## why (CrossRules X-3: every signal is either recorded here or listed).
const UNRECORDED_SIGNALS := {
	"player_respawned": "room_enter covers respawns",
	"player_landed": "per-frame movement noise",
	"camera_shake_requested": "presentation only",
	"camera_impulse_requested": "presentation only",
	"room_loaded": "room_enter is the §44 room event",
	"movement_config_changed": "dev tuning",
	"movement_config_reload_requested": "dev tuning",
	"ranged_weapon_changed": "loadout snapshot in _meta",
	"reactor_changed": "per-frame meter",
	"game_state_reset": "session boundary is begin_session",
	"scrap_changed": "scrap_* events cover it",
	"interact_prompt_changed": "UI only",
	"dialogue_finished": "dialogue_* events cover it",
	"menu_requested": "menu_open covers it",
	"memory_playback_requested": "memory_* story events cover it",
	"memory_playback_finished": "memory_* story events cover it",
	"memory_playback_aborted": "memory_* story events cover it",
	"collectible_taken": "collect events cover it",
}

var config: PlaytestConfig = CONFIG
## Where session files go (tests point this at a temp folder).
var dir: String = DIR
## Headless runs (tests, probes) never record unless a test opts in.
var allow_headless: bool = false
var session: PlaytestSession = null
var variant: PlaytestVariant = null
var session_path: String = ""

var _t: float = 0.0
var _sample_acc: float = 0.0
var _save_acc: float = 0.0
var _last_usec: int = 0
var _room: String = ""
var _room_since: float = 0.0
var _was_paused: bool = false
var _player: Player
var _dodge_seen: bool = false
## sequence id -> {first, locked} of the play in progress (seq_end copies it).
var _seq_open: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.room_entered.connect(_on_room_entered)
	EventBus.room_leaving.connect(func(_r: Node) -> void: _end_room("leave"))
	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.player_died.connect(_on_player_died)
	EventBus.player_healed.connect(func(hp: int) -> void: _event("heal", {"hp": hp}))
	EventBus.anchor_rested.connect(func(a: Node) -> void:
		_event("anchor_rest", {"anchor": String((a as Anchor).anchor_id) if a is Anchor else ""}))
	EventBus.secret_found.connect(func(id: String) -> void: _event("secret", {"id": id}))
	EventBus.memory_fragment_found.connect(func(f: Resource) -> void:
		_event("fragment", {"id": (f as MemoryFragmentData).id if f is MemoryFragmentData else ""}))
	EventBus.quest_updated.connect(func(q: Resource) -> void:
		var qd := q as QuestData
		if qd:
			_event("quest", {"id": qd.id, "stage": qd.current_stage(), "done": Game.has_flag(qd.complete_flag)}))
	EventBus.dialogue_requested.connect(func(_d: Resource, npc: String) -> void: _event("dialogue", {"npc": npc}))
	EventBus.item_purchased.connect(func(shop: StringName, item: String, price: int) -> void:
		_event("purchase", {"shop": String(shop), "item": item, "price": price}))
	EventBus.circuit_granted.connect(func(id: String) -> void: _event("circuit_granted", {"id": id}))
	EventBus.weapon_granted.connect(func(id: String) -> void: _event("weapon_granted", {"id": id}))
	EventBus.loadout_changed.connect(func() -> void: _event("loadout", _loadout()))
	EventBus.hint_requested.connect(func(text: String, _s: float) -> void: _event("hint", {"text": text}))
	EventBus.boss_started.connect(func(b: Node2D, title: String) -> void: _event("boss_start", {"boss": title, "id": _boss_id_of(b)}))
	EventBus.boss_phase_changed.connect(func(_b: Node2D, phase: int) -> void: _event("boss_phase", {"phase": phase}))
	EventBus.boss_defeated.connect(func(id: String) -> void: _event("boss_defeated", {"boss": id}))
	EventBus.slice_completed.connect(_on_slice_completed)
	EventBus.perfect_dodge.connect(func(_a: Node2D) -> void: _count("perfect_dodges"))
	EventBus.ranged_fired.connect(func(w: Resource, _ammo: int) -> void:
		_count("shots:%s" % (w as WeaponData).id if w is WeaponData else "shots:?"))
	EventBus.enemy_damaged.connect(_on_enemy_damaged)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.style_changed.connect(_on_style_changed)
	EventBus.settings_changed.connect(func() -> void: _event("settings", _settings_snapshot()))
	# M5: map use is a confusion signal; transit shows how the world is travelled.
	EventBus.map_opened.connect(func() -> void: _event("map_open"))
	EventBus.map_pins_changed.connect(func() -> void: _count("pin_changes"))
	EventBus.fast_traveled.connect(func(from: String, to: String) -> void:
		_event("fast_travel", {"from": from.get_file(), "to": to.get_file()}))
	# M7: onboarding beats (first dodge, hint and HUD flags) for the Undercity
	# timeline, and the district set pieces.
	EventBus.player_state_changed.connect(_on_player_state_changed)
	EventBus.flag_changed.connect(_on_flag_changed)
	EventBus.breaker_hit.connect(func(circuit: StringName) -> void: _event("breaker", {"circuit": String(circuit)}))
	EventBus.shutter_passed.connect(func(id: String, margin: float) -> void:
		_event("shutter", {"id": id, "margin": snappedf(margin, 0.01)}))
	EventBus.scanner_tripped.connect(_on_scanner_tripped)
	EventBus.clamp_dropped.connect(func(id: String, staggered: bool) -> void: _event("clamp", {"id": id, "staggered": staggered}))
	EventBus.chase_started.connect(func(id: String) -> void: _event("chase_start", {"id": id}))
	EventBus.chase_caught.connect(func(id: String, cp: int) -> void: _event("chase_caught", {"id": id, "cp": cp}))
	EventBus.chase_completed.connect(func(id: String, seconds: float, catches: int, min_lead: float) -> void:
		_event("chase_done", {"id": id, "seconds": snappedf(seconds, 0.01), "catches": catches, "min_lead": snappedf(min_lead, 0.01)}))
	EventBus.tracker_locked.connect(func(id: String) -> void: _event("tracker_lock", {"id": id}))
	# M8 narrative: sequences, memory vignettes, arcs, the Act I choice and
	# endings. Dev replays (the Ending theatre, sequence previews) set
	# CinematicMode.theatre and their sequence events are dropped, so skip
	# rates only count real views. Ending events carry `theatre` instead (the
	# analyzer ignores those).
	EventBus.sequence_started.connect(_on_sequence_started)
	EventBus.sequence_finished.connect(_on_sequence_finished)
	EventBus.memory_scene_started.connect(func(id: String, source: StringName) -> void:
		_event("memory_start", {"id": id, "source": String(source)}))
	EventBus.memory_scene_finished.connect(_on_memory_finished)
	EventBus.arc_stage_entered.connect(func(npc: String, stage: String, on_load: bool) -> void:
		if not on_load:
			_event("arc", {"npc": npc, "stage": stage}))
	EventBus.dialogue_choice_made.connect(func(dialogue: String, choice: String) -> void:
		_event("choice", {"dialogue": dialogue, "choice": choice}))
	EventBus.ending_started.connect(func(id: String, theatre: bool) -> void:
		_event("ending_start", {"id": id, "theatre": theatre}))
	EventBus.ending_finished.connect(func(id: String, theatre: bool, skipped: bool) -> void:
		_event("ending", {"id": id, "theatre": theatre, "skipped": skipped}))
	# M9 endgame: achievements, challenge runs, splits, NG+, rebinding,
	# assist offers, language and the demo boundary.
	EventBus.achievement_unlocked.connect(func(id: String, retro: bool) -> void:
		_event("achievement", {"id": id, "retro": retro}))
	EventBus.challenge_started.connect(func(id: String, attempt: int) -> void:
		_event("challenge_start", {"id": id, "attempt": attempt}))
	EventBus.challenge_finished.connect(func(id: String, outcome: int, value: int, medal: int, new_best: bool) -> void:
		_event("challenge_end", {"id": id, "outcome": outcome, "value": value, "medal": medal, "new_best": new_best}))
	EventBus.challenge_reset.connect(func(id: String, reason: StringName) -> void:
		_event("challenge_reset", {"id": id, "reason": String(reason)}))
	EventBus.challenge_stage_cleared.connect(func(id: String, stage: String, frames: int, hits: int, deaths: int, medal: int) -> void:
		_event("challenge_stage", {"id": id, "stage": stage, "frames": frames, "hits": hits, "deaths": deaths, "medal": medal}))
	EventBus.speedrun_split.connect(func(id: String, igt: int, delta: int) -> void:
		_event("split", {"id": id, "igt": igt, "delta": delta}))
	EventBus.ng_plus_started.connect(func(cycle: int) -> void: _event("ng_plus", {"cycle": cycle}))
	EventBus.input_bindings_changed.connect(func(action: StringName) -> void:
		_event("rebind", {"action": String(action)}))
	EventBus.assist_suggested.connect(func(context: String, cause: String, deaths: int) -> void:
		_event("assist_suggested", {"context": context, "cause": cause, "deaths": deaths}))
	EventBus.assist_suggestion_answered.connect(func(context: String, answer: StringName, key: String) -> void:
		_event("assist_answered", {"context": context, "answer": String(answer), "key": key}))
	EventBus.locale_changed.connect(func(locale: String) -> void: _event("locale", {"locale": locale}))
	EventBus.demo_boundary_reached.connect(func(from: String, to: String) -> void:
		_event("demo_end", {"from": from, "to": to}))


func recording_allowed() -> bool:
	if not Settings.playtest_recording:
		return false
	return allow_headless or DisplayServer.get_name() != "headless"


func is_recording() -> bool:
	return session != null


## Called when the player starts or continues the slice from the title.
## `kind` is "new" (New Game, starts in the Undercity), "new_relay" (the debug
## 'Slice (Relay start)' entry) or "continue".
func begin_session(kind: String) -> void:
	if session:
		end_session("replaced")
	if not recording_allowed():
		return
	variant = _pick_variant()
	_t = 0.0
	_sample_acc = 0.0
	_save_acc = 0.0
	_room = ""
	_dodge_seen = false
	_last_usec = Time.get_ticks_usec()
	var stamp := Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "")
	session_path = "%s/session_%s_%04d.json" % [dir, stamp, randi() % 10000]
	session = PlaytestSession.new(_meta(kind))
	_event("session_start", {"kind": kind, "variant": variant.id if variant else ""})
	_event("loadout", _loadout())
	if is_instance_valid(_player) and variant:
		variant.apply_to_player(_player)
	flush()


func end_session(reason: String) -> void:
	if session == null:
		return
	_end_room("session_end")
	_event("session_end", {"reason": reason, "play_time": Game.state.play_time_sec, "deaths": Game.state.deaths})
	session.data["ended"] = reason
	flush()
	session = null
	variant = null


func flush() -> void:
	if session == null:
		return
	session.data["duration"] = snappedf(_t, 0.01)
	var err := session.save(session_path)
	if err != OK:
		push_warning("Playtest: could not write %s (%s)" % [session_path, error_string(err)])


## "Report a moment" (pause menu): a tag plus an optional note, stamped with
## where the player was, so the report can place confusion on the map.
func report_moment(tag: String, note: String = "") -> void:
	_event("moment", {"tag": tag, "note": note})
	flush()


func submit_survey(answers: Dictionary) -> void:
	if session == null:
		return
	session.data["survey"] = answers
	_event("survey", {"answered": answers.size()})
	flush()


func session_time() -> float:
	return _t


# --- Per-frame sampling -----------------------------------------------------

func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last_usec) / 1000.0
	_last_usec = now
	if session == null:
		return
	# M8 scene time. A memory vignette pauses the tree itself, so it is
	# checked first and counts as cinematic_s, never as a pause (no 'pause'
	# event, no paused_s). A locking sequence counts only while the tree runs:
	# under the PauseMenu it is paused_s alone, so the report's "minus
	# cinematic_s" column never subtracts pause time twice.
	var memory := is_instance_valid(MemoryScenePlayer.active_instance) and MemoryScenePlayer.active_instance.is_playing()
	if memory or (Cinematics.locks_input() and not get_tree().paused):
		_count("cinematic_s", delta)
	if memory:
		_was_paused = get_tree().paused
		return
	var paused := get_tree().paused
	if paused and not _was_paused:
		_event("pause")
	_was_paused = paused
	if paused:
		_count("paused_s", delta)
		return
	_t += delta
	# Real frame time (not delta, which the engine clamps): this is what a
	# tester on real hardware actually saw.
	session.add_frame(_t, _room, frame_ms, config.spike_ms, config.max_spikes)
	_count("input_pad_s" if InputGlyphs.using_pad else "input_keyboard_s", delta)
	_sample_acc += delta
	# No position samples while a scene holds the player: the gap splits
	# idle_spans, so watching a scene never reads as standing still, confused.
	if Cinematics.locks_input():
		_sample_acc = 0.0
	elif _sample_acc >= config.sample_interval and is_instance_valid(_player) and _room != "":
		_sample_acc = 0.0
		session.add_sample(_t, _room, _player.global_position)
	_save_acc += delta
	if _save_acc >= config.autosave_interval:
		_save_acc = 0.0
		flush()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		end_session("window_closed")


## Last-chance write on shutdown. Other autoloads may already be gone, so
## only the session's own data is touched here.
func _exit_tree() -> void:
	if session:
		if session.data["ended"] == "":
			session.data["ended"] = "exit"
		flush()


# --- Event handlers -------------------------------------------------------------

func _on_room_entered(_district: String, _room_name: String) -> void:
	var room := SceneRouter.current_room as Room
	if room == null or not room.world_room:
		return
	_room = SceneRouter.current_room_path.get_file().get_basename()
	_room_since = _t
	var entry := String(room.active_spawn().spawn_id) if not room.spawns.is_empty() else ""
	_event("room_enter", {"entry": entry})


func _end_room(reason: String) -> void:
	if session == null or _room == "":
		return
	_event("room_exit", {"seconds": snappedf(_t - _room_since, 0.01), "reason": reason})


func _on_player_spawned(p: Node2D) -> void:
	_player = p as Player
	if session and variant and _player:
		variant.apply_to_player(_player)


func _on_player_state_changed(_from: StringName, to: StringName) -> void:
	if to != &"dodge" and to != &"dash":
		return
	_count("dodges")
	if not _dodge_seen and session:
		_dodge_seen = true
		_event("dodge_first", {"state": String(to)})


func _on_flag_changed(id: String, value: Variant) -> void:
	if id.begins_with("hint_") or RECORDED_FLAGS.has(id):
		_event("flag", {"id": id, "value": value})


## Errata #15: scanner trips are reported split into live and calibration.
## The typed signal carries no marker, so the beam is looked up by the
## roomgen name Hazards/Scanner_<beam_id> and its data read duck-typed
## (ScannerBeam lands in M6): calibration = its ScannerData deals 0 damage.
## A missing node or data counts as live.
func _on_scanner_tripped(id: String, mode: int) -> void:
	_event("scanner", {"id": id, "mode": mode, "calibration": _is_calibration_beam(id)})


func _is_calibration_beam(id: String) -> bool:
	var room := SceneRouter.current_room
	if room == null:
		return false
	var beam := room.get_node_or_null(NodePath("Hazards/Scanner_" + id))
	if beam == null:
		return false
	var data: Variant = beam.get("data")
	if not (data is Object) or data == null:
		return false
	var dmg: Variant = (data as Object).get("damage")
	return dmg != null and int(dmg) == 0


## The boss_id of the arena in the current room that runs this boss ("" when
## none does), so bosses are told apart by id rather than banner title.
func _boss_id_of(b: Node2D) -> String:
	var room := SceneRouter.current_room
	if room == null or b == null:
		return ""
	for n in room.find_children("*", "BossArena", true, false):
		if (n as BossArena).boss == b:
			return (n as BossArena).boss_id
	return ""


func _cause() -> String:
	return _player.combat.last_damage_source if is_instance_valid(_player) else "unknown"


func _on_player_damaged(amount: int, health: int) -> void:
	_event("damage", {"amount": amount, "hp": health, "cause": _cause()})


func _on_player_died() -> void:
	_event("death", {"cause": _cause()})
	flush()


func _on_slice_completed() -> void:
	var t := SliceStats.totals()
	_event("slice_complete", {
		"play_time": Game.state.play_time_sec, "deaths": Game.state.deaths,
		"secrets": SliceStats.secrets_found(), "secrets_total": (t["secret_ids"] as Array).size(),
		"fragments": Game.state.memory_fragments.size(), "shards": Game.state.core_shards,
		"dead_air": Game.has_flag("dead_air_complete"),
		# M8: what the player leaves Act I with (memories, people, the card).
		"memories": MemoryLibrary.remembered_count(),
		"memory_details": _count_flags("mem_detail_"),
		"memories_pending": MemoryLibrary.pending().size(),
		"arc_beats_heard": _count_flags("arcbeat_"),
		"arcs": _arc_stages(),
		"orr_air": "named" if Game.has_flag("orr_air_named") else ("ghost" if Game.has_flag("orr_air_ghost") else "none"),
		"act1_complete": Game.has_flag("act1_complete"),
		"standing": Array(ActLibrary.standing_lines(ActLibrary.act(1))),
	})
	flush()


## seq_end repeats its start's `first` and `locked`, so the analyzer reads one
## event per view. locked = the play held the player (barks and retry intros
## do not): only those seconds sit inside the session clocks as scene time.
func _on_sequence_started(id: String, first_view: bool) -> void:
	if CinematicMode.theatre:
		return
	_seq_open[id] = {"first": first_view, "locked": Cinematics.locks_input()}
	_event("seq_start", {"id": id, "first": first_view})


func _on_sequence_finished(id: String, skipped: bool, seconds: float, step: int, step_count: int, nominal: float) -> void:
	if CinematicMode.theatre:
		return
	var open: Dictionary = _seq_open.get(id, {})
	_seq_open.erase(id)
	_event("seq_end", {"id": id, "skipped": skipped, "seconds": snappedf(seconds, 0.01), "step": step,
		"of": step_count, "nominal": snappedf(nominal, 0.01), "first": bool(open.get("first", false)),
		"locked": bool(open.get("locked", false))})


func _on_memory_finished(id: String, source: StringName, skipped: bool, seconds: float, beats: int, detail: bool, first: bool) -> void:
	_event("memory_end", {"id": id, "source": String(source), "skipped": skipped, "seconds": snappedf(seconds, 0.01),
		"beats": beats, "detail": detail, "first": first})


## Set flags with this prefix (bool true or int > 0).
func _count_flags(prefix: String) -> int:
	var n := 0
	for k: String in Game.state.flags:
		if k.begins_with(prefix) and Game.has_flag(k):
			n += 1
	return n


## {npc: spine index reached} for every arc the tracker knows.
func _arc_stages() -> Dictionary:
	var out := {}
	if Game.arcs == null:
		return out
	for a: NpcArc in Game.arcs.arcs:
		if a != null:
			out[a.npc_id] = a.current_index()
	return out


func _on_enemy_damaged(_enemy: Node2D, hit: HitInfo, _result: int) -> void:
	if hit and hit.attack and hit.attacker == _player and _player != null:
		_count("hits:%s" % hit.attack.id)


func _on_enemy_killed(enemy: Node2D, hit: HitInfo) -> void:
	if enemy is Enemy and (enemy as Enemy).data:
		_count("kills:%s" % (enemy as Enemy).data.id)
	if hit and hit.attack and hit.attacker == _player and _player != null:
		_count("kill_attack:%s" % hit.attack.id)


func _on_style_changed(_points: float, rank: int) -> void:
	if session == null or _room == "":
		return
	var key := "style_max:%s" % _room
	var c: Dictionary = session.data["counters"]
	c[key] = maxf(float(c.get(key, 0.0)), float(rank))


# --- Helpers --------------------------------------------------------------------

func _event(type: String, extra: Dictionary = {}) -> void:
	if session == null:
		return
	var pos := _player.global_position if is_instance_valid(_player) else Vector2.ZERO
	# pt = cumulative play time, which survives Save & Quit / Continue (the
	# session clock `t` restarts with every session).
	var e := extra.duplicate()
	e["pt"] = snappedf(Game.state.play_time_sec, 0.01)
	session.add_event(_t, type, _room, pos, e)


func _count(key: String, amount: float = 1.0) -> void:
	if session:
		session.count(key, amount)


func _loadout() -> Dictionary:
	return {"melee": Game.state.melee_weapon, "ranged": Game.state.ranged_weapon,
		"circuits": Game.state.equipped_circuits.duplicate()}


func _settings_snapshot() -> Dictionary:
	return {"shake": Settings.screen_shake_scale, "hitstop": Settings.hitstop_scale,
		"flash_reduction": Settings.flash_reduction, "currency_loss": Settings.currency_loss,
		"core_mode": Settings.reactor_mode, "music": Settings.music_volume, "sfx": Settings.sfx_volume}


func _meta(kind: String) -> Dictionary:
	var info := Engine.get_version_info()
	return {
		"build": str(ProjectSettings.get_setting("application/config/version", "")),
		"godot": "%s.%s.%s" % [info.major, info.minor, info.patch],
		"started_utc": Time.get_datetime_string_from_system(true),
		"kind": kind,
		"variant": variant.id if variant else "",
		"os": OS.get_name(),
		"cpu": OS.get_processor_name(),
		"cores": OS.get_processor_count(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"refresh_hz": DisplayServer.screen_get_refresh_rate(),
		"window": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"physics_hz": Engine.physics_ticks_per_second,
		"settings": _settings_snapshot(),
	}


## Settings can force an arm; otherwise rotate through the variants using a
## per-install random offset, so different testers' first sessions spread
## across arms instead of everyone starting on the first one.
func _pick_variant() -> PlaytestVariant:
	if Settings.playtest_variant != "":
		var forced := config.variant(Settings.playtest_variant)
		if forced:
			return forced
	if config.variants.is_empty():
		return null
	var cfg := ConfigFile.new()
	var path := dir + "/install.cfg"
	cfg.load(path)
	var offset: int = cfg.get_value("playtest", "offset", randi() % 1000)
	var n: int = cfg.get_value("playtest", "sessions", 0)
	cfg.set_value("playtest", "offset", offset)
	cfg.set_value("playtest", "sessions", n + 1)
	DirAccess.make_dir_recursive_absolute(dir)
	cfg.save(path)
	return config.variants[(offset + n) % config.variants.size()]
