extends RedlineTestCase
## Deep Rig route tests (M9 D3 §3.2/§3.8, bible §34 traversal validation;
## T10). Each stratum is played as the real challenge run (Challenges.start,
## the profile's loadout plus Dash, enemies pacified like every route test)
## by RouteBot, and must reach its ChallengeGoal under the stage's par. The
## measured times are recorded in the T10 commit body (D-154: pars stay
## placeholders until §44). Breaker Run pins the shutter margins of the
## intended line (>= 0.35 s, the test_power_shutter measure), proves the
## expert line over NS2's housing, and documents why the rig needs Dash: the
## same line without it misses NS1. The Floor uses the scripted damage
## harness (test_enemies_boss) to kill Krail's variant and checks the
## on_boss goal. NULL_DOORS pins the challenge folder's doors.

const H := preload("res://tests/fixtures/challenges/ChallengeHarness.gd")
const DIR := "res://world/rooms/challenge/"
const STATIC_LANE := "res://world/rooms/challenge/NullStaticLane.tscn"
const BREAKER_RUN := "res://world/rooms/challenge/NullBreakerRun.tscn"
const FLOOR := "res://world/rooms/challenge/NullFloor.tscn"
const PULSE_PIT := "res://world/rooms/challenge/PulsePit.tscn"
const MIN_MARGIN := 0.35

## Every door in the challenge folder: [room, exit target, entry, requires_flag].
## Exits are off inside runs (a stage moves on at its goal); they exist for
## dev teleports and are pinned so a generator change cannot drift them.
const NULL_DOORS := [
	[STATIC_LANE, BREAKER_RUN, &"from_lane", ""],
	[BREAKER_RUN, FLOOR, &"from_breaker", ""],
]
## Every spawn in the challenge folder: [room, spawn id, default].
const NULL_SPAWNS := [
	[STATIC_LANE, &"start", true],
	[BREAKER_RUN, &"from_lane", true],
	[FLOOR, &"from_breaker", true],
	[PULSE_PIT, &"start", true],
]

## Static Lane, intended line with Dash: blur through the pulsing beams, the
## dash-jump gaps, a Dash past the landing's high beam, then the goal.
const STATIC_LANE_ROUTE := [
	["dodge", 125], ["dodge", 265], ["dodge", 405], ["dodge", 545],   # A: four beams
	["dashjump", 820, 1060], ["dashjump", 1100, 1280], ["dashjump", 1330, 1535],   # B: three gaps
	["run", 1570], ["dodge", 1582],                                     # the landing's high beam
	["run", 2340],                                                      # C: through the Flow fight
]

## Breaker Run, intended line: each breaker, then Dashes in the line so every
## shutter is passed standing with margin (NS1 is the Dash clock).
const BREAKER_NS1 := [["run", 88], ["attack", 1], ["dodge", 200], ["dodge", 330], ["dodge", 460], ["dodge", 590], ["dodge", 700]]
## nb_2 is shot from below (_snap_shot_up: fire and go, as a player would),
## then the line to NS2.
const BREAKER_TO_NB2 := [["run", 868]]
const BREAKER_RUN_REST := [
	["dodge", 960], ["dodge", 1090], ["dodge", 1220], ["dodge", 1340], ["run", 1500],  # NS2
	["run", 1688], ["attack", 1], ["run", 2080],                                        # nb_3, NS3a/b
]
## The expert line: up the one-way steps to the ledge, a dash-jump onto NS2's
## housing (only a Dash spans the 200 px), off its east side; nb_2 skipped.
const BREAKER_EXPERT_REST := [
	["run", 940], ["jump", 980], ["jump", 1030], ["jump", 1100], ["run", 1172],
	["dashjump", 1180, 1420], ["run", 1500],
	["run", 1688], ["attack", 1], ["run", 2080],
]

var h: H
var bot: RouteBot
var _cleared: Array = []
var _passes: Array = []


func before_each() -> void:
	h = H.new(self, "null_routes")
	h.setup()
	ChallengeLibrary.data_dir = ChallengeLibrary.DEFAULT_DIR
	ChallengeLibrary.clear_cache()
	_cleared = []
	_passes = []
	h.listen(EventBus.challenge_stage_cleared, func(id: String, st: String, f: int, hits: int, deaths: int, m: int) -> void:
		_cleared.append([id, st, f, hits, deaths, m]))
	h.listen(EventBus.shutter_passed, func(id: String, margin: float) -> void: _passes.append([id, margin]))


func after_each() -> void:
	bot = null
	await h.teardown()


