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


## Maintenance Shaft critical route up to the closet: climbs A and B, breaks
## the closet wall with the blade and walks over its two items. Shared by the
## route and the secret test, so an upper-climb regression is reported apart.
const SHAFT_TO_CLOSET := [
	["run", 530], ["jump", 530], ["jump", 450], ["jump", 530], ["jump", 450], ["jump", 370],
	["run", 100], ["jump", 100], ["jump", 180], ["jump", 100], ["jump", 180], ["jump", 262],
	["run", 528], ["attack", 3], ["run", 604],
]
## From the closet up climb C to the exit ledge. The last hop aims at 488
## (the draft said 520): a 48 px rise lands as soon as Rook clears the ledge
## lip at 440, and RouteBot only steers 4 frames after landing.
const SHAFT_CLOSET_TO_EXIT := [
	["run", 488], ["jump", 488], ["jump", 408], ["jump", 488], ["jump", 408], ["jump", 488], ["run", 600],
]


func test_maintenance_shaft_route() -> void:
	_campaign(true)
	await _enter(UC + "MaintenanceShaft.tscn", &"from_medical")
	_assert_exit(-1, UC + "MedicalRuin.tscn", &"from_shaft")
	if not await _run(SHAFT_TO_CLOSET + SHAFT_CLOSET_TO_EXIT):
		return
	check(Game.is_collected("uc_shaft_closet"), "the closet wall should be broken")
	check(Game.is_collected("sb_uc_shaft_closet") and Game.is_collected("mf_undercity_01"), "the closet items should be collected")
	check_near(bot.player.global_position.y, -720.0, 2.0, "Rook should stand on the exit ledge")
	check(bot.player.is_on_floor(), "Rook should be on the exit ledge floor")
	_assert_exit(1, UC + "FirstPursuit.tscn", &"from_shaft")
	if await _run([["exit", 1]]):
		check(SceneRouter.current_room.name == "FirstPursuit", "the top door leads to First Pursuit")
		check(Game.state.last_entry_id == "from_shaft", "arrival should record FirstPursuit's from_shaft entry")


## Secret 1 (the first secret): two light blade hits open the closet.
func test_shaft_closet_secret() -> void:
	_campaign(true)
	await _enter(UC + "MaintenanceShaft.tscn", &"from_medical")
	if not await _run(SHAFT_TO_CLOSET):
		return
	check(Game.is_collected("uc_shaft_closet"), "the closet wall should be broken by the blade")
	check(Game.is_collected("sb_uc_shaft_closet"), "the closet scrap bundle should be collected")
	check(Game.is_collected("mf_undercity_01") and Game.state.memory_fragments.has("mf_undercity_01"), "the closet fragment should be collected")


## The optional crew ledge: one step up from the exit ledge, then a 92 px
## run-jump. The note is read there; the stash is 20 Scrap.
func test_shaft_crew_pocket() -> void:
	_campaign(true)
	await _enter(UC + "MaintenanceShaft.tscn", &"from_pursuit")
	# A short settle replaces the draft's ["run", 390]: that step ends with a
	# small rightward drift, which RouteBot's runjump reads as "already
	# turning" and jumps on the spot.
	if not await _run([["run", 460], ["jump", 390], ["wait", 8], ["runjump", 304, 160], ["run", 40], ["wait", 10]]):
		return
	check(Game.is_collected("sb_uc_shaft_crew"), "the crew stash should be collected")
	check_near(bot.player.global_position.y, -768.0, 2.0, "Rook should stand on the crew ledge")


