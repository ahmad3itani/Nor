extends RedlineTestCase
## NG+ routes (M9 D3 §4, R09.3): the remixed rooms stay traversable and fair,
## and the early Dash of an NG+ run never skips a story gate.
## - The rooms' own route tests run again with every remix forced on
##   (RemixLibrary.force_active; the route suites reset Game.state, so the
##   ng_remix flag would not survive their before_each). PowerBlock's route
##   asserts the shutter margins against the D-099 floor with the remix
##   timings, RainlineChase runs the rainline_remix Sweeper.
## - BossBot beats the remixed Collector (the CollectorBay ops applied to a
##   drone in the M4 arena harness, rng_seed 23).
## - test_ngplus_dash_early_story_gates walks Act I (the full Undercity walk
##   and the full Lowlight chain, the rooms' own RouteBot steps) with the Dash
##   from Wake and compares every story flag and world-state switch with the
##   same walk without it. A room whose walk the Dash breaks is listed in
##   KNOWN_DASH_SKIPS until the T09b generator fix (the list may only shrink).

const TR := preload("res://tests/TestRunner.gd")
const UC_ROUTES := "res://tests/unit/test_undercity_routes.gd"
const LL_ROUTES := "res://tests/unit/test_lowlight_m7_routes.gd"
const BOSS := "res://tests/unit/test_boss_collector.gd"
const SLICE_ROUTES := preload("res://tests/unit/test_slice_routes.gd")
const UCR := preload("res://tests/unit/test_undercity_routes.gd")
const LLR := preload("res://tests/unit/test_lowlight_m7_routes.gd")
const UC := "res://world/rooms/undercity/"
const LL := "res://world/rooms/lowlight/"
const BAY_REMIX := "res://data/remix/CollectorBay.tres"

## Rooms whose Act I walk the early Dash breaks, pending a generator fix
## (R09.3, step 3b). The test fails if a room not listed here breaks.
const KNOWN_DASH_SKIPS: PackedStringArray = []


func after_each() -> void:
	RemixLibrary.force_active = false
	await physics_frames(2)


## Runs another suite's test with every remix forced on; its failures become ours.
func _remixed(script_path: String, method: String, rooms: PackedStringArray) -> void:
	var suite: RedlineTestCase = (load(script_path) as GDScript).new()
	add_child(suite)
	RemixLibrary.clear_cache()
	RemixLibrary.force_active = true
	var r: Dictionary = await TR.run_one(suite, "%s::%s (remix)" % [script_path.get_file().get_basename(), method], method)
	for room in rooms:
		check(int(RemixLibrary.last_applied.get(room, 0)) > 0, "%s: the remix ran in %s" % [method, room.get_file()])
	RemixLibrary.force_active = false
	for f in suite.failures:
		failures.append("%s: %s" % [_current_test, f])
	check(r["status"] != "SKIP", "%s did not run: %s" % [method, r.get("reason", "")])
	suite.queue_free()
	await physics_frames(2)


func test_remix_medical_ruin_route() -> void:
	await _remixed(UC_ROUTES, "test_medical_ruin_route", [UC + "MedicalRuin.tscn"])


func test_remix_security_station_route() -> void:
	await _remixed(LL_ROUTES, "test_security_station_route", [LL + "SecurityStation.tscn"])


## The route asserts every shutter's pass margin >= 0.5 s (D-099) and S4b's
## low-line margin, here with shutter_run_remix / shutter_l3_remix.
func test_remix_power_block_route() -> void:
	var run := load("res://data/level/shutter_run_remix.tres") as ShutterTiming
	var l3 := load("res://data/level/shutter_l3_remix.tres") as ShutterTiming
	check(run.open < (load("res://data/level/shutter_run.tres") as ShutterTiming).open and l3.open < (load("res://data/level/shutter_l3.tres") as ShutterTiming).open,
		"the remix shutters are tighter than the base ones")
	await _remixed(LL_ROUTES, "test_power_block_route", [LL + "PowerBlock.tscn"])