## Starts `id` as the profile would (Dash owned), pacifies the room and binds
## a RouteBot to the run's player.
func _run(id: String, dash := true) -> bool:
	Game.set_ability(&"dash", dash)
	var ch := ChallengeLibrary.by_id(id)
	check(ch != null, "%s shipped" % id)
	if ch == null:
		return false
	var started: bool = await h.start(ch, {})
	check(started, "%s started" % id)
	if not started:
		return false
	_pacify()
	bot = RouteBot.new(get_tree(), h.player())
	await physics_frames(5)
	return true


func _pacify() -> void:
	var room := h.room()
	for e in room.find_children("*", "Enemy", true, false):
		var enemy := e as Enemy
		if enemy.ai_enabled:
			enemy.ai_enabled = false
			enemy.set_ai(Enemy.AI.IDLE)


func _steps(steps: Array) -> bool:
	var ok: bool = await bot.run(steps)
	check(ok, "%s: %s | %s" % [SceneRouter.current_room.name if SceneRouter.current_room else "no room", bot.failure, bot.log])
	return ok


## Walks east into the goal (the run freezes Rook there, so this is not a
## RouteBot "run" step, which would read the freeze as stuck).
func _into_goal(frames := 120) -> bool:
	bot.input.move_x = 1
	var ok: bool = await h.until(func() -> bool: return not _cleared.is_empty(), frames)
	bot.input.move_x = 0
	return ok


## One shot straight up, then straight on: RouteBot's "shoot" step stands
## for 24 frames after the shot, which no player racing a clock would.
func _snap_shot_up() -> void:
	bot.input.up_held = true
	bot.input.press_ranged()
	await physics_frames(4)
	bot.input.up_held = false


func _par_frames(id: String, stage_id: String) -> int:
	var ch := ChallengeLibrary.by_id(id)
	for st in ch.stages:
		if st.id == stage_id:
			return roundi(st.par_s * RunClock.FPS)
	return 0


func test_static_lane_route_under_par() -> void:
	if not await _run("null_static_lane"):
		return
	if not await _steps(STATIC_LANE_ROUTE):
		return
	check(await _into_goal(), "the static_lane goal fired")
	if _cleared.is_empty():
		return
	var frames := int(_cleared[0][2])
	print("NULL_ROUTE static_lane %.2f s hits %d" % [frames / 60.0, _cleared[0][3]])
	check(_cleared[0][1] == "static_lane" and frames < _par_frames("null_static_lane", "static_lane"),
		"under par (%.2f s)" % (frames / 60.0))
	check(int(_cleared[0][3]) == 0, "the intended line takes no hit (%d)" % _cleared[0][3])



func test_breaker_run_route_under_par_with_margins() -> void:
	if not await _run("null_breaker_run"):
		return
	if not await _steps(BREAKER_NS1 + BREAKER_TO_NB2):
		return
	await _snap_shot_up()
	if not await _steps(BREAKER_RUN_REST):
		return
	check(await _into_goal(), "the breaker_run goal fired")
	if _cleared.is_empty():
		return
	var frames := int(_cleared[0][2])
	print("NULL_ROUTE breaker_run %.2f s hits %d margins %s" % [frames / 60.0, _cleared[0][3], _passes])
	check(frames < _par_frames("null_breaker_run", "breaker_run"), "under par (%.2f s)" % (frames / 60.0))
	var ids: Array = _passes.map(func(p: Array) -> String: return p[0])
	for id in ["NS1", "NS2", "NS3a", "NS3b"]:
		check(ids.has(id), "%s passed (%s)" % [id, ids])
	for pass_info: Array in _passes:
		check(float(pass_info[1]) >= MIN_MARGIN, "%s passed standing with %.2f s (>= %.2f)" % [pass_info[0], pass_info[1], MIN_MARGIN])


func test_breaker_run_expert_line() -> void:
	if not await _run("null_breaker_run"):
		return
	var hits: Array = []
	h.listen(EventBus.breaker_hit, func(c: StringName) -> void: hits.append(c))
	if not await _steps(BREAKER_NS1 + BREAKER_EXPERT_REST):
		return
	check(not hits.has(&"nb_c2"), "the expert line never touches nb_2 (%s)" % [hits])
	var ids: Array = _passes.map(func(p: Array) -> String: return p[0])
	check(not ids.has("NS2"), "NS2 is gone over, not through (%s)" % [ids])
	check(await _into_goal(), "the expert line reaches the goal")
	if not _cleared.is_empty():
		print("NULL_ROUTE breaker_run expert %.2f s" % (int(_cleared[0][2]) / 60.0))