## The first composition (Floor 2): every other enemy idles, the Needle and
## Scout pair keep their AI. Both engage within 2 s of Rook reaching Floor 2,
## the director caps them at two attackers, and the blade alone kills the
## Needle.
func test_shaft_first_composition() -> void:
	_campaign(true)
	await _enter(UC + "MaintenanceShaft.tscn", &"from_medical", false)
	var room := SceneRouter.current_room as Room
	var pair: Array[Enemy] = []
	for e in room.find_children("*", "Enemy", true, false):
		var enemy := e as Enemy
		if enemy.global_position.y < -470.0:
			pair.append(enemy)
		else:
			enemy.ai_enabled = false
			enemy.set_ai(Enemy.AI.IDLE)
	check(pair.size() == 2, "Floor 2 should hold exactly two enemies (got %d)" % pair.size())
	room.player.reactor.config = room.player.reactor.config.duplicate()
	room.player.reactor.config.drain_per_second = 0.0
	if not await _run(SHAFT_TO_CLOSET.slice(0, 12)):
		return
	var director := room.get_node("EncounterDirector") as EncounterDirector
	var engaged := false
	var max_seen := 0
	for f in 120:
		await physics_frames(1)
		max_seen = maxi(max_seen, director.active_attackers())
		if pair.all(func(x: Enemy) -> bool: return x.ai != Enemy.AI.IDLE):
			engaged = true
			break
	check(engaged, "both Floor 2 enemies should engage within 2 s")
	check(director.max_attackers == 2 and max_seen <= 2, "the director should allow at most two attackers (saw %d)" % max_seen)
	var needle: Enemy = null
	for e in pair:
		if e.data.id == "needle":
			needle = e
	check(needle != null, "the Floor 2 pair should include a Needle")
	if needle == null:
		return
	# Two blade strings, each from close range (the Needle steps in and out
	# of reach while it lunges, so Rook closes in before each string).
	for n in 2:
		if not is_instance_valid(needle) or needle.is_dead():
			break
		await _shaft_close_in(needle)
		await _run([["attack", 3]])
	check(not is_instance_valid(needle) or needle.is_dead(), "two blade strings should kill the Needle")


## Walks Rook to within blade reach of `target`, facing it (at most 1 s).
func _shaft_close_in(target: Enemy) -> void:
	for f in 60:
		if not is_instance_valid(target) or target.is_dead():
			break
		var dx := target.global_position.x - bot.player.global_position.x
		if absf(dx) < 22.0:
			bot.input.move_x = int(signf(dx))
			await physics_frames(1)
			break
		bot.input.move_x = int(signf(dx))
		await physics_frames(1)
	bot.input.move_x = 0


## FirstPursuit (tools/roomgen/uc_first_pursuit.py): the slide lesson, the
## Collector eye chase ("keep moving"), pair 2 and Orr's radio. Kit: blade.
const FIRST_PURSUIT := "res://world/rooms/undercity/FirstPursuit.tscn"
## From from_shaft through pair 2 (the eye is live; other enemies pacified).
## The cart-stack hop and the well run-jump stop under the eye for less than
## its 1.0 s lock time, so this route is never locked.
const FIRST_PURSUIT_TO_PAIR := [["run", 150], ["slide", 440], ["run", 990], ["jump", 1030], ["run", 1270],
	["runjump", 1296, 1410], ["run", 1560], ["slide", 1790], ["run", 2730], ["attack", 3], ["run", 3170],
	["attack", 3], ["run", 3300], ["attack", 3]]
## Section A and B only: the eye test stops at 1200, the checkpoint test at 1900.
const FIRST_PURSUIT_TO_CART := [["run", 150], ["slide", 440], ["run", 990], ["jump", 1030]]


## The room's CollectorEye (null once it freed itself post-win).
func _first_pursuit_eye() -> CeilingTracker:
	var room := SceneRouter.current_room as Room
	if room == null:
		return null
	return room.find_child("CollectorEye", true, false) as CeilingTracker


## Samples the eye every physics frame into `seen` (max x, states seen): a
## Dictionary the caller owns. The caller disconnects the returned Callable.
func _first_pursuit_watch(eye: CeilingTracker, seen: Dictionary) -> Callable:
	seen["max_x"] = -INF
	seen["states"] = []
	var cb := func() -> void:
		if not is_instance_valid(eye):
			return
		seen["max_x"] = maxf(float(seen["max_x"]), eye.position.x)
		var sname := eye.state_name()
		if not (seen["states"] as Array).has(sname):
			(seen["states"] as Array).append(sname)
	get_tree().physics_frame.connect(cb)
	return cb


## Counts every Collector eye bolt spawned into `room`.
func _first_pursuit_count_bolts(room: Room, bolts: Array) -> Callable:
	var cb := func(n: Node) -> void:
		if n is Projectile and (n as Projectile).attack != null and (n as Projectile).attack.id == &"collector_eye_bolt":
			bolts.append(1)
	room.child_entered_tree.connect(cb)
	return cb


