class_name GhostBake
extends Node
## Bakes the shipped rig ghosts (M9 D2 §4.5, T08): runs the REAL challenge
## path (Challenges.start with no return point), binds a bot to the run's
## player and keeps exactly what a player's run records. The bot per
## ChallengeData.dev_bot: "route" = RouteBot over ch.dev_route (its trailing
## ["exit", dir] becomes "hold dir until the finish line", because a run's
## exits are finish lines and the next room never loads); "boss_blade" /
## "boss_pistol" = walk into the arena, then BossBot with that profile.
##
##   godot --headless --fixed-fps 60 res://devtools/GhostBake.tscn -- --challenge=<id>|all [--check] [--out=res://data/challenges/ghosts] [--pacify]
##
## --check re-bakes in memory and exits 1 when a shipped ghost's revision or
## frame count differs (exact: headless fixed-fps is deterministic, R08.14),
## which test_dev_ghosts_current also runs in-process. Without --check the
## ghosts are written to --out. Either way it prints the suggested medals;
## a human copies them into the .tres (data, never auto-written).
##
## Determinism (R08.4, R08.14): every timing setting is pinned for the bake
## and put back after; the scene registers a world root but NO fade (like the
## test runner, so SceneRouter._fade stays null and a transition is a fixed
## two-frame swap); bots start only after room_loaded, once no transition
## runs, after a fixed lead.
##
## Players see a baked ghost as the "Rig ghost": the bot is frame-perfect
## with no reaction time, so the top medal sits bot_margin above it (D-150).

const DEFAULT_OUT := "res://data/challenges/ghosts"
## Physics frames between the run room going live and the bot's first input.
const LEAD_FRAMES := 10
## Safety caps (frames): the start, a route's hold to the finish line, the
## walk into an arena, a boss fight.
const START_LIMIT := 240
const HOLD_LIMIT := 900
const WALK_LIMIT := 600
const BOSS_SECONDS := 150.0
## Every setting that changes run timing, pinned for a bake (R08.4).
const PINNED := {"hitstop_scale": 1.0, "jump_hold_mode": 0, "aim_assist": 0, "damage_assist": 0, "reactor_mode": 0,
	"burnout_hurts": true, "generous_checkpoints": false, "currency_loss": true, "playtest_variant": "",
	"challenge_ghost": 0}

var _root: Node2D
var _exit_code: int = 0


func _ready() -> void:
	_root = Node2D.new()
	_root.name = "World"
	add_child(_root)
	SceneRouter.register_world_root(_root)
	_main.call_deferred()


func _main() -> void:
	var args := parse_args(OS.get_cmdline_user_args())
	var ids: PackedStringArray = args["ids"]
	if ids.is_empty():
		printerr("GhostBake: pass --challenge=<id>|all")
		get_tree().quit(2)
		return
	for id in ids:
		var ch := ChallengeLibrary.by_id(id)
		if ch == null:
			printerr("GhostBake: unknown challenge '%s'" % id)
			_exit_code = 1
			continue
		var pacify := bool(args["pacify"])
		if ch.dev_bot == &"none" and not (pacify and not ch.dev_route.is_empty()):
			print("GhostBake: %s has no bot (dev_bot none), skipped" % id)
			continue
		var r: Dictionary = await bake(get_tree(), ch, pacify)
		if not bool(r["ok"]):
			printerr("GhostBake: %s FAILED: %s" % [id, r["failure"]])
			_exit_code = 1
			continue
		var frames := int(r["frames"])
		print("GhostBake: %s %d frames (%s)  suggested medals %s" % [id, frames, RunClock.format(frames),
			medal_line(suggest_medals(frames))])
		if pacify:
			print("GhostBake: %s was baked PACIFIED: provisional medals only, nothing written" % id)
		elif bool(args["check"]):
			var why := check_against_shipped(ch, frames)
			if why != "":
				printerr("GhostBake: %s DRIFT: %s" % [id, why])
				_exit_code = 1
			else:
				print("GhostBake: %s matches the shipped ghost" % id)
		else:
			var path := "%s/%s.ghost" % [String(args["out"]), id]
			var err := GhostCodec.save(path, r["ghost"])
			if err != OK:
				printerr("GhostBake: %s could not write %s (%s)" % [id, path, error_string(err)])
				_exit_code = 1
			else:
				print("GhostBake: wrote %s" % path)
	get_tree().quit(_exit_code)


