extends RedlineTestCase
## M9 T11 (D4 §8.4, §8.5, §13, D-161): the route suites again under the two
## assists that change how rooms play.
## - "Always full height" (jump_hold_mode 1): every slice_routes,
##   undercity_routes and lowlight_m7_routes test re-runs with the latch on.
##   A test that needs a short hop must be listed in KNOWN_SHORT_HOP with its
##   reason; the test fails when a new one appears (the list may only shrink).
## - "Respawn at room entrance" (generous_checkpoints): every world room on
##   the map is entered, Rook dies right after the entry, and the respawn must
##   put him back at that entry alive (or, for a chase room, not there); the
##   Lowlight slice routes then run from the respawned player.
## The latch itself is checked frame by frame against a held jump.

const PLAYER_SCENE := preload("res://player/Player.tscn")
const TMP_CFG := "user://test_routes_assist_variants.cfg"
const SAVE_DIR := "user://test_routes_assist_variants_saves"
const SUITES := ["test_slice_routes", "test_undercity_routes", "test_lowlight_m7_routes"]
## suite::test -> why it needs a short hop (D-161). Only removals are allowed.
## Measured at T11: no route needs a short hop; the one entry asserts the
## short hop itself (a tap must not climb the Wake ward step), which the latch
## removes by design.
const KNOWN_SHORT_HOP := {
	"test_undercity_routes::test_wake_tap_is_not_enough": "asserts a tap is a short hop (the latch's purpose)",
}
## Lowlight slice rooms with plain routes: [room file, entry, route constant].
const LL := "res://world/rooms/lowlight/"
const SLICE_ROUTES := [
	["Relay.tscn", &"start", "RELAY_TO_ALLEY"],
	["FloodedAlley.tscn", &"from_relay", "ALLEY_ROUTE"],
	["MarketRun.tscn", &"from_alley", "MARKET_ROUTE"],
	["ApartmentStack.tscn", &"from_market", "STACK_ROUTE"],
	["NeonRoofs.tscn", &"from_stack", "ROOFS_ROUTE"],
	["BellTower.tscn", &"from_rainline", "BELL_ROUTE"],
]

var world: Node2D
var root: Node2D
var _snap: Dictionary = {}


func before_each() -> void:
	_snap = snapshot_settings()
	Settings.remove_settings_files(TMP_CFG)
	Settings._path = TMP_CFG
	Settings.apply_defaults()
	SaveManager.save_dir = SAVE_DIR
	Game.new_game()


func after_each() -> void:
	get_tree().paused = false
	if is_instance_valid(world):
		world.queue_free()
	if is_instance_valid(root):
		root.queue_free()
	SceneRouter.current_room = null
	SceneRouter.current_room_path = ""
	SceneRouter.world_root = null
	SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR
	AtomicJson.remove_tree(SAVE_DIR)
	Settings.remove_settings_files(TMP_CFG)
	restore_settings(_snap)
	Game.new_game()
	await physics_frames(2)


# --- The latch, frame by frame (R11.10) ------------------------------------------------

func _spawn(at: Vector2) -> Array:
	world = Node2D.new()
	add_child(world)
	var b := GrayboxBlock.new()
	b.size = Vector2(3000, 64)
	b.position = Vector2(-500, 0)
	world.add_child(b)
	var p: Player = PLAYER_SCENE.instantiate()
	p.abilities = PlayerAbilities.new()
	var input := ScriptedInputSource.new()
	p.input_source = input
	world.add_child(p)
	p.respawn(at)
	await physics_frames(6)
	return [p, input]


