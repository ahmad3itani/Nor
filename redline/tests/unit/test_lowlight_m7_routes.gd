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


# --- Security Station (tools/roomgen/ll_security_station.py) ---
## Ground floor east (calibration lane, lobby beams, stairwell run-jump),
## cell-block climb, upper floor west, atrium climb, roof east under the
## breaker-darkened searchlight.
const SECURITY_ROUTE := [
	["runjump", 60, 150], ["run", 180], ["slide", 240], ["run", 295], ["dodge", 295],        # calibration: LOW, HIGH, FULL
	["runjump", 380, 480], ["run", 614], ["slide", 700], ["run", 855], ["dodge", 855],       # lobby: LOW, HIGH, pulsing FULL
	["runjump", 956, 1070], ["run", 1140], ["jump", 1140], ["jump", 1200], ["jump", 1140], ["jump", 1080],
	["run", 789], ["dodge", 789], ["run", 570], ["slide", 480],                              # Monitor Corridor, westbound
	["run", 370], ["jump", 320], ["jump", 250], ["jump", 320], ["jump", 390],               # atrium
]
const SECURITY_ROOF := [["run", 440], ["attack", 1], ["run", 1210]]

## [beam_id, mode] per scanner_tripped while a Security Station test listens
## (append-only: lambdas copy locals).
var _security_trips: Array = []


func _security_station_listen() -> void:
	_security_trips.clear()
	EventBus.scanner_tripped.connect(_security_station_on_trip)


func _security_station_unlisten() -> void:
	if EventBus.scanner_tripped.is_connected(_security_station_on_trip):
		EventBus.scanner_tripped.disconnect(_security_station_on_trip)


func _security_station_on_trip(id: String, mode: int) -> void:
	_security_trips.append([id, mode])


## Trips from live (damage > 0) beams so far.
func _security_station_live_trips(room: Room) -> Array:
	var out: Array = []
	for t: Array in _security_trips:
		var beam := _security_station_beam(room, t[0])
		if beam == null or beam.data.damage > 0:
			out.append(t[0])
	return out


func _security_station_beam(room: Room, id: String) -> ScannerBeam:
	return room.get_node_or_null(NodePath("Hazards/Scanner_" + id)) as ScannerBeam


## Samples every physics frame until `done` holds a value: appends Rook's x
## to `live_at` whenever he is under the searchlight's sweep (x 600..1040)
## while the beam is not offline.
func _security_station_watch_roof(room: Room, beam: ScannerBeam, live_at: Array, done: Array) -> void:
	while done.is_empty():
		await physics_frames(1)
		if not is_instance_valid(room) or not is_instance_valid(room.player) or not is_instance_valid(beam):
			return
		var x := room.player.global_position.x - room.global_position.x
		var on_roof := room.player.global_position.y - room.global_position.y < -300.0
		if on_roof and x > 600.0 and x < 1040.0 and beam.offline_left <= 0.0:
			live_at.append(x)


func test_security_station_route() -> void:
	await _enter(LL + "SecurityStation.tscn", &"from_power")
	var room := SceneRouter.current_room as Room
	var max_hp := room.player.combat.health
	_security_station_listen()
	var ok := await _run(SECURITY_ROUTE)
	if ok:
		check(room.player.global_position.y < -380.0, "the atrium climb should end on the roof (y %.0f)" % room.player.global_position.y)
		var light := _security_station_beam(room, "ss_searchlight")
		var live_at: Array = []
		var done: Array = []
		_security_station_watch_roof(room, light, live_at, done)
		ok = await _run(SECURITY_ROOF)
		done.append(true)
		check(light.trips == 0, "the searchlight tripped during the roof pass")
		check(live_at.is_empty(), "ss_searchlight should be offline for the whole roof pass (live at x %s)" % str(live_at.slice(0, 4)))
	var live := _security_station_live_trips(room)
	check(live.is_empty(), "live beams tripped on the main route: %s" % str(live))
	check(room.player.combat.health == max_hp, "the route should cost no pip (%d/%d)" % [room.player.combat.health, max_hp])
	_security_station_unlisten()
	_assert_exit(-1, LL + "PowerBlock.tscn", &"from_security")
	_assert_exit(1, LL + "RainlineChase.tscn", &"from_security")
	if ok:
		ok = await _run([["exit", 1]])
		check(ok and SceneRouter.current_room != null and SceneRouter.current_room.name == "RainlineChase", "the roof door should lead to RainlineChase")


## The optional B1 isolation block: fall into the stairwell (the first
## climb-back step catches Rook), step down to the B1 floor, pass the two
## pulsing FULLs and the HIGH westbound, break the cell bars and collect
## Cell Four (mf_lowlight_04) and the scrap cache, then return east and
## climb the steps back to the ground floor: the fall is never a trap.
func test_ss_b1() -> void:
	await _enter(LL + "SecurityStation.tscn", &"from_power")
	var room := SceneRouter.current_room as Room
	room.player.global_position = room.global_position + Vector2(930, 0)
	await physics_frames(2)
	var ok := await _run([["run", 1000], ["run", 950], ["wait", 30]])
	check(ok and room.player.global_position.y > 140.0, "Rook should reach the B1 floor (y %.0f)" % room.player.global_position.y)
	if ok:
		ok = await _run([["dodge", 945], ["dodge", 845], ["run", 746], ["slide", 700], ["attack", 3], ["run", 640], ["run", 628]])
	check(Game.state.memory_fragments.has("mf_lowlight_04"), "Cell Four fragment not collected")
	check(Game.is_collected("sb_ss_cell4"), "cell scrap cache not collected")
	if ok:
		ok = await _run([["slide", 760], ["dodge", 793], ["dodge", 893], ["run", 975], ["jump", 980], ["jump", 1020], ["jump", 1070]])
		check(ok and absf(room.player.global_position.y) < 2.0, "the climb-back steps should reach the ground floor (y %.0f)" % room.player.global_position.y)


## Walking into each calibration beam costs no pip and shoves Rook at least
## 24 px back toward where he came from.
func test_ss_calibration() -> void:
	await _enter(LL + "SecurityStation.tscn", &"from_power")
	var room := SceneRouter.current_room as Room
	var p := room.player
	var max_hp := p.combat.health
	_security_station_listen()
	for id: String in ["ss_cal_low", "ss_cal_high", "ss_cal_full"]:
		var beam := _security_station_beam(room, id)
		check(beam != null and beam.data.damage == 0, "%s should be a calibration beam" % id)
		if beam == null:
			continue
		p.global_position = room.global_position + Vector2(beam.position.x - 50.0, 0)
		p.velocity = Vector2.ZERO
		beam.grace_left = 0.0
		await physics_frames(6)
		var before := _security_trips.size()
		var trip_x := INF
		bot.input.move_x = 1
		for f in 90:
			await physics_frames(1)
			if _security_trips.size() > before:
				trip_x = p.global_position.x - room.global_position.x
				bot.input.move_x = 0
				break
		bot.input.move_x = 0
		check(_security_trips.size() == before + 1, "%s: walking in should trip once" % id)
		await physics_frames(45)
		var x := p.global_position.x - room.global_position.x
		check(p.combat.health == max_hp, "%s: calibration must not cost a pip" % id)
		check(x <= trip_x - 24.0, "%s: shove should move Rook >= 24 px back (trip %.1f, now %.1f)" % [id, trip_x, x])
	_security_station_unlisten()


