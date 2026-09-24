extends RedlineTestCase
## M7 Undercity route tests (bible §34 traversal validation, §42 onboarding).
## Each room task proves its room with RouteBot from the forward campaign
## state and stops at its own exit (asserting the door contract); the full
## chain through all seven rooms is D6's test_full_undercity_walk.
##
## Everything above the room-tests marker is the shared harness. It is
## frozen after the world skeleton (D0): a room that needs another helper
## defines a private one prefixed with its room name in its own section.
## Kit per room (_campaign arguments): Wake, MedicalRuin (); MaintenanceShaft,
## FirstPursuit, BrokenLift (true); CollectorBay (true, false, true);
## EscapeTunnel (true, true, true).

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


## Harness self-test: the campaign kit, an entry, the exit contract and a
## door walk, on the Wake stub (any Wake geometry keeps from_medical on a
## floor next to the east door).
func test_harness_campaign_enter_and_exit() -> void:
	_campaign(true, false, true)
	check(Game.onboarding.enforce and Game.campaign_start_room() == WAKE, "campaign config not installed")
	check(Game.state.melee_weapon == "pulse_blade" and Game.has_flag("got_pulse_blade"), "blade kit not applied")
	check(Game.state.ranged_weapon == "" and not Game.has_flag("got_service_pistol"), "pistol must stay unowned")
	check(not Game.has_flag("core_hud_hidden"), "core_shown should clear core_hud_hidden")
	await _enter(WAKE, &"from_medical")
	check(Game.state.last_entry_id == "from_medical", "pre-Anchor respawn should record the entry")
	_assert_exit(1, UC + "MedicalRuin.tscn", &"from_wake")
	if await _run([["exit", 1]]):
		check(SceneRouter.current_room.name == "MedicalRuin", "the east door leads to the Medical Ruin")


func test_harness_close_dialogue() -> void:
	_campaign()
	check(Game.state.owned_weapons.is_empty() and Game.has_flag("core_hud_hidden"), "the bare campaign starts unarmed, Core hidden")
	await _enter(WAKE, &"start")
	var orr: NpcProfile = load("res://data/npcs/orr.tres")
	EventBus.dialogue_requested.emit(orr.rules[orr.rules.size() - 1].dialogue, "Orr")
	check(dialogue_box.is_open() and get_tree().paused, "the harness box should open and pause")
	await _close_dialogue()
	check(not get_tree().paused, "closing should unpause")


# --- room tests (one owner per function) ---
func test_wake_route() -> void:
	print("PENDING: Wake")


## Bible §42 0-5 min: the rack arms an unarmed Rook, the first chain kills
## the dormant orderly, the shelf is reachable with plain jumps, and the
## live Needles (pacified here: geometry only) sit on floor, pit and deck.
func test_medical_ruin_route() -> void:
	_campaign()
	check(Game.state.melee_weapon == "", "the Medical Ruin kit is the bare, unarmed campaign")
	await _enter(UC + "MedicalRuin.tscn", &"from_wake")
	var dormant := _medical_ruin_dormant()
	check(dormant != null, "no dormant Needle in the room")
	if dormant == null:
		return
	if not await _run([["run", 140], ["run", 236], ["attack", 3], ["run", 700], ["run", 850], ["jump", 910],
			["run", 1028], ["jump", 1028], ["jump", 1110], ["run", 1140], ["run", 1340], ["attack", 3],
			["run", 1690], ["jump", 1720], ["attack", 3], ["run", 1956]]):
		return
	check(Game.has_flag("got_pulse_blade") and Game.state.owned_weapons.has("pulse_blade"), "the rack should grant the Pulse Blade")
	check(Game.state.melee_weapon == "pulse_blade", "the Pulse Blade should be equipped from the rack")
	check(not is_instance_valid(dormant) or dormant.is_dead(), "the first chain should kill the dormant Needle")
	check(Game.is_collected("sb_uc_med_shelf"), "the shelf Scrap should be reachable with plain jumps")
	_assert_exit(1, UC + "MaintenanceShaft.tscn", &"from_medical")
	if await _run([["exit", 1]]):
		check(SceneRouter.current_room.name == "MaintenanceShaft", "the east door leads to the Maintenance Shaft")


## Unarmed swings do nothing: only the rack makes the practice target die.
## Unreachable in room order (the rack's trigger cannot be jumped), so Rook
## is teleported past it.
func test_medical_ruin_attack_before_rack() -> void:
	_campaign()
	await _enter(UC + "MedicalRuin.tscn", &"from_wake")
	var dormant := _medical_ruin_dormant()
	check(dormant != null, "no dormant Needle in the room")
	if dormant == null:
		return
	var player := (SceneRouter.current_room as Room).player
	player.global_position = Vector2(236, -1)
	player.velocity = Vector2.ZERO
	await physics_frames(10)
	if not await _run([["run", 236], ["attack", 3]]):
		return
	check(not Game.has_flag("got_pulse_blade") and Game.state.melee_weapon == "", "Rook should still be unarmed")
	check(is_instance_valid(dormant) and not dormant.is_dead() and dormant.health == dormant.data.max_health,
			"unarmed attacks must leave the dormant Needle at full HP")


## The one Enemy authored with its AI off (the orderly at x 270).
func _medical_ruin_dormant() -> Enemy:
	for e in SceneRouter.current_room.find_children("*", "Enemy", true, false):
		if not (e as Enemy).ai_enabled:
			return e as Enemy
	return null


func test_maintenance_shaft_route() -> void:
	print("PENDING: MaintenanceShaft")


func test_first_pursuit_route() -> void:
	print("PENDING: FirstPursuit")


func test_broken_lift_route() -> void:
	print("PENDING: BrokenLift")


func test_collector_bay_post_win_route() -> void:
	print("PENDING: CollectorBay")


func test_escape_tunnel_route() -> void:
	print("PENDING: EscapeTunnel")


func test_full_undercity_walk() -> void:
	print("PENDING: D6")