## Positions per frame of one run-jump: [positions, airtime frames, dx, frame
## the latch let go (-1 = never latched)].
func _arc(hold: bool, mode: int) -> Array:
	Settings.jump_hold_mode = mode
	var got: Array = await _spawn(Vector2(0, -2))
	var p: Player = got[0]
	var input: ScriptedInputSource = got[1]
	input.move_x = 1
	await physics_frames(20)
	var x0 := p.global_position.x
	input.press_jump()
	var positions: Array[Vector2] = []
	var air := 0
	var released_at := -1
	var was_latched := false
	for i in 90:
		await physics_frames(1)
		if i == 1 and not hold:
			input.release_jump()
		positions.append(p.global_position)
		if not p.is_on_floor():
			air += 1
		if p.jump_latched():
			was_latched = true
		elif was_latched and released_at < 0:
			released_at = i
		if i > 5 and p.is_on_floor():
			break
	var dx := p.global_position.x - x0
	input.release_jump()
	input.move_x = 0
	world.queue_free()
	await physics_frames(1)
	return [positions, air, dx, released_at]


func test_latched_jump_matches_held_arc() -> void:
	var held: Array = await _arc(true, 0)
	var latched: Array = await _arc(false, 1)
	var tap: Array = await _arc(false, 0)
	var hp: Array = held[0]
	var lp: Array = latched[0]
	var worst := 0.0
	for i in mini(hp.size(), lp.size()):
		worst = maxf(worst, (hp[i] as Vector2).distance_to(lp[i]))
	check(hp.size() == lp.size() and worst < 0.01, "a latched tap follows the held arc frame by frame (max diff %.3f px, %d vs %d frames)" % [worst, hp.size(), lp.size()])
	check(int(held[1]) == int(latched[1]), "same airtime (%d vs %d)" % [held[1], latched[1]])
	check_near(float(latched[2]), float(held[2]), 0.01, "same horizontal distance")
	check(int(tap[1]) < int(held[1]), "in Hold mode a tap is still a short hop (%d < %d frames)" % [tap[1], held[1]])
	var cap := Settings.config().jump_latch_max_frames
	var released: int = latched[3]
	check(released > 0 and released < cap, "the latch lets go after the apex window (frame %d) before the %d-frame cap" % [released, cap])


func test_latch_applies_to_scripted_source() -> void:
	Settings.jump_hold_mode = 1
	var got: Array = await _spawn(Vector2(0, -2))
	var p: Player = got[0]
	var input: ScriptedInputSource = got[1]
	var y0 := p.global_position.y
	input.press_jump()
	await physics_frames(1)
	input.release_jump()
	var peak := 0.0
	for i in 60:
		await physics_frames(1)
		peak = maxf(peak, y0 - p.global_position.y)
	check_near(peak, p.config.jump_height, 1.5, "a ScriptedInputSource tap reaches full height with the latch (%.1f)" % peak)


# --- Route suites under "Always full height" ------------------------------------------

func test_routes_with_jump_hold_mode_full() -> void:
	var runner: GDScript = load("res://tests/TestRunner.gd")
	var new_failures: Array[String] = []
	var still_known: Array[String] = []
	for suite_name: String in SUITES:
		var script := load("res://tests/unit/%s.gd" % suite_name) as GDScript
		var suite: RedlineTestCase = script.new()
		add_child(suite)
		for m in suite.get_method_list():
			var method: String = m["name"]
			if not method.begins_with("test_"):
				continue
			var id := "%s::%s" % [suite_name, method]
			Settings.jump_hold_mode = 1
			var before := suite.failures.size()
			var result: Dictionary = await runner.run_one(suite, id, method)
			if result["status"] != "FAIL":
				continue
			if KNOWN_SHORT_HOP.has(id):
				still_known.append(id)
			else:
				new_failures.append("%s (%s)" % [id, " | ".join(suite.failures.slice(before))])
		suite.queue_free()
		await get_tree().process_frame
	Settings.jump_hold_mode = 0
	for id: String in KNOWN_SHORT_HOP:
		if not still_known.has(id):
			print("NOTE: %s now passes with the latch; remove it from KNOWN_SHORT_HOP" % id)
	check(new_failures.is_empty(), "routes that fail with Always full height and are not in KNOWN_SHORT_HOP: %s" % [new_failures])


