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
	EventBus.boss_started.connect(func(_b: Node2D, title: String) -> void: _event("boss_start", {"boss": title}))
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


func recording_allowed() -> bool:
	if not Settings.playtest_recording:
		return false
	return allow_headless or DisplayServer.get_name() != "headless"


func is_recording() -> bool:
	return session != null


## Called when the player starts or continues the slice from the title.
## `kind` is "new" or "continue".
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
	if _sample_acc >= config.sample_interval and is_instance_valid(_player) and _room != "":
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
	})
	flush()


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
	session.add_event(_t, type, _room, pos, extra)


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