## {"ids": PackedStringArray, "check": bool, "out": String}. "all" = every
## challenge with a bot.
static func parse_args(args: PackedStringArray) -> Dictionary:
	var out := {"ids": PackedStringArray(), "check": false, "pacify": false, "out": DEFAULT_OUT}
	var ids := PackedStringArray()
	for a in args:
		if a == "--check":
			out["check"] = true
		elif a == "--pacify":
			out["pacify"] = true
		elif a.begins_with("--out="):
			out["out"] = a.trim_prefix("--out=").trim_suffix("/")
		elif a.begins_with("--challenge="):
			var v := a.trim_prefix("--challenge=")
			if v == "all":
				for ch in ChallengeLibrary.all():
					if ch.dev_bot != &"none":
						ids.append(ch.id)
			else:
				for id in v.split(",", false):
					ids.append(id)
	out["ids"] = ids
	return out


## "" when the shipped ghost of `ch` has this revision and frame count, else
## why not.
static func check_against_shipped(ch: ChallengeData, frames: int) -> String:
	if ch.dev_ghost == "":
		return "no dev_ghost path in %s" % ch.id
	var g := GhostCodec.load_file(ch.dev_ghost)
	if g == null:
		return "cannot read %s" % ch.dev_ghost
	if g.kind == "dev_hand":
		return ""
	if g.challenge != ch.id or g.revision != ch.revision:
		return "shipped ghost is %s rev %d, challenge is %s rev %d" % [g.challenge, g.revision, ch.id, ch.revision]
	if g.frames != frames:
		return "shipped %d frames, re-bake %d" % [g.frames, frames]
	return ""


## Suggested medals [Bronze, Silver, Gold, Redline] in frames (D-150): Redline
## = bot frames × bot_margin, Gold/Silver/Bronze = Redline × 1.35/1.7/2.4,
## each rounded UP to 0.5 s.
static func suggest_medals(bot_frames: int) -> PackedInt32Array:
	var margin := ChallengeConfig.shared().bot_margin
	var redline := round_up_half_s(float(bot_frames) * margin)
	return PackedInt32Array([round_up_half_s(redline * 2.4), round_up_half_s(redline * 1.7),
		round_up_half_s(redline * 1.35), redline])


## Frames rounded up to the next 0.5 s (30 frames). A tiny epsilon keeps an
## exact product (3600 × 1.35 = 4860.000001) from jumping a step.
static func round_up_half_s(frames: float) -> int:
	var half := RunClock.FPS / 2
	return int(ceil(frames / half - 0.000001)) * half


static func medal_line(m: PackedInt32Array) -> String:
	var parts := PackedStringArray()
	for i in m.size():
		parts.append("%s %d (%s)" % [RankLadder.name(i + 1), m[i], RunClock.format(m[i])])
	return " · ".join(parts)


## Whether SceneRouter has a live fade rect (a booted Main registers one; a
## bake must run without, so a transition is the same fixed two frames as in
## the test runner, R08.14).
static func fade_live() -> bool:
	return is_instance_valid(SceneRouter.get("_fade"))


## Every pinned setting's current value (restore_settings puts them back).
static func pin_settings() -> Dictionary:
	var saved := {}
	for k: String in PINNED:
		saved[k] = Settings.get(k)
		Settings.set(k, PINNED[k])
	return saved


static func restore_settings(saved: Dictionary) -> void:
	for k: String in saved:
		Settings.set(k, saved[k])