## ss_searchlight uses the ScannerBeam defaults (offline_open 5.5 s,
## offline_warn 1.5 s): after the roof breaker trips, the beam is dark for
## 5.5 s +- one frame, and lit again after.
func test_ss_roof_offline_window() -> void:
	await _enter(LL + "SecurityStation.tscn", &"from_rainline")
	var room := SceneRouter.current_room as Room
	var light := _security_station_beam(room, "ss_searchlight")
	check(light != null and light.circuit == &"ss_roof", "ss_searchlight should be on circuit ss_roof")
	check_near(light.offline_open, 5.5, 0.001, "offline_open default")
	check_near(light.offline_warn, 1.5, 0.001, "offline_warn default")
	var breaker := room.get_node("Interactables/Breaker_ss_roof") as Breaker
	check(breaker.trip(), "the roof breaker should trip")
	var frames := 0
	while light.state() == ScannerBeam.State.OFFLINE and frames < 600:
		await physics_frames(1)
		frames += 1
	check(absi(frames - 330) <= 1, "offline for %d frames, expected 330 +- 1" % frames)
	check(light.state() != ScannerBeam.State.OFFLINE, "the searchlight should come back")


## D-075 backward route for old saves: enter from the Rainline roof door,
## walk west over the roof (the searchlight may cost pips), drop down the
## atrium and leave by the calibration lane to PowerBlock from_security.
func test_security_station_backward() -> void:
	await _enter(LL + "SecurityStation.tscn", &"from_rainline")
	var room := SceneRouter.current_room as Room
	_security_station_listen()
	# Roof west (the live searchlight may bite), off the roof onto the top
	# atrium step, onto the middle step, then off its west end to the ground,
	# west of the HIGH calibration housing. Then back up to take the LOW
	# calibration beam at run speed, and out of the west door.
	var ok := await _run([["run", 380], ["run", 330], ["run", 250], ["run", 150], ["wait", 30]])
	check(ok and absf(room.player.global_position.y) < 2.0, "the atrium drop should reach the ground floor (y %.0f)" % room.player.global_position.y)
	if ok:
		ok = await _run([["run", 190], ["wait", 20], ["runjump", 145, 40], ["run", 0]])
	var live: Array = _security_station_live_trips(room).filter(func(id: String) -> bool: return id != "ss_searchlight")
	check(live.is_empty(), "westbound, only the searchlight may bite: %s" % str(live))
	check(room.player.combat.health > 0, "Rook should reach the west door alive")
	_security_station_unlisten()
	_assert_exit(-1, LL + "PowerBlock.tscn", &"from_security")
	if ok:
		ok = await _run([["exit", -1]])
	check(ok and SceneRouter.current_room != null and SceneRouter.current_room.name == "PowerBlock", "the west door should lead to PowerBlock")


# --- RainlineChase (the district climax; ChaseDirector 'rainline') ------------------
# Private helpers are prefixed _rainline_. Positions are room coordinates
# (the room sits at the origin). Chase numbers: data/world/chase/rainline.tres
# (start_lead 380, respawn_lead 260, regroup 1 s); path x 60 -> 3620,
# checkpoints 440 / 1200 / 2000 / 2980 (index 0..3).

func _rainline_path() -> String:
	return LL + "RainlineChase.tscn"


## The eastbound main route from from_security to the terminal (the spec's
## route, bot about 28 s).
func _rainline_east_steps() -> Array:
	return [["run", 790], ["runjump", 796, 900], ["runjump", 1036, 1160], ["run", 1200], ["slide", 1300],
		["slidejump", 1420, 1560], ["run", 1690], ["runjump", 1696, 1790], ["run", 1830], ["slide", 1930],
		["run", 2210], ["jump", 2270], ["run", 2330], ["runjump", 2436, 2560], ["runjump", 2696, 2800], ["run", 2940],
		["runjump", 3196, 3320], ["runjump", 3492, 3600], ["run", 4120]]


## Westbound, from from_bell (4100) down the car coupler step, over the cars,
## under the gantries and back to the Security door (x 20). The chase stays
## idle the whole way (it only arms moving east).
func _rainline_west_steps() -> Array:
	return _rainline_west_to_cars() + [["run", 2530], ["runjump", 2524, 2400], ["run", 2200], ["slide", 1840],
		["run", 1780], ["runjump", 1764, 1650], ["run", 1560], ["slidejump", 1534, 1410], ["run", 1300],
		["slide", 1210], ["run", 1136], ["runjump", 1132, 1010], ["run", 880], ["runjump", 876, 770], ["run", 20]]


## From from_bell west to the top of CarB (x about 2640, y -48).
func _rainline_west_to_cars() -> Array:
	return [["run", 3590], ["runjump", 3580, 3460], ["run", 3310], ["runjump", 3298, 3190], ["run", 2990],
		["jump", 2945], ["jump", 2880], ["run", 2770], ["runjump", 2764, 2640]]


func _rainline_director() -> ChaseDirector:
	var room := SceneRouter.current_room
	if room == null or not is_instance_valid(room):
		return null
	return room.find_child("Chase_rainline", true, false) as ChaseDirector


func _rainline_pursuers() -> Array:
	var out: Array = []
	var room := SceneRouter.current_room
	if room == null or not is_instance_valid(room):
		return out
	for n in room.find_children("*", "", true, false):
		if n is Pursuer:
			out.append(n)
	return out


## Records the chase signals (lambdas append to shared arrays). Pass the
## result to _rainline_unwatch() before the test ends.
func _rainline_watch() -> Dictionary:
	var w := {"started": [], "caught": [], "completed": []}
	w["on_started"] = func(id: String) -> void:
		(w["started"] as Array).append(id)
	w["on_caught"] = func(id: String, cp: int) -> void:
		var room := SceneRouter.current_room as Room
		var d := _rainline_director()
		var p := room.player
		(w["caught"] as Array).append({"id": id, "cp": cp, "x": p.global_position.x, "y": p.global_position.y,
			"hp": p.combat.health, "dead": p.combat.dead, "source": p.combat.last_damage_source,
			"pursuer_x": d.point_at(d.pursuer_progress).x if d else -1.0})
	w["on_completed"] = func(id: String, seconds: float, catches: int, min_lead: float) -> void:
		(w["completed"] as Array).append({"id": id, "seconds": seconds, "catches": catches, "min_lead": min_lead,
			"flag": Game.has_flag("chase_rainline_done")})
	EventBus.chase_started.connect(w["on_started"])
	EventBus.chase_caught.connect(w["on_caught"])
	EventBus.chase_completed.connect(w["on_completed"])
	return w


func _rainline_unwatch(w: Dictionary) -> void:
	EventBus.chase_started.disconnect(w["on_started"])
	EventBus.chase_caught.disconnect(w["on_caught"])
	EventBus.chase_completed.disconnect(w["on_completed"])


## Kills Rook (a lethal hit, as a Needle would land) and waits for the room to
## reload at the last Anchor; rebinds `bot` to the new player.
func _rainline_die_and_respawn() -> Room:
	var room := SceneRouter.current_room as Room
	var old_id := room.get_instance_id()
	room.player.combat.take_damage(99, Vector2(-60, -120), 0.0, true, "Needle/needle_lunge")
	for f in 400:
		var cur := SceneRouter.current_room
		if is_instance_valid(cur) and cur.get_instance_id() != old_id and not SceneRouter.transitioning:
			break
		await physics_frames(1)
	room = SceneRouter.current_room as Room
	check(room != null and room.get_instance_id() != old_id, "death should reload the room")
	await physics_frames(10)
	_pacify()
	bot = RouteBot.new(get_tree(), room.player)
	return room


