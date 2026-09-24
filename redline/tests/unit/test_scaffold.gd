extends RedlineTestCase
## M7 shared scaffolding: roomgen contract, district folders, the content
## protocol, RouteBot's new steps, pit override, nonlethal damage and shove,
## exported enemy facing, and the Undercity telemetry (recorder + analyzer).

const RELAY := "res://world/rooms/lowlight/Relay.tscn"
const PIT := "res://tests/fixtures/scaffold_pit.tscn"
const PROTOCOL := "res://tests/fixtures/scaffold_protocol.tscn"
const NEEDLE := preload("res://enemies/variants/Needle.tscn")
const PLAYER_SCENE := preload("res://player/Player.tscn")
const TEST_DIR := "user://test_scaffold_playtests"

var root: Node2D
var _saved_recording: bool
var _saved_variant: String


func before_each() -> void:
	_saved_recording = Settings.playtest_recording
	_saved_variant = Settings.playtest_variant
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	Game.new_game()


func after_each() -> void:
	Playtest.end_session("test_done")
	Playtest.allow_headless = false
	Playtest.dir = Playtest.DIR
	Settings.playtest_recording = _saved_recording
	Settings.playtest_variant = _saved_variant
	_clear_test_dir()
	SceneRouter.current_room = null
	SceneRouter.world_root = null
	root.queue_free()
	Game.new_game()
	await physics_frames(2)


func _clear_test_dir() -> void:
	if DirAccess.dir_exists_absolute(TEST_DIR):
		for f in DirAccess.get_files_at(TEST_DIR):
			DirAccess.remove_absolute("%s/%s" % [TEST_DIR, f])


func _record() -> void:
	Settings.playtest_recording = true
	Settings.playtest_variant = "baseline"
	Playtest.dir = TEST_DIR
	Playtest.allow_headless = true
	_clear_test_dir()
	Playtest.begin_session("new")


func _enter(path: String, entry: StringName) -> Room:
	SceneRouter.goto_room(path, entry)
	await physics_frames(10)
	return SceneRouter.current_room as Room


## Runs a python roomgen script from redline/ (the scripts use relative paths).
## -B keeps python from rewriting tools/roomgen/__pycache__: every gate runs
## this suite, and tracked .pyc churn would leak into parallel branches' commits.
func _python(script: String) -> int:
	var probe: Array = []
	if OS.execute("sh", ["-c", "command -v python3"], probe) != 0:
		push_warning("python3 not found: %s not run here (it is part of the gate)" % script)
		return 0
	var out: Array = []
	var code := OS.execute("sh", ["-c", "cd '%s' && python3 -B %s --check" % [ProjectSettings.globalize_path("res://"), script]], out, true)
	if code != 0:
		print(out)
	return code


# --- Roomgen and content folders -------------------------------------------------

func test_roomgen_lowlight_output_unchanged() -> void:
	check(_python("tools/roomgen/lowlight.py") == 0, "lowlight.py --check reports drift")
	for path in [PIT, PROTOCOL]:
		var inst := (load(path) as PackedScene).instantiate()
		check(inst is Room, "%s should load as a Room" % path)
		inst.free()


func test_roomgen_new_helpers_emit() -> void:
	check(_python("tools/roomgen/fixtures_scaffold.py") == 0, "fixtures_scaffold.py --check (self-test + fixtures) failed")


func test_room_dirs_scanned() -> void:
	check(ContentValidator.ROOM_DIRS.has("res://world/rooms/undercity"), "validator must scan the undercity folder")
	check(DirAccess.dir_exists_absolute("res://world/rooms/undercity"), "undercity room folder missing")
	var v := ContentValidator.new()
	v.validate_rooms()
	for e in v.errors:
		check(not e.contains("undercity"), "undercity folder should validate clean: %s" % e)
	check(load("res://data/districts/undercity.tres") is DistrictTheme, "undercity DistrictTheme missing")


func test_world_room_dirs() -> void:
	check(not ContentValidator.WORLD_ROOM_DIRS.has("res://world/rooms"), "WORLD_ROOM_DIRS must not include the labs folder")
	check(ContentValidator.ROOM_DIRS.has("res://world/rooms"), "ROOM_DIRS keeps the root folder")
	for p in SliceStats.room_paths():
		check(p.ends_with(".tscn") and not p.contains("Lab"), "slice room paths hold a non-room: %s" % p)


