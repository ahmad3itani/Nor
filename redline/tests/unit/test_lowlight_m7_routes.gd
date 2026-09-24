extends RedlineTestCase
## M7 Lowlight route tests: Power Block, Security Station, Rainline Chase and
## the Smuggler Route (bible §34 traversal validation), plus the D7b checks
## of the re-plumbed existing rooms. Each room task stops at its own exit and
## asserts the door contract; D6's test_full_lowlight_chain walks the chain.
## Lowlight tests start from Game.new_game() (the full kit) unless their spec
## says otherwise.
##
## Everything above the room-tests marker is the shared harness. It is
## frozen after the world skeleton (D0): a room that needs another helper
## defines a private one prefixed with its room name in its own section.

const UC := "res://world/rooms/undercity/"
const LL := "res://world/rooms/lowlight/"
const WAKE := "res://world/rooms/undercity/Wake.tscn"

var root: Node2D
## The conversation box Main.tscn would own (tests do not load Main).
var dialogue_box: CanvasLayer
## The RouteBot of the last _enter().
var bot: RouteBot
var _saved_onboarding: OnboardingConfig


func before_each() -> void:
	_saved_onboarding = Game.onboarding
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	dialogue_box = load("res://ui/dialogue/DialogueBox.gd").new()
	add_child(dialogue_box)
	bot = null
	Game.new_game()


func after_each() -> void:
	get_tree().paused = false
	Game.onboarding = _saved_onboarding
	SceneRouter.current_room = null
	SceneRouter.world_root = null
	root.queue_free()
	dialogue_box.queue_free()
	bot = null
	Game.new_game()
	await physics_frames(2)


## The forward campaign state at a later Undercity room: the real campaign
## New Game (unarmed, Core readout hidden, Wake start), plus what the rooms
## before it leave behind. Weapons are added directly, not through
## Game.grant_weapon, so no WEAPON ACQUIRED banner and no weapon_granted
## telemetry fire; the entry/Anchor respawn fields are left to _enter().
##   blade:      the MedicalRuin rack (Pulse Blade, got_pulse_blade)
##   pistol:     the CollectorBay drop (Service Pistol, got_service_pistol)
##   core_shown: BrokenLift's first Flow Zone (core_hud_hidden cleared)
func _campaign(blade := false, pistol := false, core_shown := false) -> void:
	var c := (Game.ONBOARDING as OnboardingConfig).duplicate() as OnboardingConfig
	c.enforce = true
	c.campaign_start_room = WAKE
	c.campaign_start_entry = &"start"
	Game.onboarding = c
	Game.start_campaign()
	if blade:
		_campaign_weapon("pulse_blade", "got_pulse_blade")
	if pistol:
		_campaign_weapon("service_pistol", "got_service_pistol")
	if core_shown:
		Game.set_flag("core_hud_hidden", false)


func _campaign_weapon(id: String, flag: String) -> void:
	if not Game.state.owned_weapons.has(id):
		Game.state.owned_weapons.append(id)
	Game.equip_weapon(id)
	Game.set_flag(flag)


## Loads a room at an entry like a door would, optionally pacified, and
## returns a RouteBot driving its player (also kept in `bot`).
func _enter(room_path: String, entry: StringName, pacify := true, drain_off := true) -> RouteBot:
	SceneRouter.goto_room(room_path, entry)
	await physics_frames(3)
	if pacify:
		_pacify(drain_off)
	bot = RouteBot.new(get_tree(), (SceneRouter.current_room as Room).player)
	await physics_frames(10)
	return bot


## Geometry-only play: every enemy whose AI is on goes idle. Enemies authored
## with ai_enabled = false (the dormant Needle) stay exactly as authored, and
## set pieces that are not Enemies (the Collector eye, chases, scanners,
## shutters, clamps) are never touched. drain_off stops the Core drain
## (tests that measure a Flow Zone's pace pass false).
func _pacify(drain_off := true) -> void:
	var room := SceneRouter.current_room as Room
	for e in room.find_children("*", "Enemy", true, false):
		var enemy := e as Enemy
		if enemy.ai_enabled:
			enemy.ai_enabled = false
			enemy.set_ai(Enemy.AI.IDLE)
	if drain_off:
		room.player.reactor.config = room.player.reactor.config.duplicate()
		room.player.reactor.config.drain_per_second = 0.0