func _rainline_set_anchor() -> void:
	Game.state.last_anchor_room = _rainline_path()
	Game.state.last_anchor_id = "rainline_platform"


func test_rainline_route() -> void:
	# Pursuer active (the ChaseDirector is not an Enemy: _pacify leaves it);
	# the well Needles are pacified.
	await _enter(_rainline_path(), &"from_security")
	var w := _rainline_watch()
	var ok := await _run(_rainline_east_steps())
	_rainline_unwatch(w)
	check(ok, "Rainline route failed")
	check(Game.has_flag("chase_rainline_done"), "crossing x 3620 during the chase sets chase_rainline_done")
	check((w["started"] as Array).size() == 1, "the chase arms once, got %d" % (w["started"] as Array).size())
	check((w["caught"] as Array).is_empty(), "a clean run is never caught: %s" % str(w["caught"]))
	var completed: Array = w["completed"]
	check(completed.size() == 1, "chase_completed once, got %d" % completed.size())
	if completed.size() == 1:
		check(bool(completed[0]["flag"]), "the flag is set when chase_completed fires")
		check(float(completed[0]["min_lead"]) >= 200.0, "min_lead >= 200 on the bot route, got %.1f" % float(completed[0]["min_lead"]))
		print("Rainline route: %.1f s, min_lead %.0f" % [float(completed[0]["seconds"]), float(completed[0]["min_lead"])])
	_assert_exit(1, LL + "BellTower.tscn", &"from_rainline")
	_assert_exit(-1, LL + "SecurityStation.tscn", &"from_rainline")
	if ok and await _run([["exit", 1]]):
		check(SceneRouter.current_room_path == LL + "BellTower.tscn", "the east door leads to the Bell Tower")


func test_rainline_caught() -> void:
	await _enter(_rainline_path(), &"from_security")
	var w := _rainline_watch()
	await _run([["run", 790], ["runjump", 796, 900], ["runjump", 1036, 1160], ["run", 1210], ["wait", 300]])
	_rainline_unwatch(w)
	var caught: Array = w["caught"]
	check(not caught.is_empty(), "standing past CP 1200 gets Rook caught")
	if caught.is_empty():
		return
	check(int(caught[0]["hp"]) == 4, "a catch costs one pip (5 -> 4), got %d" % int(caught[0]["hp"]))
	check(int(caught[0]["cp"]) == 1, "checkpoint index 1 (x 1200), got %d" % int(caught[0]["cp"]))
	check_near(float(caught[0]["x"]), 1200.0, 0.5, "Rook returns to CP 1200")
	check_near(float(caught[0]["pursuer_x"]), 940.0, 0.5, "the Sweeper restarts 260 behind CP 1200")
	check(String(caught[0]["source"]) == "chase/rainline", "catch source chase/rainline, got %s" % caught[0]["source"])


func test_rainline_caught_before_first_cp() -> void:
	await _enter(_rainline_path(), &"from_security")
	var w := _rainline_watch()
	await _run([["run", 600], ["wait", 300]])
	_rainline_unwatch(w)
	var caught: Array = w["caught"]
	check(not caught.is_empty(), "waiting at x 600 gets Rook caught")
	if caught.is_empty():
		return
	check(int(caught[0]["cp"]) == 0, "checkpoint index 0 (ChaseStart), got %d" % int(caught[0]["cp"]))
	check_near(float(caught[0]["x"]), 440.0, 0.5, "Rook returns to CP 440")
	check_near(float(caught[0]["pursuer_x"]), 180.0, 0.5, "the Sweeper restarts at 440 - 260")


func test_rainline_pit_catch() -> void:
	await _enter(_rainline_path(), &"from_security")
	var w := _rainline_watch()
	await _run([["run", 790], ["runjump", 796, 900], ["run", 1000]])
	var safe := (SceneRouter.current_room as Room).player.last_safe_position
	# A short hop into G2 (1040..1128): the step itself "fails" (Rook lands
	# back at the checkpoint, not at 1080), which is the point.
	await bot.run([["jump", 1080]])
	_rainline_unwatch(w)
	var caught: Array = w["caught"]
	check(caught.size() == 1, "one pit catch in G2, got %d" % caught.size())
	if caught.is_empty():
		return
	var c: Dictionary = caught[0]
	check(String(c["source"]) == "pit", "the pit is handled by the chase (source 'pit'), got %s" % c["source"])
	check(int(c["hp"]) == 4 and not bool(c["dead"]), "a chase pit costs one nonlethal pip, hp %d" % int(c["hp"]))
	check(int(c["cp"]) == 0, "before CP 1200 the checkpoint index is 0, got %d" % int(c["cp"]))
	check_near(float(c["x"]), 440.0, 0.5, "Rook returns to CP 440, not his last safe ground")
	check(absf(float(c["x"]) - safe.x) > 100.0, "no last_safe_position teleport (safe was %s)" % safe)
	check_near(float(c["pursuer_x"]), 180.0, 0.5, "the Sweeper restarts at 440 - respawn_lead 260")


func test_rainline_nonlethal() -> void:
	await _enter(_rainline_path(), &"from_security")
	var p := (SceneRouter.current_room as Room).player
	p.combat.health = 1
	var w := _rainline_watch()
	await _run([["run", 600], ["wait", 300]])
	_rainline_unwatch(w)
	check(not (w["caught"] as Array).is_empty(), "Rook is caught at 1 pip")
	check(not p.combat.dead and p.combat.health == 1, "a catch at 1 pip never kills (hp %d, dead %s)" % [p.combat.health, p.combat.dead])


func test_rainline_death_rearm() -> void:
	_rainline_set_anchor()
	await _enter(_rainline_path(), &"from_security")
	var w := _rainline_watch()
	await _run([["run", 600]])
	check(_rainline_director().is_active(), "the chase is live at x 600")
	var room := await _rainline_die_and_respawn()
	check_near(room.player.global_position.x, 200.0, 1.0, "Rook respawns at the rainline_platform Anchor")
	check(_rainline_director().state == ChaseDirector.State.IDLE, "no chase after the respawn (%s)" % _rainline_director().state_name())
	check((w["started"] as Array).size() == 1, "the respawn does not arm the chase")
	await _run([["run", 380]])
	check((w["started"] as Array).size() == 1, "walking toward ChaseStart does not arm it yet")
	await _run([["run", 440]])
	_rainline_unwatch(w)
	check((w["started"] as Array).size() == 2 and _rainline_director().is_active(), "walking 220 px east into ChaseStart re-arms the chase")
	check(not Game.has_flag("chase_rainline_done"), "a death never sets the done flag")


func test_rainline_transit_arrival() -> void:
	# A transit arrival lands on the Anchor's own spawn (Game.travel_to).
	_rainline_set_anchor()
	var w := _rainline_watch()
	await _enter(_rainline_path(), &"rainline_platform")
	var p := (SceneRouter.current_room as Room).player
	check_near(p.global_position.x, 200.0, 1.0, "arrives at the Anchor")
	await physics_frames(30)
	check((w["started"] as Array).is_empty() and _rainline_director().state == ChaseDirector.State.IDLE, "arriving before ChaseStart stays idle")
	await _run([["run", 460]])
	_rainline_unwatch(w)
	check((w["started"] as Array).size() == 1 and _rainline_director().is_active(), "crossing ChaseStart arms the chase")