func test_content_protocol() -> void:
	var v := ContentValidator.new().check_room(PROTOCOL, false)
	check(v.errors == PackedStringArray(["room scaffold_protocol: ProtocolProbe: y"]), "errors: %s" % str(v.errors))
	for w in ["room scaffold_protocol: ProtocolProbe: x", "room scaffold_protocol: FlagDeclaration: stub flag declaration: t_declared"]:
		check(v.warnings.has(w), "missing warning '%s' in %s" % [w, str(v.warnings)])
	check(v.produced.has("t_declared"), "declared flag should count as produced")
	# Fixtures are never on the world map; the default check says so.
	var strict := ContentValidator.new().check_room(PROTOCOL)
	check(Array(strict.errors).any(func(e: String) -> bool: return e.contains("not on the world map")), "map check should run by default")


# --- RouteBot steps ---------------------------------------------------------------

func test_shoot_step() -> void:
	var room := await _enter(RELAY, &"start")
	var shots: Array = []
	var on_fire := func(_w: Resource, _ammo: int) -> void: shots.append(1)
	EventBus.ranged_fired.connect(on_fire)
	var aims: Array = []
	var on_child := func(n: Node) -> void:
		if n is Projectile:
			aims.append((n as Projectile).velocity)
	room.child_entered_tree.connect(on_child)
	var bot := RouteBot.new(get_tree(), room.player)
	var ok: bool = await bot.run([["shoot", 2, "fwd"]])
	check(ok and shots.size() == 2, "shoot fwd x2 should fire twice (%d, %s)" % [shots.size(), bot.failure])
	aims.clear()
	ok = await bot.run([["shoot", 1, "up"]])
	check(ok and aims.size() >= 1 and (aims[0] as Vector2).y < 0.0, "shoot up should aim upward (%s)" % str(aims))
	EventBus.ranged_fired.disconnect(on_fire)
	room.child_entered_tree.disconnect(on_child)


func test_dodge_step() -> void:
	var room := await _enter(RELAY, &"start")
	var states: Array = []
	var on_state := func(_from: StringName, to: StringName) -> void: states.append(to)
	EventBus.player_state_changed.connect(on_state)
	var bot := RouteBot.new(get_tree(), room.player)
	var ok: bool = await bot.run([["dodge", 300]])
	EventBus.player_state_changed.disconnect(on_state)
	check(ok, "dodge step failed: %s" % bot.failure)
	check(states.has(&"dodge"), "dodge step should enter the dodge state (%s)" % str(states))


## M7 air-dodge teaching gap: a dodge-jump across a GapChallenge with an air
## dodge 10 airborne frames in. The step must land near the target, and both
## dodges (ground, then air) must really fire.
func test_dodgejump_airdodge_step() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var gap := GapChallenge.new()
	gap.technique = "dodge_jump"
	world.add_child(gap)
	gap.build()
	var p: Player = PLAYER_SCENE.instantiate()
	p.config = load("res://data/movement/default_movement.tres")
	p.abilities = PlayerAbilities.new()
	world.add_child(p)
	p.respawn(Vector2(-140, -2))
	await physics_frames(5)
	var dodges: Array = []
	var on_state := func(_from: StringName, to: StringName) -> void:
		if to == &"dodge":
			dodges.append({"air": not p.is_on_floor(), "left": p.air_dodges_left})
	EventBus.player_state_changed.connect(on_state)
	var before := p.metrics.dodges
	var bot := RouteBot.new(get_tree(), p)
	var ok: bool = await bot.run([["dodgejump_airdodge", 2.0, gap.gap_width() + 40.0, 10]])
	EventBus.player_state_changed.disconnect(on_state)
	check(ok, "dodgejump_airdodge step failed: %s (at %s)" % [bot.failure, p.global_position])
	check(dodges.size() == 2 and p.metrics.dodges - before == 2, "expected a ground and an air dodge: %s" % str(dodges))
	check(dodges.any(func(d: Dictionary) -> bool: return d["air"]), "no dodge happened airborne: %s" % str(dodges))
	var start_left: int = p.config.air_dodges
	check(dodges.any(func(d: Dictionary) -> bool: return d["left"] < start_left), "air dodge did not spend air_dodges_left: %s" % str(dodges))


# --- Room / player / enemy hooks --------------------------------------------------

func test_nonlethal_clamps_after_multiplier() -> void:
	var room := await _enter(RELAY, &"start")
	Game.grant_circuit("glass_pulse")
	check(Game.toggle_circuit("glass_pulse"), "could not equip glass_pulse (damage_taken x2)")
	var p := room.player
	p.combat.health = 2
	p.combat.take_damage(1, Vector2.ZERO, 0.0, false, "test", true)
	check(p.combat.health == 1 and not p.combat.dead, "nonlethal should leave 1 pip, got %d" % p.combat.health)