## Reads the open conversation to its end (dialogue pauses the tree).
func _close_dialogue(max_lines := 12) -> void:
	var n := 0
	while dialogue_box.is_open() and n < max_lines:
		dialogue_box.advance()
		n += 1
	check(not dialogue_box.is_open(), "dialogue did not close within %d lines" % max_lines)
	get_tree().paused = false
	await physics_frames(2)


## The current room has an exit to (target_path, target_entry) with exactly
## this requires_flag, on the given side: -1 west, +1 east of the bounds
## centre (by the exit rect's centre). Values come from the door contracts
## (tests/unit/test_door_contracts.gd).
func _assert_exit(side_dir: int, target_path: String, target_entry: StringName, requires_flag := "") -> bool:
	var room := SceneRouter.current_room as Room
	var mid := room.bounds.get_center().x
	for e in room.find_children("*", "RoomExit", true, false):
		var exit := e as RoomExit
		var x := (exit.global_position - room.global_position).x + exit.size.x * 0.5
		if exit.target_room == target_path and exit.target_entry == target_entry and exit.requires_flag == requires_flag \
				and signf(x - mid) == signf(side_dir):
			return true
	check(false, "%s: no %s exit to %s/%s (requires_flag '%s')" % [room.name, "west" if side_dir < 0 else "east", target_path.get_file(), target_entry, requires_flag])
	return false


## Runs RouteBot steps on `bot`; a failure is reported with the step.
func _run(steps: Array) -> bool:
	var ok: bool = await bot.run(steps)
	check(ok, "%s: %s" % [SceneRouter.current_room.name if SceneRouter.current_room else "no room", bot.failure])
	return ok


## Harness self-test: pacify leaves nothing hostile and no drain, and the
## exit contract reads the room.
func test_harness_pacify_and_exit() -> void:
	await _enter(LL + "FloodedAlley.tscn", &"from_relay")
	var room := SceneRouter.current_room as Room
	for e in room.find_children("*", "Enemy", true, false):
		check(not (e as Enemy).ai_enabled and (e as Enemy).ai == Enemy.AI.IDLE, "%s not pacified" % e.name)
	check(room.player.reactor.config.drain_per_second == 0.0, "drain should be off")
	check(Game.state.melee_weapon != "", "Lowlight tests keep the full kit")
	_assert_exit(-1, LL + "Relay.tscn", &"from_alley")
	_assert_exit(1, LL + "MarketRun.tscn", &"from_alley")


# --- room tests (one owner per function) ---
# PowerBlock (tools/roomgen/ll_power_block.py): the Grid thesis. L0 y 0, L1
# y 192, L2 y 384, L3 y 576, basement L4 y 768; breakers pb_b1..b4 on
# circuits pb_l0..pb_l3; shutters S1 (780), S2 (176), S3 (800), S4a (700),
# S4b (360), each latching pb_<id>_latched.
const POWER_BLOCK := "res://world/rooms/lowlight/PowerBlock.tscn"
const POWER_BLOCK_LATCHES := ["pb_s1_latched", "pb_s2_latched", "pb_s3_latched", "pb_s4a_latched", "pb_s4b_latched"]


func _power_block_node(node_name: String) -> Node:
	return SceneRouter.current_room.find_child(node_name, true, false)