func test_rainline_done_flag_survives_death() -> void:
	_rainline_set_anchor()
	await _enter(_rainline_path(), &"from_security")
	var steps := _rainline_east_steps()
	steps[steps.size() - 1] = ["run", 3700]
	var ok := await _run(steps)
	check(ok and Game.has_flag("chase_rainline_done"), "crossing x 3620 sets the flag")
	var room := await _rainline_die_and_respawn()
	check(Game.has_flag("chase_rainline_done"), "a death after the finish keeps chase_rainline_done")
	check(_rainline_director().state == ChaseDirector.State.DONE, "the reloaded chase is DONE")
	check(_rainline_pursuers().is_empty(), "no Sweeper after the finish")
	check(not room.pit_override.is_valid(), "no chase pit override after the finish")


func test_rainline_hurt_stun_fairness() -> void:
	# One forced hit (knocked back toward the Sweeper) on flat deck at each
	# x: the hurt stun must never cost a catch on the bot's line.
	await _enter(_rainline_path(), &"from_security")
	var w := _rainline_watch()
	var p := (SceneRouter.current_room as Room).player
	var legs := [
		[["run", 700]],
		[["run", 790], ["runjump", 796, 900], ["runjump", 1036, 1150]],
		[["run", 1200], ["slide", 1300], ["slidejump", 1420, 1560], ["run", 1650]],
		[["run", 1690], ["runjump", 1696, 1790], ["run", 1830], ["slide", 1930], ["run", 2150]],
		[["run", 2210], ["jump", 2270], ["run", 2330], ["runjump", 2436, 2560], ["runjump", 2696, 2800], ["run", 2950]],
		[["run", 2990], ["runjump", 3196, 3320], ["run", 3400]],
		[["runjump", 3492, 3600], ["run", 3700]],
	]
	var hits := 0
	for i in legs.size():
		if not await _run(legs[i]):
			break
		if i == legs.size() - 1:
			break
		p.combat.health = 5
		p.combat.hurt_invuln_timer = 0.0
		p.combat.take_damage(1, Vector2(-p.facing * 60.0, -120.0), 0.06, true, "test/knock")
		hits += 1
		await physics_frames(24)
	_rainline_unwatch(w)
	check(hits == 6, "six forced hits, got %d" % hits)
	check((w["caught"] as Array).is_empty(), "no catch from a hurt stun: %s" % str(w["caught"]))
	check(Game.has_flag("chase_rainline_done"), "the knocked-about run still finishes")


func test_rainline_lowroad() -> void:
	await _enter(_rainline_path(), &"from_security")
	var w := _rainline_watch()
	var p := (SceneRouter.current_room as Room).player
	await _run([["run", 790], ["runjump", 796, 900], ["runjump", 1036, 1160], ["run", 1200], ["slide", 1300],
		["slidejump", 1370, 1470]])
	check_near(p.global_position.y, 72.0, 0.5, "an early G3 slide-jump lands on the LowRoad")
	check(p.global_position.x > 1420.0 and p.global_position.x < 1532.0, "landed under G3 (x %.0f)" % p.global_position.x)
	var ok := await _run([["run", 1722], ["jump", 1730], ["jump", 1800], ["run", 1830]])
	_rainline_unwatch(w)
	check(ok and absf(p.global_position.y) < 1.0, "climbs out through the hatch onto D5 (at %s)" % p.global_position)
	check((w["caught"] as Array).is_empty(), "the LowRoad is below the Sweeper: no reset, got %s" % str(w["caught"]))
	check(p.combat.health == 5, "no pip lost on the LowRoad, hp %d" % p.combat.health)


func test_rainline_signal_box_after_chase() -> void:
	Game.set_flag("chase_rainline_done")
	await _enter(_rainline_path(), &"from_bell")
	var p := (SceneRouter.current_room as Room).player
	var scrap0 := Game.state.total_scrap()
	# Down the cars to CarA, up the one-way to the high line, dodge-jump the
	# 130 px gap to the signal box's ledge, break the wall, collect.
	var ok := await _run(_rainline_west_to_cars() + [["run", 2530], ["runjump", 2524, 2400], ["run", 2290],
		["jump", 2290], ["jump", 2350], ["run", 2340], ["dodgejump", 2418, 2580]])
	check(ok and absf(p.global_position.y + 144.0) < 1.0, "reached HL2 (at %s)" % p.global_position)
	await _run([["run", 2590], ["attack", 3]])
	check(Game.is_collected("rc_signal_box"), "three hits break the signal box wall")
	await _run([["run", 2660], ["wait", 120]])
	check(Game.is_collected("sb_rc_signal"), "the stash inside is collected")
	# Both burst into pickups; most land in reach inside the box.
	check(Game.state.total_scrap() - scrap0 >= 60, "wall 30 + stash 60 scrap, got %d" % (Game.state.total_scrap() - scrap0))


func test_rainline_reentry_no_pursuer() -> void:
	Game.set_flag("chase_rainline_done")
	var w := _rainline_watch()
	await _enter(_rainline_path(), &"from_security")
	await _run([["run", 700]])
	_rainline_unwatch(w)
	check(_rainline_pursuers().is_empty(), "no Sweeper once the chase is done")
	check(_rainline_director().state == ChaseDirector.State.DONE, "director DONE on re-entry")
	check((w["started"] as Array).is_empty(), "crossing ChaseStart after the chase does nothing")
	check(not (SceneRouter.current_room as Room).pit_override.is_valid(), "pits are ordinary again")


func test_rainline_from_bell_idle() -> void:
	await _enter(_rainline_path(), &"from_bell")
	var w := _rainline_watch()
	var d := _rainline_director()
	var moved: Array = [false]
	var watch := func() -> void:
		if is_instance_valid(d) and d.pursuer_progress != 0.0:
			moved[0] = true
	get_tree().physics_frame.connect(watch)
	var ok := await _run(_rainline_west_steps())
	get_tree().physics_frame.disconnect(watch)
	check(ok, "the westbound walk reaches the Security door")
	check((w["started"] as Array).is_empty(), "walking west never arms the chase")
	check((w["caught"] as Array).is_empty(), "no catch westbound")
	check(not Game.has_flag("chase_rainline_done"), "crossing end_area while idle does not set the flag")
	check(not moved[0], "the parked Sweeper never moves")
	await _run([["run", 460]])
	_rainline_unwatch(w)
	check((w["started"] as Array).size() == 1, "walking east from 20 past 440 arms the chase once")


func test_rainline_old_save_via_bell_lift() -> void:
	# A v3-style save: full kit, Dash, Krail down, the Bell lift running, Orr
	# met, and no chase flag. It walks the line backwards from the Bell Tower.
	Game.set_ability(&"dash", true)
	for f in ["warden_krail_defeated", "shortcut_bell_lift", "met_orr"]:
		Game.set_flag(f)
	await _enter(LL + "BellTower.tscn", &"from_rainline")
	var w := _rainline_watch()
	var ok := await _run([["exit", -1]])
	check(ok and SceneRouter.current_room_path == _rainline_path(), "the Bell Tower's bottom-left door leads to the Rainline")
	_pacify()
	var p := (SceneRouter.current_room as Room).player
	check_near(p.global_position.x, 4100.0, 4.0, "arrives at from_bell")
	ok = ok and await _run(_rainline_west_steps() + [["exit", -1]])
	_rainline_unwatch(w)
	check((w["caught"] as Array).is_empty() and (w["started"] as Array).is_empty(), "the Sweeper never wakes westbound")
	check(not Game.has_flag("chase_rainline_done"), "the flag stays unset")
	check(SceneRouter.current_room_path == LL + "SecurityStation.tscn", "reaches the Security Station")
	var room := SceneRouter.current_room as Room
	if room != null:
		check(room.player.combat.health == 5, "no pip lost on the way, hp %d" % room.player.combat.health)
		check(room.player.global_position.distance_to(Vector2(1200, -384)) < 40.0, "arrives at from_rainline, at %s" % room.player.global_position)