## Waits for a death respawn (a room reload) after `from`.
func _first_pursuit_wait_room_change(from: Node, frames := 300) -> bool:
	for i in frames:
		await physics_frames(1)
		if SceneRouter.current_room != from and is_instance_valid(SceneRouter.current_room) and not SceneRouter.transitioning:
			await physics_frames(3)
			return true
	return false


func test_first_pursuit_route() -> void:
	_campaign(true)
	await _enter(FIRST_PURSUIT, &"from_shaft")
	var eye := _first_pursuit_eye()
	check(eye != null, "FirstPursuit has no CollectorEye before the boss")
	if eye == null:
		return
	var seen := {}
	var cb := _first_pursuit_watch(eye, seen)
	var ok: bool = await _run(FIRST_PURSUIT_TO_PAIR)
	check(Game.state.last_entry_id == "pursuit_mid", "crossing x 1816 should move the respawn to pursuit_mid (got '%s')" % Game.state.last_entry_id)
	if ok:
		# The radio's 24 px use area is 3978..4002; Rook (12 wide) overlaps it
		# from 3972, so the spec's 3960 would stop short of it.
		ok = await _run([["run", 3980], ["interact"]])
	if ok:
		check(dialogue_box.is_open(), "the radio should open a conversation")
		await _close_dialogue()
		ok = await _run([["run", 4116]])
	get_tree().physics_frame.disconnect(cb)
	check((seen["states"] as Array).has("TRACK"), "the eye should have tracked Rook: %s" % str(seen["states"]))
	check(not (seen["states"] as Array).has("LOCK") and eye.lock_count == 0, "the critical route must never be locked: %s" % str(seen["states"]))
	check(float(seen["max_x"]) <= 1620.0, "the eye left its rail: max x %.1f" % float(seen["max_x"]))
	check(Game.has_flag("met_orr_radio"), "the radio call should set met_orr_radio")
	check(Game.state.last_entry_id == "pursuit_mid", "no Anchor here: the respawn stays pursuit_mid")
	if _assert_exit(1, UC + "BrokenLift.tscn", &"from_pursuit") and ok:
		if await _run([["exit", 1]]):
			check(SceneRouter.current_room.name == "BrokenLift", "the east door leads to the Broken Lift")


## Secret 2: the high-ledge cache, reached by a taught run-jump (96 px).
func test_first_pursuit_cache() -> void:
	_campaign(true)
	await _enter(FIRST_PURSUIT, &"from_shaft")
	var ok: bool = await _run(FIRST_PURSUIT_TO_PAIR)
	if ok:
		# ["run", 3600] settles the landing drift first (runjump's run-up
		# treats a backward drift as "already at speed" and jumps on the spot);
		# ["run", 3750] clears the far ledge (x 3776) so Rook drops to the floor.
		await _run([["run", 3470], ["jump", 3470], ["jump", 3530], ["jump", 3590], ["run", 3600], ["runjump", 3676, 3790],
			["run", 3806], ["attack", 3], ["run", 3856], ["run", 3750], ["run", 4116]])
	check(Game.is_collected("uc_pursuit_cache"), "the cache wall should be broken")
	check(Game.is_collected("sb_uc_pursuit_cache"), "the cache scrap should be collected")