## Main path, from_roofs to the right basement door (enemies pacified): hit
## each floor's breaker and make its shutters, slide the duct and go low under
## S4b (the intended line), reroute at the basement lever, leave east.
func test_power_block_route() -> void:
	await _enter(POWER_BLOCK, &"from_roofs")
	var player := bot.player
	var passes: Array = []
	var on_pass := func(id: String, margin: float) -> void: passes.append([id, margin, player.is_low])
	EventBus.shutter_passed.connect(on_pass)
	# Shafts B and D: the top step sits 32 px under the floor's lip, too low for
	# Rook to walk east under it, so the bot takes the zigzag steps west first.
	var ok := await _run([
		["run", 680], ["attack", 1], ["run", 990], ["wait", 30],                   # L0: B1, S1, down shaft A
		["run", 440], ["attack", 1], ["run", -20], ["wait", 20],                   # L1: B2, the clock through S2, down shaft B
		["runjump", 396, 520], ["run", 700], ["shoot", 1, "up"], ["run", 990],     # L2: trench, high B3, S3, down shaft C
		["run", 800], ["attack", 1], ["run", 594], ["slide", 500],                 # L3: B4, S4a, the duct slot
		["run", 402], ["slide", 330], ["run", -20], ["wait", 20],                  # S4b low, down shaft D
		["run", 880], ["interact"], ["run", 960],                                  # L4: reroute, StationGate
	])
	EventBus.shutter_passed.disconnect(on_pass)
	if not ok:
		return
	check(Game.has_flag("lowlight_power_rerouted"), "the basement lever did not reroute the grid")
	for f: String in POWER_BLOCK_LATCHES:
		check(Game.has_flag(f), "%s not set" % f)
	var ids: Array = []
	for pass_info: Array in passes:
		ids.append(pass_info[0])
		if pass_info[0] != "S4b":
			check(float(pass_info[1]) >= 0.5, "shutter %s passed with a %.2f s margin (< 0.5)" % [pass_info[0], pass_info[1]])
	# S4b is the intended low line: Rook slides under it about when its open
	# clock runs out (the standing margin is 0.18 s, for experts). PowerShutter
	# reports the open clock while the panel is still up, so the low line's
	# margin is read against the end of the slot (open + drop + slot).
	var s4b := _power_block_node("Shutter_S4b") as PowerShutter
	var s4b_pass: Array = passes.filter(func(pass_info: Array) -> bool: return pass_info[0] == "S4b")
	check(s4b_pass.size() == 1 and bool(s4b_pass[0][2]), "S4b should be passed low (the intended line): %s" % str(s4b_pass))
	if s4b != null:
		var t := s4b.timing
		var low_margin := t.open + t.drop + t.slot - s4b.t_open
		check(low_margin >= 0.5, "S4b low-line margin %.2f s (< 0.5)" % low_margin)
	check(ids == ["S1", "S2", "S3", "S4a", "S4b"], "each shutter passes once, in order: %s" % str(ids))
	var gate := _power_block_node("StationGate") as Gate
	check(gate != null and not gate.closed, "StationGate should be open on priority power")
	_assert_exit(1, LL + "SecurityStation.tscn", &"from_power", "lowlight_power_rerouted")
	_assert_exit(-1, LL + "NeonRoofs.tscn", &"from_power")
	_assert_exit(-1, LL + "SmugglerRoute.tscn", &"from_power")
	if await _run([["exit", 1]]):
		check(SceneRouter.current_room.name == "SecurityStation", "the right basement door leads to SecurityStation, not %s" % SceneRouter.current_room.name)


## The Meter Room secret: after the reroute the grid lock (MeterGate) fails
## open; climb the mezzanine from the entrance, break the cabinet, take both.
func test_meter_room() -> void:
	Game.set_flag("lowlight_power_rerouted")
	await _enter(POWER_BLOCK, &"from_roofs")
	var gate := _power_block_node("MeterGate") as Gate
	check(gate != null and not gate.closed, "MeterGate should be open after the reroute")
	var scrap := Game.state.total_scrap()
	if not await _run([["run", 160], ["jump", 198], ["jump", 262], ["run", 364], ["attack", 3]]):
		return
	check(Game.is_collected("pb_meter_cabinet"), "three light attacks should break the meter cabinet (25 HP)")
	if not await _run([["run", 420], ["wait", 90]]):
		return
	check(Game.is_collected("sb_pb_meter"), "the meter stash was not collected")
	check(Game.state.total_scrap() == scrap + 70, "cabinet 30 + stash 40 Scrap expected, got +%d" % (Game.state.total_scrap() - scrap))