# --- Smuggler Route (optional loop, D-075): Power Block basement -> den -> Stack.
const SR := "res://world/rooms/lowlight/SmugglerRoute.tscn"
## East entry to P2's east end: breaker (shoot up), shutter run, W1, pipe slot.
const SR_TO_P2 := [["run", 2200], ["shoot", 1, "up"], ["run", 1826], ["runjump", 1822, 1700], ["run", 1656], ["slide", 1570]]
## P2 to the Sill: W2 slide-jump over the culvert, W3 run-jump.
const SR_TO_SILL := [["slidejump", 1464, 1340], ["runjump", 1202, 1090]]
## Sill up the floodgate steps to the DashLedge; the top step and the ledge
## are one-ways stacked over the -144 step, jumped up through.
const SR_TO_LEDGE := [["run", 1076], ["jump", 1076], ["jump", 1020], ["jump", 1076], ["jump", 1084], ["jump", 1084]]


## East to west, pacified: the high breaker opens the shutter, which latches
## once crossed; the floodway, the floodgate slot, then the den lever unbolts
## the hatch and the west door leads to the Stack.
func test_smuggler_route() -> void:
	await _enter(SR, &"from_power")
	var steps := SR_TO_P2 + SR_TO_SILL + [["run", 766], ["slide", 670], ["run", 40], ["interact"], ["run", -20]]
	if not await _run(steps):
		return
	check(Game.has_flag("sr_shutter_latched"), "crossing the open shutter should latch it")
	check(Game.has_flag("shortcut_smuggler_route"), "the den lever should unbolt the hatch")
	var hatch := SceneRouter.current_room.find_child("Hatch", true, false) as Gate
	check(hatch != null and not hatch.closed, "the Hatch should be open")
	_assert_exit(1, LL + "PowerBlock.tscn", &"from_smuggler")
	_assert_exit(-1, LL + "ApartmentStack.tscn", &"from_smuggler", "shortcut_smuggler_route")
	if await _run([["exit", -1]]):
		check(SceneRouter.current_room.name == "ApartmentStack", "the hatch should lead to the Stack (in %s)" % SceneRouter.current_room.name)


## The shrine is Dash-only: with Dash, a dash-jump from the DashLedge
## (reached by the floodgate steps) drops onto the shrine 64 px below and
## collects the shard.
func test_smuggler_dash_shard() -> void:
	Game.set_ability(&"dash", true)
	await _enter(SR, &"from_power")
	if await _run(SR_TO_P2 + SR_TO_SILL + SR_TO_LEDGE + [["dashjump", 1060, 759]]):
		check(Game.is_collected("cs_smuggler_dash"), "a dash-jump from the ledge should reach the shard")


## Negative sweep (plan risk "Dash-gate integrity"): without Dash, a
## dodge-jump plus an air dodge on EVERY airborne frame the dodge cooldown
## allows, from the first (~18 frames after the ground dodge ends) to the
## last before landing, must neither collect the shard nor land on the far
## platform (`far`: its top edge, x..x+width at y; a landing there that just
## misses the pickup would still let Rook walk onto the shard).
## Each attempt restarts at `edge_start` on the take-off surface. Returns the
## leaks found; the caller decides whether they fail.
func _smuggler_sweep(room_path: String, entry: StringName, edge_start: Vector2, edge: float, target: float, shard: String, far: Rect2) -> PackedStringArray:
	await _enter(room_path, entry)
	check(not Game.abilities.dash, "the sweep runs without Dash")
	var leaks := PackedStringArray()
	var p := bot.player
	# [take-off frame, air-dodge airborne frame, first landing, air-dodge position]
	var seen := [-1, -1, Vector2.INF, Vector2.INF]
	var on_jump := func(_kind: StringName) -> void:
		seen[0] = Engine.get_physics_frames()
	var on_state := func(_from: StringName, to: StringName) -> void:
		if to == &"dodge" and seen[0] >= 0 and not p.is_on_floor() and seen[1] < 0:
			seen[1] = Engine.get_physics_frames() - int(seen[0])
			seen[3] = p.global_position
	var on_land := func(_speed: float) -> void:
		if seen[1] >= 0 and seen[2] == Vector2.INF:
			seen[2] = p.global_position
	p.jumped.connect(on_jump)
	EventBus.player_state_changed.connect(on_state)
	p.landed.connect(on_land)
	var d := 1  # 0 would be a plain dodge-jump (no air dodge)
	var tries := 0
	var covered := false
	while tries < 90:
		tries += 1
		p.respawn(edge_start, int(signf(target - edge_start.x)))
		await physics_frames(6)
		seen[0] = -1
		seen[1] = -1
		seen[2] = Vector2.INF
		seen[3] = Vector2.INF
		await bot.run([["dodgejump_airdodge", edge, target, d]])
		bot.input.move_x = 0  # no walking on after the landing
		await physics_frames(20)
		if int(seen[1]) < 0:
			covered = true  # landed before an air dodge could fire
			break
		var land: Vector2 = seen[2]
		var on_far := land != Vector2.INF and absf(land.y - far.position.y) < 2.0 \
				and land.x > far.position.x - 7.0 and land.x < far.end.x + 7.0
		if on_far or Game.is_collected(shard):
			leaks.append("air dodge on airborne frame %d from %s: landed at %s%s" % [seen[1], edge_start, land, ", collected" if Game.is_collected(shard) else ""])
			break
		# An air dodge zeroes the fall but never lifts: once it starts below
		# the far top, every later frame does too, so the window is covered.
		if (seen[3] as Vector2).y > far.position.y + 1.0:
			covered = true
			break
		# d below the cooldown floor all fire on its first frame: jump there.
		d = maxi(d + 1, int(seen[1]) - 2)
	check(covered or not leaks.is_empty(), "%s from %s: the sweep stopped before the last air-dodge frame" % [room_path.get_file(), edge_start])
	check(tries > 12, "%s from %s: only %d air-dodge frames swept, the sweep proves little" % [room_path.get_file(), edge_start, tries])
	p.jumped.disconnect(on_jump)
	EventBus.player_state_changed.disconnect(on_state)
	p.landed.disconnect(on_land)
	return leaks


func test_smuggler_dash_shard_negative_sweep() -> void:
	# The shrine (740..778, top -176) from the DashLedge (1060..1104 at -240,
	# 282 px, 64 px above) and the top step (1064..1104 at -192, 286 px, 16 px
	# above). The -144 step (270 px, 32 px below) is out of reach by ~50 px.
	# Each take-off is swept at the lip and 8 px past it (a late, coyote-time
	# jump). A take-off 16-20 px past the lip (the whole coyote window, then a
	# frame-exact air dodge) can still land: that is the mastery residue the
	# map marker admits ("(mostly)", KNOWN_ISSUES K-48).
	var shrine := Rect2(740, -176, 38, 16)
	for from in [[Vector2(1100, -240), 1060.0], [Vector2(1100, -192), 1064.0]]:
		for late in [0.0, 8.0]:
			var leaks := await _smuggler_sweep(SR, &"from_power", from[0], from[1] - late, 759, "cs_smuggler_dash", shrine)
			check(leaks.is_empty(), "the Smuggler Dash shrine leaks without Dash (take-off %d px past the lip): %s" % [late, ", ".join(leaks)])


