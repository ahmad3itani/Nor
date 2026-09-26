extends RefCounted
## Shared setup for the M9 challenge suites (T04): a world root, temp save
## and platform dirs, the fixture challenge folder, and the pinned timing
## settings every exact-frame test uses (overview rule: hitstop 1.0, jump
## hold 0, no aim or damage assist, the default Core, no playtest variant).
## Preloaded by the suites (no class_name: test code stays out of the global
## class list).

const FIXTURES := "res://tests/fixtures/challenges"
const TRIAL := "res://tests/fixtures/challenges/fx_trial.tres"
const REMATCH := "res://tests/fixtures/challenges/fx_rematch.tres"
const STAGED := "res://tests/fixtures/challenges/fx_staged.tres"
const WORLD_A := "res://tests/fixtures/WorldA.tscn"
const WORLD_B := "res://tests/fixtures/WorldB.tscn"
const STAGE_A := "res://tests/fixtures/challenges/StageA.tscn"
const STAGE_B := "res://tests/fixtures/challenges/StageB.tscn"
const SAVE_V3 := "res://tests/fixtures/save_v3_slice.json"

var t: RedlineTestCase
var root: Node2D
var save_dir: String
var platform_dir: String
var _settings: Dictionary = {}
var _variant: String = ""
## [Signal, Callable] connected through listen(), dropped in teardown.
var _conns: Array = []
var _extras: Array[Node] = []
var main: Node = null


func _init(p_test: RedlineTestCase, tag: String) -> void:
	t = p_test
	save_dir = "user://test_%s_saves" % tag
	platform_dir = "user://test_%s_platform" % tag


func setup() -> void:
	t.get_tree().paused = false
	root = Node2D.new()
	t.add_child(root)
	SceneRouter.register_world_root(root)
	SaveManager.save_dir = save_dir
	Platform.reset_for_tests(platform_dir)
	Challenges.records.reload()
	ChallengeLibrary.data_dir = FIXTURES
	ChallengeLibrary.clear_cache()
	_settings = Settings.snapshot()
	_variant = Settings.playtest_variant
	Settings.playtest_variant = ""
	Settings.hitstop_scale = 1.0
	Settings.jump_hold_mode = 0
	Settings.aim_assist = 0
	Settings.damage_assist = 0
	Settings.reactor_mode = 0
	Settings.generous_checkpoints = false
	Settings.challenge_ghost = 1
	Settings.fast_reset_hold = true
	Settings.speedrun_timer = 0
	Game.new_game()
	Game.profile_id = 1


## Connects `c` to `sig` for this test only.
func listen(sig: Signal, c: Callable) -> void:
	sig.connect(c)
	_conns.append([sig, c])


func teardown() -> void:
	for pair: Array in _conns:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	_conns.clear()
	Challenges.reset_for_tests()
	for n in _extras:
		if is_instance_valid(n):
			n.queue_free()
	_extras.clear()
	main = null
	await t.get_tree().process_frame
	t.get_tree().paused = false
	Game.held_profile = null
	Game.suppress_leave_capture = false
	SceneRouter.current_room = null
	SceneRouter.current_room_path = ""
	SceneRouter.world_root = null
	if is_instance_valid(root):
		root.queue_free()
	for d in [save_dir, platform_dir]:
		AtomicJson.remove_tree(d)
	SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR
	Settings.restore(_settings)
	Settings.playtest_variant = _variant
	CinematicMode.theatre = false
	Game.new_game()
	await t.physics_frames(2)


static func fx(path: String) -> ChallengeData:
	return (load(path) as ChallengeData).duplicate(true) as ChallengeData


## Loads a room as the live profile would (no run).
func goto(path: String, entry: StringName = &"") -> Room:
	var r := SceneRouter.goto_room(path, entry) as Room
	await t.physics_frames(2)
	return r


## Waits until the condition holds (checked every physics frame); false on timeout.
func until(cond: Callable, max_frames: int = 30) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await t.get_tree().physics_frame
	return bool(cond.call())


## Starts `ch` and waits for its room to be live (RUNNING, no transition).
func start(ch: ChallengeData, return_to: Dictionary = {}) -> bool:
	if not Challenges.start(ch, return_to):
		return false
	return await until(func() -> bool: return Challenges.phase() == Challenges.Phase.RUNNING and not SceneRouter.transitioning)


func room() -> Room:
	return SceneRouter.current_room as Room if is_instance_valid(SceneRouter.current_room) else null


func player() -> Player:
	var r := room()
	return r.player if r else null


## Drives the room's player with a scripted source.
func drive() -> ScriptedInputSource:
	var src := ScriptedInputSource.new()
	player().input_source = src
	return src


## Presses or releases the reset action (Challenges polls it every tick).
static func reset_key(down: bool) -> void:
	if down:
		Input.action_press("reset")
	else:
		Input.action_release("reset")


## A stand-in MenuHost (group menu_host): records open_when_free requests in
## _queued like the real one and forwards quit_to_title.
func make_host(with_title: bool = false) -> Node:
	var src := GDScript.new()
	src.source_code = """extends Node
signal quit_to_title
var title: MenuScreen = null
var _queued: Array = []
var opened: Array = []
func open_when_free(id: StringName, ctx: Dictionary = {}) -> void:
	_queued.append([id, ctx])
func open_with(id: StringName, ctx: Dictionary) -> void:
	opened.append([id, ctx])
func any_open() -> bool:
	return false
"""
	src.reload()
	var host: Node = src.new()
	host.add_to_group(&"menu_host")
	t.add_child(host)
	_extras.append(host)
	if with_title:
		var title: MenuScreen = load("res://ui/menus/TitleMenu.gd").new()
		host.add_child(title)
		title.open_menu()
		host.set("title", title)
	return host


## Boots the real Main (fade, menus) at `start_room`.
func boot_main(start_room: String) -> MenuHost:
	main = (load("res://Main.tscn") as PackedScene).instantiate()
	main.set("start_room", start_room)
	t.add_child(main)
	_extras.append(main)
	await t.physics_frames(3)
	return main.get_node("Menus") as MenuHost