## The M5 slot test on the real S2 (176..192, L1 y 192, shutter_run): Rook
## at x 218 facing west. Mid-slot a slide passes and latches it; after a full
## cycle a run is blocked; a re-trip reopens it.
func test_pb_slot() -> void:
	await _enter(POWER_BLOCK, &"from_roofs")
	var s := _power_block_node("Shutter_S2") as PowerShutter
	var b2 := _power_block_node("Breaker_pb_b2") as Breaker
	check(s != null and b2 != null, "PowerBlock needs Shutter_S2 and Breaker_pb_b2")
	if s == null or b2 == null:
		return
	var t := s.timing
	check(t == load("res://data/level/shutter_run.tres"), "S2 should use shutter_run")
	bot.player.teleport(Vector2(218, 192))
	bot.player.facing = -1
	await physics_frames(3)
	b2.trip()
	await physics_frames(int(ceil((t.open + t.drop + t.slot * 0.5) * 60.0)))
	check(s.state == PowerShutter.State.SLOT, "mid-slot state expected, got %s" % s.state_name())
	var ok := await _run([["slide", 150]])
	check(ok and bot.player.global_position.x < 170.0, "a slide should pass the 24 px slot (x %.0f)" % bot.player.global_position.x)
	check(Game.has_flag("pb_s2_latched"), "a low pass should latch S2")
	# Fresh state: after the full cycle a standing run is blocked.
	Game.new_game()
	await _enter(POWER_BLOCK, &"from_roofs")
	s = _power_block_node("Shutter_S2") as PowerShutter
	b2 = _power_block_node("Breaker_pb_b2") as Breaker
	bot.player.teleport(Vector2(218, 192))
	bot.player.facing = -1
	await physics_frames(3)
	b2.trip()
	await physics_frames(int(ceil((t.open + t.drop + t.slot + t.seal + 0.1) * 60.0)))
	check(s.state == PowerShutter.State.CLOSED, "after the cycle S2 is closed again (%s)" % s.state_name())
	await bot.run([["run", 150]])
	check(bot.player.global_position.x > 192.0, "a closed S2 must block the run (x %.1f)" % bot.player.global_position.x)
	await physics_frames(30)  # past the breaker's re-arm time
	check(b2.trip(), "B2 should re-arm")
	await physics_frames(2)
	check(s.state == PowerShutter.State.OPEN, "a re-trip should reopen S2 (%s)" % s.state_name())
	ok = await _run([["run", 150]])
	check(ok and Game.has_flag("pb_s2_latched"), "after the re-trip a run passes S2 (x %.0f)" % bot.player.global_position.x)


## The high breaker B3 (box 692..708 x 288..312, floor -96 on L2) is reached
## by a jump + air light from x 700, and by every gun straight up.
func test_pb_b3_reach() -> void:
	await _enter(POWER_BLOCK, &"from_roofs")
	var b3 := _power_block_node("Breaker_pb_b3") as Breaker
	check(b3 != null, "PowerBlock needs Breaker_pb_b3")
	if b3 == null:
		return
	var p := bot.player
	var input := bot.input
	p.teleport(Vector2(700, 384))
	p.facing = 1
	await physics_frames(3)
	input.press_jump()
	for f in 40:
		await physics_frames(1)
		if p.global_position.y <= 384.0 - 40.0 and p.velocity.y < 0.0:
			break
	input.press_light()
	await physics_frames(40)
	input.release_jump()
	check(b3.trips == 1, "jump + air light from x 700 should trip pb_b3 (trips %d, feet peaked near %.0f)" % [b3.trips, p.global_position.y])
	for gun: String in ["service_pistol", "heavy_revolver", "scattergun"]:
		p.combat.set_loadout(Game.catalog.weapon("pulse_blade"), Game.catalog.weapon(gun))
		var before := b3.trips
		p.teleport(Vector2(700, 384))
		await physics_frames(36)  # past the re-arm time
		await _run([["shoot", 1, "up"]])
		check(b3.trips == before + 1, "%s straight up from x 700 should trip pb_b3" % gun)