func test_shove_no_damage_no_invuln() -> void:
	var room := await _enter(RELAY, &"start")
	var p := room.player
	var hits: Array = []
	var on_hit := func(amount: int, _hp: int) -> void: hits.append(amount)
	EventBus.player_damaged.connect(on_hit)
	var hp := p.combat.health
	p.combat.shove(Vector2(-120, -80))
	check(p.current_state_id() == &"hurt", "shove should use the hurt state")
	check(p.velocity == Vector2(-120, -80), "shove velocity not applied: %s" % p.velocity)
	check(p.combat.hurt_invuln_timer == 0.0, "shove must not grant invulnerability")
	await physics_frames(30)
	EventBus.player_damaged.disconnect(on_hit)
	check(p.combat.health == hp and hits.is_empty(), "shove must deal no damage")
	check(p.current_state_id() != &"hurt", "shove stun should end after hurt_stun_time")


func test_pit_override_called() -> void:
	var room := await _enter(PIT, &"start")
	var calls: Array = []
	room.pit_override = func(_p: Player) -> bool:
		calls.append(1)
		return true
	var p := room.player
	var hp := p.combat.health
	var input := ScriptedInputSource.new()
	p.input_source = input
	input.move_x = 1
	for f in 180:
		await physics_frames(1)
		if p.global_position.x > 345.0:
			input.move_x = 0
		if not calls.is_empty():
			break
	await physics_frames(3)
	check(not calls.is_empty(), "pit override was not called")
	check(p.combat.health == hp, "override should prevent the pit pip")
	check(p.global_position.y > room.bounds.end.y, "override should prevent the last-safe teleport (at %s)" % p.global_position)


func test_hitbox_view_calls_debug_draw() -> void:
	var room := await _enter(PROTOCOL, &"start")
	var probe := room.find_child("ProtocolProbe", true, false)
	check(probe != null, "protocol fixture has no ProtocolProbe")
	if probe == null:
		return
	var view := HitboxView.new()
	root.add_child(view)
	for i in 3:
		await get_tree().process_frame
	check(int(probe.get("debug_draw_calls")) > 0, "HitboxView should call debug_draw on room nodes")
	view.queue_free()


func test_enemy_facing_export() -> void:
	var e: Enemy = NEEDLE.instantiate()
	var exported := false
	for prop in e.get_property_list():
		if prop["name"] == "facing":
			exported = int(prop["usage"]) & PROPERTY_USAGE_STORAGE != 0
	check(exported, "Enemy.facing should be an exported (stored) property")
	e.ai_enabled = false
	e.facing = 1
	root.add_child(e)
	await physics_frames(3)
	check(e.facing == 1, "authored facing lost in _ready (%d)" % e.facing)
	e.queue_free()


# --- Telemetry ---------------------------------------------------------------------

func _analyzer() -> PlaytestAnalyzer:
	return PlaytestAnalyzer.new(Playtest.config)


func _session(kind: String, events: Array) -> PlaytestSession:
	var s := PlaytestSession.new({"kind": kind})
	for e: Dictionary in events:
		var ev := {"t": 0.0, "room": "", "x": 0, "y": 0, "pt": 0.0}
		ev.merge(e, true)
		(s.data["events"] as Array).append(ev)
	return s


func test_playtest_timeline_report_empty_ok() -> void:
	var a := _analyzer()
	var r := a.analyze()
	check((r["timeline"]["campaign"] as Array).is_empty(), "no sessions -> no campaign rows")
	var md := a.render_markdown(r)
	check(md.contains("## Undercity timeline"), "timeline section missing")
	check(md.contains("Excluded from the timeline: 0"), "excluded line missing")


func test_short_cause_labels() -> void:
	check(PlaytestAnalyzer._short_cause("unknown/collector_eye_bolt") == "Collector eye", "eye label")
	check(PlaytestAnalyzer._short_cause("clamp") == "Grid clamp", "clamp label")
	check(PlaytestAnalyzer._short_cause("scanner") == "Scanner beam", "scanner label")
	check(PlaytestAnalyzer._short_cause("chase/rainline") == "Chase: rainline", "chase label")
	check(PlaytestAnalyzer._short_cause("needle/needle_lunge") == "needle: needle_lunge", "generic label")