## Standing still under the eye: exactly one LOCK and one bolt, then nothing
## more inside the cooldown.
func test_first_pursuit_eye() -> void:
	_campaign(true)
	await _enter(FIRST_PURSUIT, &"from_shaft")
	var eye := _first_pursuit_eye()
	check(eye != null, "FirstPursuit has no CollectorEye")
	if eye == null:
		return
	var room := SceneRouter.current_room as Room
	var bolts: Array = []
	var bcb := _first_pursuit_count_bolts(room, bolts)
	if not await _run(FIRST_PURSUIT_TO_CART + [["run", 1200]]):
		room.child_entered_tree.disconnect(bcb)
		return
	var p := room.player
	var reached := false
	for f in 360:
		if eye.state == CeilingTracker.State.TRACK and absf(eye.position.x - p.global_position.x) <= eye.config.cone_half_width:
			reached = true
			break
		await physics_frames(1)
	check(reached, "the eye never reached Rook at 1200 (eye x %.1f, %s)" % [eye.position.x, eye.state_name()])
	await physics_frames(roundi((eye.config.lock_time + eye.config.windup + 0.1) * 60.0))
	check(eye.lock_count == 1, "standing should lock exactly once (got %d)" % eye.lock_count)
	check(bolts.size() == 1, "one bolt should fire (got %d)" % bolts.size())
	await physics_frames(90)  # 1.5 s, inside the 1.6 s cooldown
	check(eye.lock_count == 1, "no second LOCK inside the cooldown (got %d)" % eye.lock_count)
	room.child_entered_tree.disconnect(bcb)


## A death in section C respawns at pursuit_mid with full health and the eye
## already gone, so the respawn is never hunted and A and B are not replayed.
func test_first_pursuit_checkpoint() -> void:
	_campaign(true)
	await _enter(FIRST_PURSUIT, &"from_shaft")
	if not await _run(FIRST_PURSUIT_TO_CART + [["run", 1270], ["runjump", 1296, 1410], ["run", 1560], ["slide", 1790], ["run", 1900]]):
		return
	var room := SceneRouter.current_room as Room
	room.player.combat.take_damage(room.player.combat.health, Vector2.ZERO, 0.0, true)
	check(await _first_pursuit_wait_room_change(room), "death did not reload the room")
	var r := SceneRouter.current_room as Room
	check(r.name == "FirstPursuit", "respawned in %s, not FirstPursuit" % r.name)
	check(absf(r.player.global_position.x - 1820.0) < 24.0 and absf(r.player.global_position.y) < 4.0,
		"the respawn should be pursuit_mid (1820, 0), got %s" % r.player.global_position.round())
	check(r.player.combat.health == r.player.combat.config.max_health and not r.player.combat.dead, "the respawn should restore full health")
	var eye := _first_pursuit_eye()
	check(eye != null and eye.state == CeilingTracker.State.GONE, "the eye should load GONE at pursuit_mid")
	if eye == null:
		return
	var seen := {}
	var cb := _first_pursuit_watch(eye, seen)
	bot = RouteBot.new(get_tree(), r.player)
	await _run([["run", 1840], ["slide", 1610], ["run", 1420], ["runjump", 1384, 1270], ["run", 1190],
		["jump", 1130], ["run", 800]])
	get_tree().physics_frame.disconnect(cb)
	check(seen["states"] == ["GONE"], "walking back west must never wake the eye: %s" % str(seen["states"]))
	# The east door: arriving from the Broken Lift skips the chase too.
	await _enter(FIRST_PURSUIT, &"from_lift")
	eye = _first_pursuit_eye()
	check(eye != null and eye.state == CeilingTracker.State.GONE, "entering at from_lift should load the eye GONE")


## After the Collector Drone: no eye, and the hatch hangs open and dark.
func test_first_pursuit_post_win() -> void:
	_campaign(true)
	Game.set_flag("collector_drone_defeated")
	await _enter(FIRST_PURSUIT, &"from_shaft")
	check(_first_pursuit_eye() == null, "no CollectorEye may exist after the boss")
	var room := SceneRouter.current_room as Room
	var dead := room.find_child("HatchDead", true, false) as CanvasItem
	var live := room.find_child("HatchLive", true, false) as CanvasItem
	check(dead != null and dead.visible, "HatchDead should show after the boss")
	check(live != null and not live.visible, "the red hatch ring should go dark after the boss")


## BrokenLift: the shaft foot to the top of climb 2 (climb 1, Landing 1 and
## the Needle in FZ1, climb 2); the rest leaves FZ1 for Landing 2, climb 3 and
## the Top Landing past the uc_lift Anchor to the arena door.
const BROKEN_LIFT := UC + "BrokenLift.tscn"
const BROKEN_LIFT_TO_CLIMB2 := [
	["run", 460], ["jump", 460], ["jump", 540], ["jump", 460], ["jump", 380], ["run", 200], ["attack", 3],
	["run", 180], ["jump", 180], ["jump", 100], ["jump", 180],
]
const BROKEN_LIFT_TO_DOOR := [
	["jump", 262], ["run", 350], ["jump", 350], ["jump", 270], ["jump", 350], ["jump", 430], ["run", 600],
]


