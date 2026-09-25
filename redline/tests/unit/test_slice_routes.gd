extends RedlineTestCase
## Traversal proof: RouteBot plays each Lowlight room entrance-to-exit with
## the real movement physics (enemies disabled, Core drain off), collecting
## the quest repeaters and secrets on the way. A failure names the step.

const LL := "res://world/rooms/lowlight/"

var root: Node2D


func before_each() -> void:
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	Game.new_game()


func after_each() -> void:
	SceneRouter.current_room = null
	SceneRouter.world_root = null
	root.queue_free()
	Game.new_game()
	await physics_frames(2)


func _enter(room_file: String, entry: StringName) -> RouteBot:
	SceneRouter.goto_room(LL + room_file, entry)
	await physics_frames(3)
	_pacify()
	var bot := RouteBot.new(get_tree(), (SceneRouter.current_room as Room).player)
	await physics_frames(10)
	return bot


## Geometry-only run: no enemy AI, no Core drain, generous health.
func _pacify() -> void:
	var room := SceneRouter.current_room as Room
	for e in room.find_children("*", "Enemy", true, false):
		(e as Enemy).ai_enabled = false
		(e as Enemy).set_ai(Enemy.AI.IDLE)
	room.player.reactor.config = room.player.reactor.config.duplicate()
	room.player.reactor.config.drain_per_second = 0.0


func _run_room(room_file: String, entry: StringName, steps: Array, next_room: String) -> void:
	var bot := await _enter(room_file, entry)
	var ok: bool = await bot.run(steps)
	check(ok, "%s: %s" % [room_file, bot.failure])
	if ok and next_room != "":
		check((SceneRouter.current_room as Room).name == next_room, "%s: ended in %s, expected %s" % [room_file, SceneRouter.current_room.name, next_room])


func test_relay_to_alley() -> void:
	await _run_room("Relay.tscn", &"start", [["run", 980], ["exit", 1]], "FloodedAlley")


## The gallery door (M7): two 48 px one-way steps up to the balcony, then
## out through the upper left door, down into the Undercity's Escape Tunnel.
func test_relay_to_undercity() -> void:
	await _run_room("Relay.tscn", &"start", [
		["run", 178], ["jump", 178], ["jump", 112], ["jump", 30], ["exit", -1],
	], "EscapeTunnel")
	var room := SceneRouter.current_room as Room
	if room.name == "EscapeTunnel":
		check(room.player.global_position.distance_to(Vector2(1956, -240)) < 40.0, "should arrive at from_relay (at %s)" % room.player.global_position)


func test_flooded_alley_route_and_fragment() -> void:
	await _run_room("FloodedAlley.tscn", &"from_relay", [
		["run", 440], ["slide", 720], ["run", 1282], ["attack", 3], ["run", 1368], ["run", 1230],
		["jump", 1250], ["jump", 1275], ["jump", 1340], ["run", 1440], ["run", 1780], ["exit", 1],
	], "MarketRun")
	check(Game.state.memory_fragments.has("mf_lowlight_01"), "alley fragment not collected")


func test_market_route_repeater_and_stash() -> void:
	await _run_room("MarketRun.tscn", &"from_alley", [
		["run", 1040], ["runjump", 1096, 1240], ["run", 1320], ["jump", 1320], ["jump", 1370], ["jump", 1450],
		["run", 1500], ["interact"], ["run", 1600], ["run", 1984], ["attack", 3], ["run", 2070], ["run", 1955],
		["jump", 1955], ["jump", 2030], ["run", 2180], ["run", 2300], ["exit", 1],
	], "ApartmentStack")
	check(Game.has_flag("repeater_market"), "market repeater not realigned")
	check(Game.is_collected("cs_market"), "market core shard not collected")