func test_playtest_records_dodge_and_flags() -> void:
	_record()
	check(Playtest.is_recording(), "session should record")
	EventBus.player_state_changed.emit(&"run", &"dodge")
	EventBus.player_state_changed.emit(&"run", &"dodge")
	Game.set_flag("hint_first_flow")
	Game.set_flag("core_hud_hidden", false)
	Game.set_flag("some_other_flag")
	var s := Playtest.session
	check(int(s.data["counters"].get("dodges", 0)) == 2, "dodges counter should be 2")
	check(s.events_of("dodge_first").size() == 1, "exactly one dodge_first event")
	var flags := s.events_of("flag")
	check(flags.size() == 2, "two recorded flag events expected, got %s" % str(flags))
	for e: Dictionary in s.data["events"]:
		check(e.has("pt"), "event %s has no pt" % e["type"])


func test_timeline_report_reads_real_recorder_output() -> void:
	_record()
	await _enter(RELAY, &"start")
	EventBus.weapon_granted.emit("pulse_blade")
	EventBus.player_state_changed.emit(&"run", &"dodge")
	EventBus.secret_found.emit("t_secret")
	EventBus.dialogue_requested.emit(null, "Radio")
	Game.set_flag("hint_first_flow")
	var anchor := Anchor.new()
	anchor.anchor_id = &"uc_lift"
	EventBus.anchor_rested.emit(anchor)
	anchor.free()
	var boss := Node2D.new()
	EventBus.boss_started.emit(boss, "COLLECTOR DRONE")
	EventBus.boss_defeated.emit("collector_drone")
	boss.free()
	Playtest.end_session("test")
	var a := _analyzer()
	check(a.load_dir(TEST_DIR) == 1, "one session file expected")
	a.timeline_start_room = "Relay"
	var r := a.analyze()
	var rows: Array = r["timeline"]["campaign"]
	check(rows.size() == 1, "the Relay-start session should be a campaign run (%s)" % str(r["timeline"]))
	if rows.size() != 1:
		return
	var row: Dictionary = rows[0]
	for key in ["relay", "blade", "dodge", "secret", "npc", "first_flow", "anchor", "anchor_lift", "boss_start", "boss_defeated"]:
		check(row.has(key), "timeline item %s missing (%s)" % [key, str(row)])
	for key in ["pursuit", "composition"]:
		check(not row.has(key), "%s should be unreached" % key)
	var md := a.render_markdown(r)
	check(md.contains("| FirstPursuit entered | — | 0 |"), "unreached items print a dash")


func test_timeline_filters_sessions() -> void:
	var a := _analyzer()
	a.sessions.append(_session("new", [
		{"type": "room_enter", "room": "Wake", "t": 0.0},
		{"type": "weapon_granted", "id": "pulse_blade", "t": 150.0, "pt": 150.0},
		{"type": "room_enter", "room": "Relay", "t": 1700.0, "pt": 1700.0},
	]))
	a.sessions.append(_session("new_relay", [{"type": "room_enter", "room": "Relay", "t": 0.0}]))
	a.sessions.append(_session("continue", [
		{"type": "room_enter", "room": "FirstPursuit", "t": 0.0, "pt": 900.0},
		{"type": "room_enter", "room": "Relay", "t": 600.0, "pt": 1500.0},
	]))
	var r := a.analyze()
	var tl: Dictionary = r["timeline"]
	check((tl["campaign"] as Array).size() == 1, "exactly one campaign run")
	var med := PlaytestAnalyzer.timeline_medians(tl["campaign"])
	check(med["relay"] != null and absf(float(med["relay"]) - 28.33) < 0.01, "campaign Relay median should be 28.33 (%s)" % str(med["relay"]))
	check(med["blade"] != null and absf(float(med["blade"]) - 2.5) < 0.01, "blade at 2.5 min")
	var cont: Array = tl["continued"]
	check(cont.size() == 1 and absf(float((cont[0] as Dictionary).get("relay", -1.0)) - 25.0) < 0.01, "continued Relay from pt: %s" % str(cont))
	var excluded := 0
	for k: String in tl["excluded"]:
		excluded += int(tl["excluded"][k])
	check(excluded == 1 and (tl["excluded"] as Dictionary).has("new_relay"), "one excluded session (new_relay): %s" % str(tl["excluded"]))