## The plain route (Needle pacified, no resting: the Anchor opens UI) ends at
## the arena door and walks through it into the Collector Bay.
func test_broken_lift_route() -> void:
	_campaign(true)
	await _enter(BROKEN_LIFT, &"from_pursuit")
	check(Game.state.last_entry_room == BROKEN_LIFT and Game.state.last_entry_id == "from_pursuit", "pre-Anchor respawn should record the shaft foot")
	_assert_exit(-1, UC + "FirstPursuit.tscn", &"from_lift")
	if not await _run(BROKEN_LIFT_TO_CLIMB2 + BROKEN_LIFT_TO_DOOR):
		return
	var p := bot.player
	check(p.global_position.y < -570.0 and p.is_on_floor(), "should stand on the Top Landing (at %s)" % p.global_position.round())
	check(not Game.has_flag("core_hud_hidden") and Game.has_flag("hint_first_flow"), "walking through FZ1 should reveal the Core")
	_assert_exit(1, UC + "CollectorBay.tscn", &"from_lift")
	if await _run([["exit", 1]]):
		check(SceneRouter.current_room.name == "CollectorBay", "the east door leads to the Collector Bay")


## Curiosity: dropping east off climb 2's top step lands on the car roof and
## its Scrap.
func test_lift_car() -> void:
	_campaign(true)
	await _enter(BROKEN_LIFT, &"from_pursuit")
	if not await _run(BROKEN_LIFT_TO_CLIMB2 + [["run", 264], ["wait", 20]]):
		return
	check(Game.is_collected("sb_uc_lift_car"), "the lift-car roof Scrap should be collected (Rook at %s)" % bot.player.global_position.round())
	check(bot.player.global_position.y > -290.0 and bot.player.global_position.y < -270.0, "Rook should stand on the car roof (at %s)" % bot.player.global_position.round())


## The Core lesson at a slow pace: 20 s inside FZ1 in Normal mode with the
## Needle live. Rook walks toward it on Landing 1 and fights it there (light
## chains until it drops), then dawdles on the landing before climb 2; the
## Core never falls to critical (25). The first entry reveals the Core bar.
func test_fz1_pace() -> void:
	_campaign(true)
	check(Game.has_flag("core_hud_hidden"), "the Core bar starts hidden")
	await _enter(BROKEN_LIFT, &"from_pursuit", false)
	var p := bot.player
	p.reactor.apply_mode(0)
	p.reactor.charge = 70.0
	# Frames spent in FZ1 and the lowest charge seen there (arrays: lambdas
	# capture by value).
	var inside := [0]
	var lowest := [100.0]
	var sample := func() -> void:
		if is_instance_valid(p) and p.reactor.in_flow():
			inside[0] += 1
			lowest[0] = minf(lowest[0], p.reactor.charge)
	get_tree().physics_frame.connect(sample)
	var needle := SceneRouter.current_room.find_child("Needle1", true, false) as Enemy
	# Up climb 1, then a few steps west until the Needle (160 px aggro) wakes.
	var ok: bool = await _run(BROKEN_LIFT_TO_CLIMB2.slice(0, 5) + [["run", 300]])
	# Fight it where it stands: close in, face it, and chain light attacks
	# until it drops (a live Needle steps and lunges, so a fixed script
	# would whiff).
	var input := bot.input
	var since_swing := 99
	for i in 900:
		if not ok or not is_instance_valid(needle) or needle.is_dead() or not is_instance_valid(p):
			break
		var dx := needle.global_position.x - p.global_position.x
		since_swing += 1
		if absf(dx) > 30.0 or signf(dx) != float(p.facing):
			input.move_x = int(signf(dx))
		else:
			input.move_x = 0
			if since_swing >= 22:
				input.press_light()
				since_swing = 0
		await physics_frames(1)
	input.move_x = 0
	ok = ok and not bot.lost_player and is_instance_valid(p)
	await physics_frames(30)
	check(not is_instance_valid(needle) or needle.is_dead(), "the Needle should fall on Landing 1")
	# The slow part: dawdle on Landing 1, then climb 2 at a walk.
	ok = ok and await _run([["run", 200], ["wait", 990]] + BROKEN_LIFT_TO_CLIMB2.slice(7))
	get_tree().physics_frame.disconnect(sample)
	if not ok:
		return
	check(inside[0] >= 1200, "the slow pace should spend 20 s in FZ1 (%.1f s)" % (inside[0] / 60.0))
	check(lowest[0] > 25.0, "the Core should stay above critical at a 20 s pace (lowest %.1f)" % lowest[0])
	check(not Game.has_flag("core_hud_hidden"), "FZ1's first entry should clear core_hud_hidden")
	check(Game.has_flag("hint_first_flow"), "FZ1's first entry should set hint_first_flow")