## One bake of `ch` through the real run path. Needs a registered world root
## and no live run. Returns {ok, frames, ghost: GhostData, failure, outcome,
## fade_null}. The run is quit afterwards (the profile comes back) and the
## run room is removed.
##
## replay: instead of a bot, feed that ghost's recorded input track back
## (the determinism proof: the same inputs must give the same run).
static func bake(tree: SceneTree, ch: ChallengeData, pacify: bool = false, replay: GhostData = null) -> Dictionary:
	var r := {"ok": false, "frames": -1, "ghost": null, "failure": "", "outcome": -1,
		"fade_null": true}
	var bot_kind := ch.dev_bot if ch else &"none"
	if pacify and bot_kind == &"none" and not ch.dev_route.is_empty():
		bot_kind = &"route"
	if replay != null:
		bot_kind = &"replay"
	if ch == null or bot_kind == &"none":
		r["failure"] = "no bot"
		return r
	if Challenges.active() or SceneRouter.world_root == null:
		r["failure"] = "a run is live or no world root is registered"
		return r
	var saved := pin_settings()
	# A fade (a booted Main's, or a stale one a test left behind) would add
	# render-rate frames before the bot starts: it is unregistered for the
	# bake and put back after (R08.14).
	var fade: Variant = SceneRouter.get("_fade")
	SceneRouter.register_fade(null)
	_drop_room()
	if not Challenges.start(ch, {}):
		SceneRouter.set("_fade", fade)
		restore_settings(saved)
		r["failure"] = "Challenges.start refused"
		return r
	var live := false
	for i in START_LIMIT:
		await tree.physics_frame
		if Challenges.phase() == Challenges.Phase.RUNNING and not SceneRouter.transitioning:
			live = true
			break
	var ghost: GhostData = Challenges.recorder.data if live and Challenges.recorder else null
	if not live or ghost == null:
		r["failure"] = "the run room never went live"
	else:
		for i in LEAD_FRAMES:
			await tree.physics_frame
		r["fade_null"] = bool(r["fade_null"]) and not fade_live()
		var room := SceneRouter.current_room as Room
		if pacify:
			_pacify(room)
		var why := ""
		match bot_kind:
			&"route":
				why = await _run_route(tree, room.player, ch.dev_route)
			&"boss_blade", &"boss_pistol":
				why = await _run_boss(tree, room, ch, "blade" if bot_kind == &"boss_blade" else "pistol")
			&"replay":
				why = await _run_replay(tree, room.player, replay)
			_:
				why = "unknown dev_bot %s" % bot_kind
		var outcome := int(Challenges.last_result.get("outcome", -1)) if Challenges.phase() != Challenges.Phase.RUNNING else -1
		r["outcome"] = outcome
		if why == "" and outcome != ChallengeData.Outcome.FINISHED:
			why = "the run did not finish (outcome %d, cause '%s')" % [outcome, Challenges.last_result.get("cause", "")]
		if why == "":
			ghost.kind = "dev"
			ghost.profile = 0
			# No date: a re-bake of an unchanged room writes the same bytes.
			ghost.date = ""
			r["ok"] = true
			r["frames"] = ghost.frames
			r["ghost"] = ghost
		r["failure"] = why
	Challenges.quit()
	await tree.physics_frame
	if Challenges.active():
		Challenges.reset_for_tests()
	_drop_room()
	SceneRouter.set("_fade", fade)
	restore_settings(saved)
	return r