## The same sweep on the Flooded Alley's Dash shard. The original 220 px gap
## at one height leaked (an air dodge on airborne frame 29 landed on the far
## block); D2b rebuilt it on the Smuggler Route's principle, a drop: a one-way
## take-off (100..160 at -144) 290 px from the DashShelf (450..506), 64 px
## below. The -96 block under the take-off (edge 160) is swept too, 16 px
## above the shelf. Each take-off is swept at the lip and up to 20 px past it
## (the whole coyote window): at 282 px a take-off 16 px late still landed on
## the shelf's lip, at 290 px none does. A dash-jump from the lip crosses the
## shelf's top at x ~455 (test_slice_routes::test_dash_shard_needs_dash).
## Air lights: test_alley_dash_air_light_negative_sweep.
func test_smuggler_alley_dash_negative_sweep() -> void:
	var alley := LL + "FloodedAlley.tscn"
	var shelf := Rect2(450, -80, 56, 16)
	for from in [Vector2(135, -144), Vector2(125, -96)]:
		for late in [0.0, 8.0, 16.0, 20.0]:
			Game.new_game()  # a clean profile: no shard collected by an earlier attempt
			var leaks := await _smuggler_sweep(alley, &"from_relay", from, 158.0 + late, 468, "cs_alley_dash", shelf)
			check(leaks.is_empty(), "the Flooded Alley Dash gate leaks without Dash (from %s, %d px past the lip): %s" % [from, late, ", ".join(leaks)])


## The loft cache takes heavy attacks only: light swings bounce off, two
## heavies break it, and the bundle behind it is reachable.
func test_smuggler_den_cache() -> void:
	await _enter(SR, &"from_stack")
	var wall := SceneRouter.current_room.find_child("Breakable*", true, false) as BreakableWall
	check(wall != null and wall.persist_id == "sr_den_cache", "the loft cache wall should be in the room")
	# Count the swings that reached the wall, so "light does nothing" is not
	# just "light was out of range".
	var blocked := [0]
	var on_hit := func(_hit: HitInfo, result: int, target: Node2D) -> void:
		if target == wall and result == CombatResult.BLOCKED:
			blocked[0] += 1
	bot.player.combat.hit_landed.connect(on_hit)
	var ok := await _run([["run", 348], ["jump", 348], ["jump", 288], ["jump", 200], ["run", 128], ["attack", 3]])
	bot.player.combat.hit_landed.disconnect(on_hit)
	if not ok:
		return
	check(int(blocked[0]) >= 3, "all three light swings should reach the wall and bounce off (%d did)" % blocked[0])
	check(not Game.is_collected("sr_den_cache"), "light attacks must not break the heavy wall")
	if await _run([["heavy", 2], ["wait", 20], ["run", 60]]):
		check(Game.is_collected("sr_den_cache"), "two heavy attacks should break the cache wall")
		check(Game.is_collected("sb_sr_cache"), "the cache bundle should be reachable")


## A W2 miss drops onto the culvert: no pip, no climbing straight back to P3
## or P2, and the only way out is the one-way under P2's east end.
func test_smuggler_culvert_catch() -> void:
	await _enter(SR, &"from_power")
	if not await _run(SR_TO_P2 + [["run", 1470], ["run", 1420], ["wait", 40]]):
		return
	var p := bot.player
	var hp := p.combat.health
	check(p.is_on_floor() and absf(p.global_position.y - 72.0) < 2.0, "a W2 miss should land on the culvert (at %s)" % p.global_position)
	await bot.run([["run", 1400], ["jump", 1400], ["wait", 20]])
	check(p.global_position.y > 60.0, "the culvert must not climb straight back out (at %s)" % p.global_position)
	if await _run([["run", 1742], ["jump", 1742], ["jump", 1700]]):
		check(p.global_position.y < 1.0 and p.global_position.x > 1464.0 and p.global_position.x < 1724.0, "the culvert should lead back up to P2's east end (at %s)" % p.global_position)
	# A death would respawn a new Rook and free `p`: check that before reading it.
	var same := is_instance_valid(p) and bot.player == p
	check(same, "the culvert catch must not kill Rook")
	if same:
		check(p.combat.health == hp, "the culvert catch must not cost a pip")


## Iko's first meeting in the den: talking sets met_iko and opens her shop,
## then the den Iko is gone (she moves to the Relay, NPC.present_when).
func test_smuggler_iko_intro_and_hide() -> void:
	await _enter(SR, &"from_stack")
	var iko := SceneRouter.current_room.find_child("NPC_iko", true, false) as NPC
	check(iko != null and iko.is_present(), "Iko should be in the den before the first meeting")
	var menus: Array = []
	var on_menu := func(id: StringName) -> void:
		menus.append(id)
	EventBus.menu_requested.connect(on_menu)
	if await _run([["run", 150], ["interact"]]):
		await _close_dialogue()
	EventBus.menu_requested.disconnect(on_menu)
	check(Game.has_flag("met_iko"), "the first talk should set met_iko")
	check(menus.has(&"shop_iko"), "the first talk should open Iko's shop (menus %s)" % str(menus))
	check(iko != null and not iko.is_present() and not iko.visible, "the den Iko should hide after the meeting")


# --- D7b: the re-plumbed existing rooms (tools/roomgen/lowlight.py, D2b) ---
const WARDEN_TOWER := "res://world/rooms/lowlight/WardenTower.tscn"
const STACK := "res://world/rooms/lowlight/ApartmentStack.tscn"
const RELAY := "res://world/rooms/lowlight/Relay.tscn"
const WT_CLAMP_HINT := "Breakers live. Drop the clamp on him."