func test_remix_rainline_route() -> void:
	var r := load("res://data/world/chase/rainline_remix.tres") as PursuerData
	check(r.base_speed > (load("res://data/world/chase/rainline.tres") as PursuerData).base_speed, "the remix Sweeper is faster")
	await _remixed(LL_ROUTES, "test_rainline_route", [LL + "RainlineChase.tscn"])


## BossBot (M4) against the remixed Collector: the CollectorBay ops applied to
## a drone named like the room's, in the M4 graybox arena.
func test_bossbot_beats_remix_collector() -> void:
	var suite: RedlineTestCase = (load(BOSS) as GDScript).new()
	add_child(suite)
	suite._current_test = _current_test
	await suite.before_each()
	var world: Node2D = suite.get("world")
	var player: Player = suite.get("player")
	var holder := Node2D.new()
	holder.name = "RemixArena"
	var enemies := Node2D.new()
	enemies.name = "Enemies"
	holder.add_child(enemies)
	var e: Enemy = (load("res://bosses/CollectorDrone.tscn") as PackedScene).instantiate()
	e.name = "CollectorDrone1"
	e.position = Vector2(252, -144)
	e.ai_enabled = true
	enemies.add_child(e)
	var remix := load(BAY_REMIX) as RoomRemix
	check(RemixLibrary.apply_ops(holder, remix) == remix.ops.size(), "every CollectorBay op lands on the arena drone")
	await suite.call("_reset_player", 120)
	world.add_child(holder)
	await physics_frames(2)
	e.set_ai(Enemy.AI.ENGAGE)
	check(is_equal_approx(e.health, 420.0) and int(e.behavior.get("rng_seed")) == 23, "the remix drone (420 HP, seed 23)")
	var bot := BossBot.new(get_tree(), player, e, "blade")
	var r: Dictionary = await bot.run(200.0)
	print("  BossBot remix blade: won %s in %.1f s, health %d" % [r["won"], r["seconds"], r["health"]])
	check(r["won"] and int(r["health"]) > 0, "the blade bot beats the remix Collector (%s)" % [r])
	check(world.find_children("*", "ScrapPickup", true, false).map(func(p: ScrapPickup) -> int: return p.value).reduce(
		func(a: int, b: int) -> int: return a + b, 0) <= 80, "the remix Collector pays no more than the base 80")
	await suite.after_each()
	for f in suite.failures:
		failures.append(f)
	suite.queue_free()


# --- R09.3: the Dash from Wake ------------------------------------------------------

## What the walk saw: the story flags in the order they turned on, and the
## world-state switches of each room as the walk entered it.
class Trace:
	var story: Array = []
	var switches: Array = []
	var broken: PackedStringArray = []

	func on_flag(id: String, value: Variant) -> void:
		if (typeof(value) == TYPE_BOOL and value) and (id.begins_with("seen_seq_") or id.begins_with("met_") or id.begins_with("quest_")
				or id.begins_with("arc_") or id.begins_with("uc_") or id.begins_with("repeater_") or id.ends_with("_defeated")
				or id.begins_with("chase_") or id.begins_with("shortcut_") or id.begins_with("got_") or id == "lowlight_power_rerouted"):
			story.append(id)

	func note_room(room: Node) -> void:
		var states: Array = []
		for n in room.find_children("*", "WorldStateSwitch", true, false):
			states.append("%s/%s=%s" % [room.name, n.name, (n as CanvasItem).visible])
		switches.append(states)


func test_ngplus_dash_early_story_gates() -> void:
	var base := await _act1_walk(false)
	var dash := await _act1_walk(true)
	print("  [R09.3] story flags: %d without the Dash, %d with it; broken with the Dash: %s" % [base.story.size(), dash.story.size(), dash.broken])
	check(base.broken.is_empty(), "the walk without the Dash is clean: %s" % [base.broken])
	for room in dash.broken:
		check(KNOWN_DASH_SKIPS.has(room), "the early Dash breaks the Act I walk in %s (fix the room data or list it for T09b)" % room)
	for room in KNOWN_DASH_SKIPS:
		check(dash.broken.has(room), "%s is in KNOWN_DASH_SKIPS but the walk passes: drop it" % room)
	if dash.broken.is_empty():
		check(dash.story == base.story, "every story flag fires in the same order with the Dash:\n  base %s\n  dash %s" % [base.story, dash.story])
		check(dash.switches == base.switches, "every world-state switch shows the same state with the Dash")