func test_boss_metrics_keyed_by_id() -> void:
	var a := _analyzer()
	var ev: Array = []
	for i in 2:
		ev.append({"type": "boss_start", "boss": "COLLECTOR DRONE", "id": "collector_drone"})
	ev.append({"type": "boss_defeated", "boss": "collector_drone"})
	for i in 3:
		ev.append({"type": "boss_start", "boss": "WARDEN KRAIL", "id": "warden_krail"})
	ev.append({"type": "boss_defeated", "boss": "warden_krail"})
	ev.append({"type": "boss_start", "boss": "WARDEN KRAIL"})
	a.sessions.append(_session("new", ev))
	var r := a.analyze()
	check(r["boss_attempts_by_id"] == {"warden_krail": [4], "collector_drone": [2]}, "attempts by id: %s" % str(r["boss_attempts_by_id"]))
	check(int(r["boss_clears_by_id"].get("warden_krail", 0)) == 1 and int(r["boss_clears_by_id"].get("collector_drone", 0)) == 1, "clears by id: %s" % str(r["boss_clears_by_id"]))
	check(r["boss_attempts"] == [4] and int(r["boss_clears"]) == 1, "Krail-only legacy fields")
	var md := a.render_markdown(r)
	check(md.contains("- Warden Krail:") and md.contains("- Collector Drone:"), "per-boss lines missing")
	check(not md.contains("reached Krail"), "old combined boss line should be gone")


func test_lowlight_time_line() -> void:
	var a := _analyzer()
	a.sessions.append(_session("new", [
		{"type": "room_enter", "room": "Relay", "t": 1200.0, "pt": 1200.0},
		{"type": "slice_complete", "play_time": 2700.0, "t": 2700.0, "pt": 2700.0},
	]))
	var r := a.analyze()
	check(r["lowlight_times"].size() == 1 and absf(float(r["lowlight_times"][0]) - 25.0) < 0.001, "lowlight time: %s" % str(r["lowlight_times"]))
	var md := a.render_markdown(r)
	var whole := md.find("- Completion time, whole run (min)")
	var ll := md.find("- Lowlight time, Relay arrival → slice_complete (min)")
	check(whole >= 0 and ll > whole, "lowlight line should follow the whole-run line")


func test_set_piece_tables() -> void:
	var a := _analyzer()
	a.sessions.append(_session("new", [
		{"type": "shutter", "room": "PowerBlock", "id": "s1", "margin": 0.4},
		{"type": "shutter", "room": "PowerBlock", "id": "s1", "margin": 1.2},
		{"type": "chase_caught", "room": "RainlineChase", "id": "rainline", "cp": 2},
		{"type": "chase_done", "room": "RainlineChase", "id": "rainline", "seconds": 60.0, "catches": 1, "min_lead": 0.5},
		{"type": "tracker_lock", "room": "FirstPursuit", "id": "Eye1"},
		{"type": "scanner", "room": "SecurityStation", "id": "roof", "mode": 1},
		{"type": "clamp", "room": "WardenTower", "id": "c1", "staggered": true},
		{"type": "breaker", "room": "PowerBlock", "circuit": "grid_a"},
	]))
	var r := a.analyze()
	check((r["shutter_margins"]["s1"] as Array).size() == 2, "shutter margins")
	check(int(r["chase_catches"].get("rainline CP2", 0)) == 1, "chase catches by checkpoint")
	check(int(r["tracker_locks"].get("FirstPursuit / Eye1", 0)) == 1, "tracker locks by room/id")
	check(int(r["clamp_drops"].get("c1 (staggered boss)", 0)) == 1, "clamp drops")
	var md := a.render_markdown(r)
	for t in ["| s1 | 2 |", "Chase catches by checkpoint", "Collector eye locks", "Scanner trips", "Grid clamp drops", "Breakers struck"]:
		check(md.contains(t), "set piece report missing '%s'" % t)


func test_recorder_stamps_boss_id_and_pt() -> void:
	_record()
	var room := await _enter("res://tests/fixtures/WorldA.tscn", &"start")
	var boss: Enemy = NEEDLE.instantiate()
	boss.ai_enabled = false
	boss.position = Vector2(600, -2)
	room.add_child(boss)
	var arena := BossArena.new()
	arena.boss_id = "collector_drone"
	arena.boss_title = "COLLECTOR DRONE"
	arena.position = Vector2(5000, 5000)  # out of reach: only the lookup matters
	room.add_child(arena)
	arena.boss = boss
	EventBus.boss_started.emit(boss, "COLLECTOR DRONE")
	var other := Node2D.new()
	EventBus.boss_started.emit(other, "X")
	other.free()
	EventBus.boss_defeated.emit("collector_drone")
	var starts := Playtest.session.events_of("boss_start")
	check(starts.size() == 2, "two boss_start events expected")
	if starts.size() == 2:
		check(starts[0]["id"] == "collector_drone", "arena boss id not stamped: %s" % str(starts[0]))
		check(starts[1]["id"] == "", "unrelated boss should record an empty id")
	for e: Dictionary in Playtest.session.data["events"]:
		check(e.has("pt") and (e["pt"] is float or e["pt"] is int), "event %s lacks a numeric pt" % e["type"])