## Krail's boss test in the real Warden Tower: a retry (intro_seen), Krail
## held under the clamp, and Rook trips the west breaker the way a player
## does, jump + air light from under the box (36..52, top -96). The clamp
## warns 1.0 s, drops 0.15 s and staggers Krail for its 30; the teaching line
## shows exactly once. Nothing drops before the breaker is struck.
func test_warden_tower_clamp_in_room() -> void:
	Game.set_flag("warden_krail_intro_seen")
	await _enter(WARDEN_TOWER, &"from_bell")
	var room := SceneRouter.current_room as Room
	var c := room.find_child("Clamp_wt_clamp", true, false) as GridClamp
	var k := room.find_child("WardenKrail*", true, false) as Enemy
	var bw := room.find_child("Breaker_wt_grid_w", true, false) as Breaker
	check(c != null and k != null and bw != null, "WardenTower needs Clamp_wt_clamp, Krail and Breaker_wt_grid_w")
	if c == null or k == null or bw == null:
		return
	check(c.arm_hint == WT_CLAMP_HINT and c.circuits.size() == 1 and c.circuits[0] == &"wt_clamp", "the clamp's line and circuit")
	var hints: Array = []
	var drops: Array = []
	var staggered_at: Array = []
	var on_hint := func(text: String, _seconds: float) -> void:
		if text == WT_CLAMP_HINT:
			hints.append(Engine.get_physics_frames())
	var on_drop := func(id: String, st: bool) -> void:
		drops.append([id, st])
	EventBus.hint_requested.connect(on_hint)
	EventBus.clamp_dropped.connect(on_drop)
	var p := bot.player
	var input := bot.input
	# Into the arena under the west box: the fight starts and arms the clamp.
	p.teleport(Vector2(44, 0))
	p.facing = 1
	await physics_frames(3)
	check(c.state == GridClamp.State.READY, "the fight start arms the clamp (%s)" % c.state_name())
	var hp := k.health
	# Krail is held under the clamp's footprint (x 176..240) until the slam.
	var pin := func() -> void:
		if is_instance_valid(k) and not k.is_dead():
			k.global_position = Vector2(208, 0)
			k.velocity = Vector2.ZERO
			if k.ai == Enemy.AI.STAGGER and staggered_at.is_empty():
				staggered_at.append(Engine.get_physics_frames())
	pin.call()
	# Idle for 1.5 s with Krail under the footprint: nothing drops on its own.
	for f in 90:
		await physics_frames(1)
		pin.call()
	check(drops.is_empty() and c.state == GridClamp.State.READY, "the clamp stays idle until a breaker is hit (%s)" % c.state_name())
	# D2b: the boxes are high breakers (jump + air light). No grounded swing
	# made from either arena one-way's nearest standing point reaches one,
	# with the Pulse Blade or the Split Katars (the melee weapons; guns are
	# meant to reach high breakers straight up, bible D-071).
	var be := room.find_child("Breaker_wt_grid_e", true, false) as Breaker
	var ways: Array = []
	for n in room.find_children("OneWay*", "GrayboxBlock", true, false):
		ways.append(n)
	check(be != null and ways.size() == 2, "WardenTower needs Breaker_wt_grid_e and two arena one-ways")
	if be != null and ways.size() == 2:
		for weapon in ["split_katars", "pulse_blade"]:  # the blade last: the jump below uses it
			p.combat.set_loadout(Game.catalog.weapon(weapon), null)
			for w in ways:
				var ow := w as GrayboxBlock
				var west := ow.global_position.x < 208.0
				var stand_x := ow.global_position.x - 5.0 if west else ow.global_position.x + ow.size.x + 5.0
				for kind in ["light", "heavy", "launcher"]:
					var before: int = bw.trips + be.trips
					p.teleport(Vector2(stand_x, ow.global_position.y - 1.0))
					await physics_frames(4)
					pin.call()
					p.facing = -1 if west else 1
					check(p.is_on_floor() and absf(p.global_position.y - ow.global_position.y) < 1.5,
						"Rook stands on %s at x %.0f (at %s)" % [ow.name, stand_x, p.global_position])
					input.up_held = kind == "launcher"
					for swing in (4 if kind == "light" else 1):
						if kind == "light":
							input.press_light()
						else:
							input.press_heavy()
						for f in 18:
							await physics_frames(1)
							pin.call()
					for f in 30:
						await physics_frames(1)
						pin.call()
					input.up_held = false
					check(bw.trips + be.trips == before,
						"a grounded %s %s from %s (x %.0f) must not reach a breaker (w %d, e %d)" % [weapon, kind, ow.name, stand_x, bw.trips, be.trips])
		p.teleport(Vector2(44, 0))
		p.facing = 1
		await physics_frames(20)
		pin.call()
	check(drops.is_empty() and c.state == GridClamp.State.READY, "still idle after the one-way swings (%s)" % c.state_name())
	# The Dash module lands on the floor under the clamp, not where Krail dies.
	var arena := room.find_child("BossArena", true, false)
	check(arena != null and arena.get("reward_position") == Vector2(208, 0),
		"WardenTower BossArena reward_position is (208, 0): %s" % (arena.get("reward_position") if arena != null else "missing"))
	input.press_jump()
	for f in 40:
		await physics_frames(1)
		pin.call()
		if p.global_position.y <= -40.0 and p.velocity.y < 0.0:
			break
	input.press_light()
	var tripped_at := -1
	for f in 40:
		await physics_frames(1)
		pin.call()
		if tripped_at < 0 and bw.trips > 0:
			tripped_at = Engine.get_physics_frames()
	input.release_jump()
	check(tripped_at >= 0, "jump + air light from x 44 should trip wt_grid_w (feet near %.0f)" % p.global_position.y)
	if tripped_at < 0:
		EventBus.hint_requested.disconnect(on_hint)
		EventBus.clamp_dropped.disconnect(on_drop)
		return
	var window := int(ceil((c.timing.warn + c.timing.drop + 0.1) * 60.0))
	while Engine.get_physics_frames() - tripped_at < window and staggered_at.is_empty():
		await physics_frames(1)
		pin.call()
	check(not staggered_at.is_empty(), "Krail should be staggered within %d frames of the trip (ai %s)" % [window, Enemy.AI.keys()[k.ai]])
	check_near(hp - k.health, 30.0, 0.01, "Krail takes the clamp's 30")
	check(drops == [["wt_clamp", true]], "clamp_dropped(wt_clamp, staggered): %s" % str(drops))
	# The line fired once (Krail stood under it after hint_min) and never again.
	await physics_frames(int(c.timing.hint_delay * 60.0))
	check(hints.size() == 1, "the teaching line shows exactly once: %s" % str(hints))
	check(Game.has_flag("hint_wt_clamp"), "the line's hint flag is set")
	EventBus.hint_requested.disconnect(on_hint)
	EventBus.clamp_dropped.disconnect(on_drop)


## The Stack's ground-floor hatch is bolted from the tunnel side: without
## shortcut_smuggler_route the HatchGate is shut and even standing in the
## exit does nothing; with it, the door works both ways.
func test_stack_hatch_both_ways() -> void:
	await _enter(STACK, &"from_market")
	var room := SceneRouter.current_room as Room
	var gate := room.find_child("HatchGate", true, false) as Gate
	check(gate != null and gate.closed, "the HatchGate should be shut without the flag")
	_assert_exit(1, LL + "SmugglerRoute.tscn", &"from_stack", "shortcut_smuggler_route")
	var p := bot.player
	p.teleport(Vector2(580, 0))
	await physics_frames(3)
	await bot.run([["exit", 1]])
	check(SceneRouter.current_room == room, "the bolted hatch must not open (in %s)" % SceneRouter.current_room.name)
	check(p.global_position.x < 608.0, "the HatchGate blocks Rook (x %.0f)" % p.global_position.x)
	# Standing inside the exit rect itself (past the gate) still does nothing.
	p.teleport(Vector2(632, 0))
	await physics_frames(20)
	check(SceneRouter.current_room == room, "the hatch exit needs shortcut_smuggler_route")
	check(Game.has_flag("hint_stack_hatch"), "the bolted hatch says so ('Bolted from the other side.')")
	# Unbolted (the den lever): Stack -> Smuggler Route -> Stack. Arriving
	# through the hatch (inside the hint box) must not claim it is bolted.
	Game.set_flag("shortcut_smuggler_route")
	Game.set_flag("hint_stack_hatch", false)
	await _enter(STACK, &"from_smuggler")
	check(not Game.has_flag("hint_stack_hatch"), "no 'bolted' line once the hatch is open")
	gate = SceneRouter.current_room.find_child("HatchGate", true, false) as Gate
	check(gate != null and not gate.closed, "the HatchGate opens with the flag")
	if not await _run([["exit", 1]]):
		return
	check(SceneRouter.current_room.name == "SmugglerRoute", "the hatch leads to the Smuggler Route (in %s)" % SceneRouter.current_room.name)
	check(bot.player.global_position.distance_to(Vector2(20, 0)) < 24.0, "arrives at from_stack (at %s)" % bot.player.global_position)
	await physics_frames(10)
	if not await _run([["exit", -1]]):
		return
	check(SceneRouter.current_room.name == "ApartmentStack", "and back to the Stack (in %s)" % SceneRouter.current_room.name)
	check(bot.player.global_position.distance_to(Vector2(580, 0)) < 24.0, "arrives at from_smuggler (at %s)" % bot.player.global_position)