## The Act I walk: test_full_undercity_walk's legs (Wake to the Relay) then
## test_full_lowlight_chain's (the Relay to Warden Krail's door), driven
## through the route suites' own harness. `dash`: the NG+ early Dash.
func _act1_walk(dash: bool) -> Trace:
	var t := Trace.new()
	var uc: RedlineTestCase = (load(UC_ROUTES) as GDScript).new()
	var ll: RedlineTestCase = (load(LL_ROUTES) as GDScript).new()
	add_child(uc)
	add_child(ll)
	uc._current_test = _current_test
	ll._current_test = _current_test
	await uc.before_each()
	EventBus.flag_changed.connect(t.on_flag)
	Game.onboarding = Game.ONBOARDING
	Game.start_campaign()
	if dash:
		Game.set_ability(&"dash", true)
	await uc.call("_enter", Game.campaign_start_room(), Game.campaign_start_entry())
	t.note_room(SceneRouter.current_room)
	var legs := [
		["Wake", UCR.WAKE_ROUTE, UC + "MedicalRuin.tscn", &"from_wake"],
		["MedicalRuin", UCR.MEDICAL_RUIN_ROUTE, UC + "MaintenanceShaft.tscn", &"from_medical"],
		["MaintenanceShaft", UCR.SHAFT_TO_CLOSET + UCR.SHAFT_CLOSET_TO_EXIT, UC + "FirstPursuit.tscn", &"from_shaft"],
		["FirstPursuit", UCR.FIRST_PURSUIT_TO_PAIR + [["run", 3980], ["interact"]], UC + "BrokenLift.tscn", &"from_pursuit"],
		["BrokenLift", UCR.BROKEN_LIFT_TO_CLIMB2 + UCR.BROKEN_LIFT_TO_DOOR, UC + "CollectorBay.tscn", &"from_lift"],
		["CollectorBay", [["run", 440]], UC + "EscapeTunnel.tscn", &"from_bay"],
		["EscapeTunnel", UCR.ESCAPE_TUNNEL_VOLLEY + [["wait", 20]] + UCR.ESCAPE_TUNNEL_CLIMB, LL + "Relay.tscn", &"from_undercity"],
	]
	for leg: Array in legs:
		var room_name: String = leg[0]
		if not await _uc_leg(uc, t, room_name, leg[1], leg[2], leg[3]):
			t.broken.append(room_name)
			await _jump_to(uc, t, leg[2], leg[3], room_name)
	await uc.after_each()
	# The Lowlight chain, from the Relay balcony with the Undercity's kit.
	await ll.before_each()
	var flags := Game.state.flags.duplicate()
	ll.call("_campaign", true, true, true)
	for f: String in flags:
		if not Game.state.flags.has(f):
			Game.state.flags[f] = flags[f]
	if dash:
		Game.set_ability(&"dash", true)
	await ll.call("_enter", LL + "Relay.tscn", &"from_undercity")
	var chain := [
		["Relay", LLR.RELAY_FROM_UNDERCITY, "FloodedAlley"],
		["FloodedAlley", SLICE_ROUTES.ALLEY_ROUTE, "MarketRun"],
		["MarketRun", SLICE_ROUTES.MARKET_ROUTE, "ApartmentStack"],
		["ApartmentStack", SLICE_ROUTES.STACK_ROUTE, "NeonRoofs"],
		["NeonRoofs", SLICE_ROUTES.ROOFS_ROUTE, "PowerBlock"],
		["PowerBlock", LLR.POWER_BLOCK_ROUTE + [["exit", 1]], "SecurityStation"],
		["SecurityStation", LLR.SECURITY_ROUTE + LLR.SECURITY_ROOF + [["exit", 1]], "RainlineChase"],
		["RainlineChase", ll.call("_rainline_east_steps") + [["exit", 1]], "BellTower"],
		["BellTower", SLICE_ROUTES.BELL_ROUTE, "WardenTower"],
	]
	for leg: Array in chain:
		t.note_room(SceneRouter.current_room)
		var bot: RouteBot = ll.get("bot")
		var ok: bool = await bot.run(leg[1])
		var there: bool = SceneRouter.current_room != null and SceneRouter.current_room.name == leg[2]
		if not ok or not there:
			t.broken.append(leg[0])
			var path: String = LL + "%s.tscn" % leg[2]
			await ll.call("_enter", path, _entry_from(path, leg[0]))
		else:
			ll.call("_pacify")
			await physics_frames(10)
	EventBus.flag_changed.disconnect(t.on_flag)
	await ll.after_each()
	# The route suites' own checks are the base walk's contract; the Dash
	# walk reports breaks through `broken` instead.
	if not dash:
		for f in uc.failures + ll.failures:
			failures.append("%s: %s" % [_current_test, f])
	uc.queue_free()
	ll.queue_free()
	await physics_frames(2)
	return t