## Documents the Dash requirement: the same line without Dash (plain dodges)
## meets NS1 closed. Played in the room directly (a run refuses to start
## without Dash, test_null.gd).
func test_breaker_run_ns1_needs_dash() -> void:
	Game.set_ability(&"dash", false)
	await h.goto(BREAKER_RUN, &"from_lane")
	_pacify()
	bot = RouteBot.new(get_tree(), h.player())
	await physics_frames(5)
	var ok: bool = await bot.run(BREAKER_NS1 + [["run", 820]])
	check(not ok and bot.player.global_position.x < 760.0, "without Dash the line stops at NS1 (%s, %s)" % [ok, bot.player.global_position])
	check(not _passes.any(func(p: Array) -> bool: return p[0] == "NS1"), "NS1 never passed (%s)" % [_passes])


## The Floor: walk into the arena, then the scripted damage harness (as in
## test_enemies_boss) kills Krail's variant; the on_boss goal ends the stage.
func test_floor_boss_goal_fires_on_kill() -> void:
	if not await _run("null_floor"):
		return
	var room := h.room()
	var arena := room.find_child("BossArena", true, false) as BossArena
	check(arena != null and arena.boss_id == "null_krail", "the Null arena")
	if arena == null:
		return
	var k := arena.boss
	check(k != null and k.data.resource_path.ends_with("warden_krail_null.tres") and k.data.max_health == 560.0, "Krail's variant data")
	check(k.behavior.phase2_threshold == 0.9 and k.behavior.phase2_telegraph_scale == 0.72, "the variant's behaviour exports")
	bot.input.move_x = 1
	check(await h.until(func() -> bool: return arena.started, 120), "the fight started")
	bot.input.move_x = 0
	check(await h.until(func() -> bool: return arena.released, 240), "the boss was released after the intro")
	check(_cleared.is_empty(), "no goal before the kill")
	var death_time := k.data.death_time
	var kill := HitInfo.create(h.player(), k.data.attacks[0].duplicate(), Vector2.ZERO, Vector2.RIGHT)
	kill.attack.damage = 99999.0
	k.receive_hit(kill)
	check(await h.until(func() -> bool: return not _cleared.is_empty(), 30), "the on_boss goal fired on the kill")
	if not _cleared.is_empty():
		check(_cleared[0][0] == "null_floor" and _cleared[0][1] == "floor", "stage floor cleared (%s)" % [_cleared[0]])
		print("NULL_ROUTE floor harness %.2f s" % (int(_cleared[0][2]) / 60.0))
		check(int(_cleared[0][2]) < _par_frames("null_floor", "floor"), "under par")
	check(await h.until(func() -> bool: return Challenges.phase() != Challenges.Phase.RUNNING, 30), "a one-stage run finishes at its goal")
	# Let BossArena's post-death timer end before teardown (no coroutine
	# left waiting at exit).
	await physics_frames(roundi((death_time + 0.4) * 60.0))


## Every door and spawn in the challenge folder is declared above.
func test_null_doors_declared() -> void:
	var seen_doors: Array = []
	var seen_spawns: Array = []
	for path in DataDir.list_scenes(DIR.trim_suffix("/")):
		var room := (load(path) as PackedScene).instantiate() as Room
		for n in room.find_children("*", "RoomExit", true, false):
			var e := n as RoomExit
			var row := [path, e.target_room, e.target_entry, e.requires_flag]
			seen_doors.append(row)
			check(NULL_DOORS.has(row), "undeclared door %s" % [row])
		for n in room.find_children("*", "SpawnMarker", true, false):
			var m := n as SpawnMarker
			var row2 := [path, m.spawn_id, m.is_default]
			seen_spawns.append(row2)
			check(NULL_SPAWNS.has(row2), "undeclared spawn %s" % [row2])
		room.free()
	for row in NULL_DOORS:
		check(seen_doors.has(row), "declared door missing %s" % [row])
	for row in NULL_SPAWNS:
		check(seen_spawns.has(row), "declared spawn missing %s" % [row])
	# Every stage entry of the shipped Deep Rig challenges is one of them.
	for ch in ChallengeLibrary.all():
		for i in ch.stage_count():
			check(NULL_SPAWNS.any(func(r: Array) -> bool: return r[0] == ch.stage_room(i) and r[1] == ch.stage_entry(i)),
				"%s stage %d enters at a declared spawn" % [ch.id, i])