## Iko moves to the Relay after the den meeting (present_when flag:met_iko):
## before it she is hidden, silent and off the map; after it she is there,
## opens shop_iko, and the den Iko is gone from the room and the map.
func test_relay_iko_presence() -> void:
	await _enter(RELAY, &"start")
	var iko := SceneRouter.current_room.find_child("NPC_iko", true, false) as NPC
	check(iko != null, "the Relay should place Iko")
	if iko == null:
		return
	check(not iko.is_present() and not iko.visible and not iko.can_interact(bot.player), "no Relay Iko before met_iko")
	check(not WorldMapIndex.npc_present(_iko_pin(RELAY)), "no Relay Iko map pin before met_iko")
	var menus: Array = []
	var on_menu := func(id: StringName) -> void:
		menus.append(id)
	EventBus.menu_requested.connect(on_menu)
	await _run([["run", 580], ["interact"]])
	check(not dialogue_box.is_open() and menus.is_empty(), "nothing to talk to at x 580 before met_iko")
	Game.set_flag("met_iko")
	await physics_frames(2)
	check(iko.is_present() and iko.visible, "Iko is at the Relay after met_iko")
	check(WorldMapIndex.npc_present(_iko_pin(RELAY)), "the Relay Iko has a map pin after met_iko")
	if await _run([["interact"]]):
		await _close_dialogue()
	EventBus.menu_requested.disconnect(on_menu)
	check(menus.has(&"shop_iko"), "talking to the Relay Iko opens shop_iko (menus %s)" % str(menus))
	check(not WorldMapIndex.npc_present(_iko_pin(SR)), "the den Iko has no map pin after met_iko")
	await _enter(SR, &"from_stack")
	var den := SceneRouter.current_room.find_child("NPC_iko", true, false) as NPC
	check(den != null and not den.is_present() and not den.visible, "the den Iko is hidden after met_iko")


## The map index entry of Iko in a room ({} if the room has none).
func _iko_pin(room_path: String) -> Dictionary:
	for n: Dictionary in WorldMapIndex.room_info(room_path)["npcs"]:
		if n["id"] == "iko":
			return n
	check(false, "%s has no Iko in the map index" % room_path.get_file())
	return {}


func test_full_lowlight_chain() -> void:
	print("PENDING: D6")


## The alley DashShelf's top edge (x..x+width at y), from the room.
func _flooded_alley_shelf() -> Rect2:
	var b := SceneRouter.current_room.find_child("DashShelf", true, false) as GrayboxBlock
	check(b != null, "FloodedAlley should have a DashShelf")
	return Rect2(b.position, b.size) if b != null else Rect2()


## One no-Dash attempt at the alley shelf: from `start` (holding toward
## `dir`), optionally dodge `dodge_at` px before `jump_x` and jump when the
## centre crosses it (jump_x NAN: jump at once, from the floor); then an air
## light on frame `d` after the jump press (0 = the same frame) and every `g`
## frames after it until landing (every air light, not just the three
## hangs); optionally an air dodge from airborne frame `air_dodge`. Returns
## "" or what leaked: the shard collected, or a landing at shelf height.
func _flooded_alley_chain(start: Vector2, dir: int, jump_x: float, dodge_at: float, d: int, g: int, air_dodge: int, shelf: Rect2) -> String:
	var p := bot.player
	var inp := bot.input
	p.respawn(start, dir)
	inp.move_x = 0
	await physics_frames(3)
	inp.move_x = dir
	if not is_nan(jump_x):
		var dodged := -1
		for f in 120:
			if dodge_at > 0.0 and dodged < 0 and (jump_x - p.global_position.x) * dir < dodge_at:
				inp.press_dodge()
				dodged = f
			await physics_frames(1)
			if (p.global_position.x - jump_x) * dir >= 0.0 and (dodged < 0 or f - dodged >= 4):
				break
	inp.press_jump()
	var leak := ""
	var had_shard := Game.is_collected("cs_alley_dash")  # an earlier leak's pickup is gone
	for f in 360:
		if f >= d and (f - d) % g == 0:
			inp.press_light()
		if air_dodge > 0 and f >= air_dodge and f < air_dodge + 12:
			inp.press_dodge()
		await physics_frames(1)
		if not had_shard and Game.is_collected("cs_alley_dash"):
			leak = "collected"
		elif f > 3 and p.is_on_floor() and p.global_position.y < shelf.position.y + 2.0:
			leak = "landed at %s" % p.global_position.round()
		if leak != "" or (f > 3 and p.is_on_floor()):
			break
	inp.release_jump()
	inp.move_x = 0
	return leak


## Dash-gate integrity against air lights (M7 D2b review). Air lights used
## to hang on every swing (three per airtime), the 4th+ swing still floated,
## and a light on the jump frame was a super jump: a floor jump + chained
## lights peaked ~-85 and landed on this -80 shelf, and a lip jump + lights
## (+ an air dodge) glided ~340 px. Hangs now come only from a connecting
## swing (AttackData.air_velocity_on_hit). Without Dash, with the Pulse Blade
## and the Split Katars (Mara sells them long before Krail): (1) from the
## floor beside the shelf on both sides, holding toward it, jump and chain
## light presses from every start delay 0..30 frames (0 = the jump frame) at
## every gap 6..14 frames until landing; (2) from the take-off lip (a
## dodge-jump at the lip and 12 px late), chain lights at delays 0..30 (every
## 3rd) and gaps 6/10/14, with and without an air dodge. Nothing may collect
## the shard or land at shelf height.
func test_alley_dash_air_light_negative_sweep() -> void:
	await _enter(LL + "FloodedAlley.tscn", &"from_relay")
	check(not Game.abilities.dash, "the sweep runs without Dash")
	var shelf := _flooded_alley_shelf()
	var leaks := PackedStringArray()
	var tries := 0
	for w in ["pulse_blade", "split_katars"]:
		bot.player.combat.set_loadout(Game.catalog.weapon(w), null)
		for side in [[Vector2(shelf.position.x - 30.0, 0), 1], [Vector2(shelf.end.x + 30.0, 0), -1]]:
			for d in range(0, 31):
				for g in range(6, 15):
					tries += 1
					var leak := await _flooded_alley_chain(side[0], side[1], NAN, 0.0, d, g, 0, shelf)
					if leak != "":
						leaks.append("%s floor %s d%d g%d: %s" % [w, side[0], d, g, leak])
		for take_off in [160.0, 172.0]:
			for d in range(0, 31, 3):
				for g in [6, 10, 14]:
					for ad in [0, 30]:
						tries += 1
						var leak := await _flooded_alley_chain(Vector2(110, -144), 1, take_off, 22.0, d, g, ad, shelf)
						if leak != "":
							leaks.append("%s lip %d d%d g%d ad%d: %s" % [w, take_off, d, g, ad, leak])
		if leaks.size() > 12:
			break
	check(tries > 1000 or not leaks.is_empty(), "only %d attempts swept" % tries)
	check(leaks.is_empty(), "the Flooded Alley Dash shard leaks to air lights without Dash: %s" % ", ".join(leaks))