## Challenge mode idling in FZ1: the floor holds the Core at 1 and nothing
## burns (D-085).
func test_fz1_challenge_floor() -> void:
	_campaign(true)
	await _enter(BROKEN_LIFT, &"from_pursuit", true, false)
	var p := bot.player
	p.reactor.config = load("res://data/reactor/reactor_challenge.tres")
	p.reactor.charge = 60.0
	if not await _run(BROKEN_LIFT_TO_CLIMB2.slice(0, 5)):
		return
	check(p.reactor.in_flow(), "Landing 1 is inside FZ1")
	var hits := []
	var spy := func(amount: int, _health: int) -> void: hits.append(amount)
	EventBus.player_damaged.connect(spy)
	var hp := p.combat.health
	await physics_frames(1800)
	EventBus.player_damaged.disconnect(spy)
	check_near(p.reactor.charge, 1.0, 0.0001, "30 s idle in FZ1 should stop at the floor")
	check(hits.is_empty() and p.combat.health == hp, "no burnout damage in FZ1 (hits %s)" % str(hits))
	check(p.reactor.is_critical(), "the heartbeat still plays at the floor")


## The first Anchor ends the pre-Anchor respawn (D-063): before resting a
## death returns Rook to the shaft foot, after resting at uc_lift to the Anchor.
func test_broken_lift_anchor_respawn() -> void:
	_campaign(true)
	await _enter(BROKEN_LIFT, &"from_pursuit")
	var room := SceneRouter.current_room
	bot.player.combat.take_damage(99, Vector2.ZERO, 0.0, true)
	for i in 240:
		await physics_frames(1)
		if SceneRouter.current_room != room and is_instance_valid(SceneRouter.current_room) and not SceneRouter.transitioning:
			break
	await physics_frames(2)
	var p := (SceneRouter.current_room as Room).player
	check(SceneRouter.current_room_path == BROKEN_LIFT and p.global_position.distance_to(Vector2(-20, 0)) < 24.0,
			"a death before resting should return to from_pursuit (at %s)" % p.global_position.round())
	Game.rest_at_anchor(BROKEN_LIFT, "uc_lift")
	check(Game.respawn_room() == BROKEN_LIFT and Game.respawn_entry() == &"uc_lift", "resting should make uc_lift the respawn")
	room = SceneRouter.current_room
	p.combat.take_damage(99, Vector2.ZERO, 0.0, true)
	for i in 240:
		await physics_frames(1)
		if SceneRouter.current_room != room and is_instance_valid(SceneRouter.current_room) and not SceneRouter.transitioning:
			break
	await physics_frames(2)
	check(SceneRouter.current_room != room, "the second death did not reload a room")
	p = (SceneRouter.current_room as Room).player
	check(SceneRouter.current_room_path == BROKEN_LIFT and p.global_position.distance_to(Vector2(500, -576)) < 24.0,
			"a death after resting should return to uc_lift (at %s)" % p.global_position.round())
	check(p.combat.health == p.combat.config.max_health, "the Anchor respawn restores health")


func test_collector_bay_post_win_route() -> void:
	print("PENDING: CollectorBay")


func test_escape_tunnel_route() -> void:
	print("PENDING: EscapeTunnel")


func test_full_undercity_walk() -> void:
	print("PENDING: D6")