# --- Generous checkpoints: a death at every room's entry ----------------------------------

func _wait_room_change(from: Node, max_frames := 300) -> void:
	for i in max_frames:
		await physics_frames(1)
		if SceneRouter.current_room != from and is_instance_valid(SceneRouter.current_room) and not SceneRouter.transitioning:
			break
	await physics_frames(3)


## Enters `path` at `entry`, kills Rook there and returns the respawned room.
## `generous` records whether the session entry was going to be used.
func _die_at_entry(path: String, entry: StringName, generous: Array = []) -> Room:
	SceneRouter.goto_room(path, entry)
	await physics_frames(3)
	generous.append(Game.generous_respawn_active())
	var room := SceneRouter.current_room as Room
	room.player.combat.take_damage(99, Vector2.ZERO, 0.0, true, "test")
	await _wait_room_change(room)
	return SceneRouter.current_room as Room


func test_generous_respawn_every_room_entry() -> void:
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	Settings.generous_checkpoints = true
	var problems: Array[String] = []
	var checked := 0
	var expected := 0
	for r: MapRoomData in Game.world_map.rooms:
		var path := r.room_path
		if path == "" or not ResourceLoader.exists(path):
			continue
		expected += 1
		var spawns: Dictionary = WorldMapIndex.room_info(path).get("spawns", {})
		if spawns.is_empty():
			continue
		var entry := StringName(spawns.keys()[0])
		Game.new_game()
		var generous: Array = []
		var room := await _die_at_entry(path, entry, generous)
		checked += 1
		if room == null or not is_instance_valid(room.player):
			problems.append("%s: no room after the respawn" % path.get_file())
			continue
		var policy := WorldMapIndex.respawn_policy(path)
		var at_entry := SceneRouter.current_room_path == path and room.player.global_position.distance_to(room.active_spawn().global_position) < 2.0 \
			and room.active_spawn().spawn_id == entry
		if policy == 0 and not at_entry:
			problems.append("%s/%s: respawned in %s at %s" % [path.get_file(), entry, SceneRouter.current_room_path.get_file(), room.player.global_position.round()])
		elif policy == 1 and bool(generous[0]):
			problems.append("%s: a never-policy room still uses the session entry" % path.get_file())
		await physics_frames(30)
		if is_instance_valid(room) and is_instance_valid(room.player) and (room.player.combat.dead or room.player.combat.health < room.player.combat.config.max_health):
			problems.append("%s/%s: the respawn point hurts or kills (hp %d)" % [path.get_file(), entry, room.player.combat.health])
	check(checked > 0 and checked == expected, "every world room on the map was tried (%d of %d)" % [checked, expected])
	check(problems.is_empty(), "generous respawns: %s" % [problems])


func test_generous_respawn_then_slice_routes() -> void:
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	Settings.generous_checkpoints = true
	var consts := (load("res://tests/unit/test_slice_routes.gd") as GDScript).get_script_constant_map()
	for row: Array in SLICE_ROUTES:
		Game.new_game()
		var room := await _die_at_entry(LL + row[0], row[1])
		if not check_room(room, LL + row[0]):
			continue
		for e in room.find_children("*", "Enemy", true, false):
			(e as Enemy).ai_enabled = false
			(e as Enemy).set_ai(Enemy.AI.IDLE)
		room.player.reactor.config = room.player.reactor.config.duplicate()
		room.player.reactor.config.drain_per_second = 0.0
		var bot := RouteBot.new(get_tree(), room.player)
		await physics_frames(10)
		var ok: bool = await bot.run(consts[row[2]])
		check(ok, "%s after a death at its entry: %s" % [row[0], bot.failure])


func check_room(room: Room, path: String) -> bool:
	var ok := room != null and SceneRouter.current_room_path == path and is_instance_valid(room.player)
	check(ok, "%s: the generous respawn returns to the room (in %s)" % [path.get_file(), SceneRouter.current_room_path])
	return ok