## Safety sensor on the real S2: Rook crouched in the column through the drop,
## slot and seal is held over, never crushed, and takes no damage.
func test_pb_safety_sensor() -> void:
	await _enter(POWER_BLOCK, &"from_roofs")
	var s := _power_block_node("Shutter_S2") as PowerShutter
	var b2 := _power_block_node("Breaker_pb_b2") as Breaker
	check(s != null and b2 != null, "PowerBlock needs Shutter_S2 and Breaker_pb_b2")
	if s == null or b2 == null:
		return
	var p := bot.player
	b2.trip()
	p.teleport(Vector2(184, 192))
	bot.input.down_held = true
	var t := s.timing
	await physics_frames(int(ceil((t.open + t.drop + t.slot + t.seal + 0.5) * 60.0)))
	check(p.is_low, "Rook should be crouched in the S2 column")
	check(s.state == PowerShutter.State.SEAL and s.is_holding(), "the seal should hold over Rook (%s)" % s.state_name())
	check(s.gap >= s.slot_gap() - 0.01, "S2 held at slot height (gap %.1f)" % s.gap)
	check(p.combat.health == p.combat.config.max_health, "a held shutter deals no damage")
	bot.input.down_held = false


## Old saves (D-075): a v3-style save (full kit, Krail down, the bell lift
## open, no reroute, no latches) can walk SecurityStation's unflagged left
## exit into from_security, west of StationGate. The basement keeps the Anchor,
## the lever and both left-side ways out reachable with no ability, and shaft
## D only leads up to L3's west end, which the unlatched S4b bounds.
func test_power_block_backward_from_security() -> void:
	Game.set_ability(&"dash", true)
	Game.set_flag("warden_krail_defeated")
	Game.set_flag("shortcut_bell_lift")
	await _enter(POWER_BLOCK, &"from_security")
	var p := bot.player
	check(p.is_on_floor() and absf(p.global_position.y - 768.0) < 1.0 and p.global_position.x < 992.0,
		"from_security should stand Rook on L4 west of StationGate (%s)" % p.global_position)
	check(not Game.has_flag("lowlight_power_rerouted"), "the old save starts without the reroute")
	# Rest, then reroute: the Anchor and the lever are both on this side.
	if not await _run([["run", 420], ["interact"]]):
		return
	check(Game.state.last_anchor_id == "power_block", "Rook should rest at the power_block Anchor")
	if not await _run([["run", 880], ["interact"]]):
		return
	check(Game.has_flag("lowlight_power_rerouted"), "the lever should reroute the grid from the east side too")
	var gate := _power_block_node("StationGate") as Gate
	check(gate != null and not gate.closed, "StationGate should open with the reroute")
	# Up shaft D to L3's west end: unlatched S4b (x 360) holds him at x < 360.
	if not await _run([["run", 44], ["jump", 44], ["jump", -12], ["jump", 44], ["jump", 110], ["run", 300]]):
		return
	check(absf(p.global_position.y - 576.0) < 1.0, "shaft D should reach L3 (y %.0f)" % p.global_position.y)
	bot.input.move_x = 1
	await physics_frames(90)
	bot.input.move_x = 0
	check(p.global_position.x + 6.0 <= 360.5, "unlatched S4b should bound L3's west end (x %.1f)" % p.global_position.x)
	for f: String in POWER_BLOCK_LATCHES:
		check(not Game.has_flag(f), "%s should still be unset" % f)
	# Back down the zigzag steps and out by the left basement door.
	if not await _run([["run", -20], ["wait", 20], ["run", 100], ["wait", 20]]):
		return
	check(absf(p.global_position.y - 768.0) < 1.0, "back on L4 (y %.0f)" % p.global_position.y)
	_assert_exit(-1, LL + "SmugglerRoute.tscn", &"from_power")
	if await _run([["exit", -1]]):
		check(SceneRouter.current_room.name == "SmugglerRoute", "the left basement door leads to SmugglerRoute, not %s" % SceneRouter.current_room.name)


func test_security_station_route() -> void:
	print("PENDING: SecurityStation")


func test_rainline_route() -> void:
	print("PENDING: RainlineChase")


func test_smuggler_route() -> void:
	print("PENDING: SmugglerRoute")


func test_warden_tower_clamp_in_room() -> void:
	print("PENDING: D7b")


func test_stack_hatch_both_ways() -> void:
	print("PENDING: D7b")


func test_relay_iko_presence() -> void:
	print("PENDING: D7b")


func test_full_lowlight_chain() -> void:
	print("PENDING: D6")