## One Undercity leg: its steps, the east door contract, the next room.
func _uc_leg(uc: RedlineTestCase, t: Trace, room_name: String, steps: Array, next_path: String, next_entry: StringName) -> bool:
	var before := uc.failures.size()
	var bot: RouteBot = uc.get("bot")
	if room_name == "FirstPursuit":
		if not await bot.run(steps):
			return false
		var box: CanvasLayer = uc.get("dialogue_box")
		if box.is_open():
			await uc.call("_close_dialogue")
		steps = [["run", 4116]]
	if room_name == "BrokenLift":
		# The walk takes the Collector fight as won (M4's BossBot covers it).
		if not await bot.run(steps):
			return false
		Game.set_flag("collector_drone_defeated")
		steps = []
	if not steps.is_empty() and not await bot.run(steps):
		uc.failures.resize(before)
		return false
	var ok: bool = uc.call("_assert_exit", 1, next_path, next_entry, "got_service_pistol" if room_name == "CollectorBay" else "")
	if ok:
		ok = await bot.run([["exit", 1]])
	ok = ok and SceneRouter.current_room_path == next_path
	uc.failures.resize(before)
	if not ok:
		return false
	_pacify_next(room_name)
	await physics_frames(10)
	uc.set("bot", RouteBot.new(get_tree(), (SceneRouter.current_room as Room).player))
	await physics_frames(10)
	t.note_room(SceneRouter.current_room)
	return true


## After a door: every enemy but the Escape Tunnel Watcher (the pistol
## lesson) idles, like the full walk.
func _pacify_next(from_room: String) -> void:
	var room := SceneRouter.current_room as Room
	for e in room.find_children("*", "Enemy", true, false):
		var enemy := e as Enemy
		if enemy.ai_enabled and not (from_room == "CollectorBay" and enemy.data.id == &"watcher"):
			enemy.ai_enabled = false
			enemy.set_ai(Enemy.AI.IDLE)
	room.player.reactor.config = room.player.reactor.config.duplicate()
	room.player.reactor.config.drain_per_second = 0.0


## A broken leg: load the next room at its door so the rest of the walk
## still runs (its story gates are still compared).
func _jump_to(uc: RedlineTestCase, t: Trace, path: String, entry: StringName, _from: String) -> void:
	await uc.call("_enter", path, entry)
	t.note_room(SceneRouter.current_room)


## The entry a room's west door uses coming from `from_room` (the chain only
## walks east): "from_" + the previous room's short id, as the doors name it.
func _entry_from(path: String, from_room: String) -> StringName:
	var packed := load(path) as PackedScene
	var inst := packed.instantiate()
	var found := &""
	for n in inst.find_children("*", "SpawnMarker", true, false):
		var id := String(n.get("spawn_id"))
		if id.begins_with("from_") and from_room.to_lower().contains(id.trim_prefix("from_").get_slice("_", 0)):
			found = StringName(id)
			break
	inst.free()
	return found