func test_apartment_stack_climb() -> void:
	await _run_room("ApartmentStack.tscn", &"from_market", [
		["run", 460], ["jump", 460], ["jump", 540], ["jump", 460], ["jump", 380],
		["run", 30], ["interact"],
		["run", 180], ["jump", 180], ["jump", 100], ["jump", 180], ["jump", 262],
		["run", 460], ["jump", 460], ["jump", 540], ["jump", 460], ["jump", 380],
		["run", 74], ["attack", 3], ["run", -10], ["run", 180],
		["jump", 180], ["jump", 100], ["jump", 180], ["jump", 262], ["run", 600], ["exit", 1],
	], "NeonRoofs")
	check(Game.has_flag("repeater_stack"), "stack repeater not realigned")
	check(Game.state.memory_fragments.has("mf_lowlight_02"), "stack fragment not collected")


func test_neon_roofs_slide_jump_gate_and_shard() -> void:
	await _run_room("NeonRoofs.tscn", &"from_stack", [
		["run", 370], ["runjump", 396, 520], ["slidejump", 762, 900], ["run", 1150], ["runjump", 1176, 1300],
		["run", 1430], ["jump", 1430], ["jump", 1520], ["dodgejump", 1600, 1774], ["run", 1830],
		["run", 1990], ["runjump", 1996, 2130], ["run", 2400], ["exit", 1],
	], "PowerBlock")
	check(Game.is_collected("cs_roofs"), "roof core shard not collected")


## The 112 px gap teaches the slide-jump. A perfectly timed coyote run-jump
## or a dodge-jump can also make it (not a hard gate), but an ordinary early
## run-jump can't. Missing drops you into the service well (no pip lost), and
## the well's steps lead back up to roof 2.
func test_early_run_jump_falls_into_the_well_and_climbs_back() -> void:
	var bot := await _enter("NeonRoofs.tscn", &"from_stack")
	await bot.run([["run", 370], ["runjump", 396, 520]])
	var hp := bot.player.combat.health
	await bot.run([["runjump", 740, 940]])
	check(bot.player.global_position.y > 0.0, "an early run-jump should fall short of the 112 px gap (at %s)" % bot.player.global_position)
	check(bot.player.combat.health == hp, "the well must not cost a pip")
	var ok: bool = await bot.run([["run", 826], ["jump", 826], ["jump", 780], ["jump", 700]])
	check(ok and bot.player.global_position.y < -90.0, "the well should climb back to roof 2: %s" % bot.failure)


func test_bell_tower_climb_lever_and_office() -> void:
	await _run_room("BellTower.tscn", &"from_rainline", [
		["run", 130], ["jump", 130], ["jump", 200], ["jump", 130], ["jump", 180], ["jump", 262],
		["run", 530], ["jump", 530], ["jump", 460], ["jump", 530], ["jump", 450], ["jump", 370],
		["run", 30], ["interact"],
		["run", 130], ["jump", 130], ["jump", 200], ["jump", 130], ["jump", 180], ["jump", 262],
		["run", 548], ["heavy", 2], ["run", 602], ["run", 530],
		["jump", 530], ["jump", 460], ["jump", 530], ["jump", 450], ["jump", 370],
		["run", 40], ["interact"], ["run", 392],
		["jump", 490], ["jump", 580], ["exit", 1],
	], "WardenTower")
	check(Game.has_flag("repeater_bell"), "bell repeater not realigned")
	check(Game.has_flag("shortcut_bell_lift"), "shortcut lever not pulled")
	check(Game.state.memory_fragments.has("mf_lowlight_03"), "office fragment not collected")


func test_dash_shard_needs_dash() -> void:
	var steps := [["run", 65], ["jump", 65], ["jump", 125], ["jump", 140], ["dashjump", 158, 468]]
	var bot := await _enter("FloodedAlley.tscn", &"from_relay")
	await bot.run(steps)
	check(not Game.is_collected("cs_alley_dash"), "dash shard reachable without Dash")
	Game.set_ability(&"dash", true)
	bot = await _enter("FloodedAlley.tscn", &"from_relay")
	var ok: bool = await bot.run(steps)
	check(ok and Game.is_collected("cs_alley_dash"), "dash shard unreachable with Dash: %s" % bot.failure)