## Route bot: every step but a trailing exit, then hold that direction until
## the finish line ends the run.
static func _run_route(tree: SceneTree, player: Player, route: Array) -> String:
	var steps := route.duplicate(true)
	var dir := 0
	if not steps.is_empty() and String((steps.back() as Array)[0]) == "exit":
		dir = int((steps.pop_back() as Array)[1])
	var bot := RouteBot.new(tree, player)
	var ok: bool = await bot.run(steps)
	if Challenges.phase() != Challenges.Phase.RUNNING:
		if int(Challenges.last_result.get("outcome", -1)) == ChallengeData.Outcome.FINISHED:
			return ""
		return "the run ended during the route (outcome %d, cause '%s'): %s" % [int(Challenges.last_result.get("outcome", -1)),
			Challenges.last_result.get("cause", ""), bot.failure]
	if not ok:
		return "route: %s" % bot.failure
	if dir == 0:
		return "the route has no trailing exit step"
	for i in HOLD_LIMIT:
		if Challenges.phase() != Challenges.Phase.RUNNING:
			return ""
		if is_instance_valid(bot.player):
			bot.input.move_x = dir
		await tree.physics_frame
	return "never reached the finish line"


## Replays a ghost's input track and waits for the run to end.
static func _run_replay(tree: SceneTree, player: Player, g: GhostData) -> String:
	var src := ReplaySource.new()
	src.track = input_track(g)
	player.input_source = src
	for i in g.frames + HOLD_LIMIT:
		if Challenges.phase() != Challenges.Phase.RUNNING:
			return ""
		await tree.physics_frame
	return "the replay never finished the run"


## The input bits of every sample of `g`, in order.
static func input_track(g: GhostData) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in g.sample_count():
		out.append(int(g.sample(i).get("input", 1)))
	return out


## Feeds a recorded input track back, one frame per physics sample (a
## future "watch replay" mode starts here, D2 §4.1). Past the end: idle.
class ReplaySource extends PlayerInputSource:
	var track: PackedInt32Array = PackedInt32Array()
	var index: int = 0

	func sample(_config: PlayerMovementConfig) -> PlayerInputFrame:
		var bits := track[index] if index < track.size() else 1
		index += 1
		return GhostCodec.decode_input(bits)


## Boss bot: walk toward the arena until the fight starts (the clock starts
## on boss_started), then fight.
static func _run_boss(tree: SceneTree, room: Room, ch: ChallengeData, profile: String) -> String:
	var arena: BossArena = null
	for n in room.find_children("*", "BossArena", true, false):
		if (n as BossArena).boss_id == ch.boss_id:
			arena = n as BossArena
	if arena == null or arena.boss == null:
		return "no BossArena for %s in %s" % [ch.boss_id, room.name]
	var walk := ScriptedInputSource.new()
	room.player.input_source = walk
	var dir := 1 if arena.global_position.x + 32.0 > room.player.global_position.x else -1
	for i in WALK_LIMIT:
		if Challenges.clock.running:
			break
		walk.move_x = dir
		await tree.physics_frame
	if not Challenges.clock.running:
		return "the fight never started"
	var bot := BossBot.new(tree, room.player, arena.boss, profile)
	var res: Dictionary = await bot.run(BOSS_SECONDS)
	if not bool(res.get("won", false)):
		return "BossBot did not win (%s)" % [res]
	for i in 30:
		if Challenges.phase() != Challenges.Phase.RUNNING:
			break
		await tree.physics_frame
	return ""


## --pacify (a measuring aid for a challenge whose live bake is not reliable
## yet, plan risk 'Bot routes were written for pacified rooms'): every awake
## enemy idles, as in the route tests. Such a bake is never written or
## checked; it only prints provisional medals.
static func _pacify(room: Room) -> void:
	for e in room.find_children("*", "Enemy", true, false):
		var enemy := e as Enemy
		if enemy.ai_enabled:
			enemy.ai_enabled = false
			enemy.set_ai(Enemy.AI.IDLE)


## Frees the loaded room (the next start then swaps at once instead of
## saving a world room first).
static func _drop_room() -> void:
	var room := SceneRouter.current_room
	if room and is_instance_valid(room):
		if room.get_parent():
			room.get_parent().remove_child(room)
		room.queue_free()
	SceneRouter.current_room = null
	SceneRouter.current_room_path = ""
