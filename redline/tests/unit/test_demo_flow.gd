extends RedlineTestCase
## M9 D6 demo flow (D-165): the router refusal, the border barrier and its
## card, the card's two rows, the demo_build / demo_end_seen flags, the title
## in a demo, the demo-filtered totals, recording off by default, the
## ACT_CLOSE mode, dev routes, save isolation and the challenge exemption.

const TUNNEL := "res://world/rooms/undercity/EscapeTunnel.tscn"
const BAY := "res://world/rooms/undercity/CollectorBay.tscn"
const RELAY := "res://world/rooms/lowlight/Relay.tscn"
const PURSUIT := "res://world/rooms/undercity/FirstPursuit.tscn"
const UNDERCITY := "res://world/rooms/undercity"
const TEST_DIR := "user://test_demo_flow"
const SAVE_DIR := "user://test_demo_flow_saves"
const FULL_SAVE := "res://tests/fixtures/save_full_game_relay.json"

var root: Node2D
var _extras: Array[Node] = []
var _saved_recording: bool
var _saved_variant: String
var _saved_settings_path: String
var _main: Node


func before_each() -> void:
	_saved_recording = Settings.playtest_recording
	_saved_variant = Settings.playtest_variant
	_saved_settings_path = Settings._path
	get_tree().paused = false
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	# Custom dirs first: a forced demo never moves a path a test set.
	SaveManager.save_dir = SAVE_DIR
	Playtest.dir = TEST_DIR
	Game.new_game()


func after_each() -> void:
	for n in _extras:
		if is_instance_valid(n):
			n.queue_free()
	_extras.clear()
	await get_tree().process_frame
	get_tree().paused = false
	BuildInfo.set_force_demo(-1)
	DemoGate.dev_bypass = false
	Challenges.force_active = false
	Playtest.end_session("test_done")
	Playtest.allow_headless = false
	Playtest.dir = Playtest.DIR
	Settings.playtest_recording = _saved_recording
	Settings.playtest_variant = _saved_variant
	Settings._path = _saved_settings_path
	for dir in [TEST_DIR, SAVE_DIR]:
		AtomicJson.remove_tree(dir)
	SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR
	SceneRouter.current_room = null
	SceneRouter.current_room_path = ""
	SceneRouter.world_root = null
	root.queue_free()
	Game.new_game()
	await physics_frames(2)


func _extra(n: Node) -> Node:
	add_child(n)
	_extras.append(n)
	return n


func _gate() -> DemoGate:
	return _extra(DemoGate.new()) as DemoGate


## A full Main scene (menus, HUD, viewport); a forced demo adds its DemoGate.
func _boot_main(start_room: String) -> MenuHost:
	_main = (load("res://Main.tscn") as PackedScene).instantiate()
	_main.set("start_room", start_room)
	_extra(_main)
	await physics_frames(3)
	return _main.get_node("Menus") as MenuHost


func _barriers(room: Node) -> Array:
	return room.find_children("*", "DemoBarrier", true, false)


func _labels(menu: MenuScreen) -> Array:
	var out: Array = []
	for c in menu._body.get_children():
		if c.is_queued_for_deletion():
			continue
		if c is Button:
			out.append((c as Button).text)
		elif c is Label:
			out.append((c as Label).text)
	return out


func _buttons(menu: MenuScreen) -> Array[Button]:
	var out: Array[Button] = []
	for c in menu._body.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c as Button)
	return out


func _scripted(p: Player) -> ScriptedInputSource:
	if not p.input_source is ScriptedInputSource:
		p.input_source = ScriptedInputSource.new()
	return p.input_source as ScriptedInputSource


## Walks the player `dir` until `until` holds or `frames` pass; returns frames used.
func _walk(p: Player, dir: int, frames: int, until: Callable) -> int:
	var src := _scripted(p)
	src.move_x = dir
	for i in frames:
		await get_tree().physics_frame
		if until.call():
			src.move_x = 0
			return i
	src.move_x = 0
	return frames


# --- Router (defence in depth) ----------------------------------------------------

func test_router_refuses_relay_and_emits() -> void:
	BuildInfo.set_force_demo(1)
	SceneRouter.goto_room(TUNNEL)
	await physics_frames(2)
	var room := SceneRouter.current_room
	var seen: Array = []
	var on_boundary := func(from: String, to: String) -> void: seen.append([from, to])
	EventBus.demo_boundary_reached.connect(on_boundary)
	SceneRouter.transition_to(RELAY, &"from_undercity")
	EventBus.demo_boundary_reached.disconnect(on_boundary)
	check(seen == [[TUNNEL, RELAY]], "one boundary signal (%s)" % [seen])
	check(SceneRouter.current_room == room and not SceneRouter.transitioning, "the room stays, no transition")
	SceneRouter.transition_to(PURSUIT)
	check(SceneRouter.transitioning, "a room inside the demo still transitions")
	while SceneRouter.transitioning:
		await get_tree().process_frame
	check(SceneRouter.current_room_path == PURSUIT, "and loads")


func test_goto_room_refuses_out_of_scope() -> void:
	BuildInfo.set_force_demo(1)
	SceneRouter.goto_room(TUNNEL)
	await physics_frames(2)
	var room := SceneRouter.current_room
	check(SceneRouter.goto_room(RELAY) == null, "goto_room refuses the Relay")
	check(SceneRouter.current_room == room and SceneRouter.current_room_path == TUNNEL, "current room unchanged")


# --- Barrier and card ---------------------------------------------------------------

func test_escape_tunnel_gets_one_barrier_in_demo_none_in_full() -> void:
	BuildInfo.set_force_demo(1)
	_gate()
	SceneRouter.goto_room(TUNNEL)
	await physics_frames(2)
	var room := SceneRouter.current_room
	var bs := _barriers(room)
	check(bs.size() == 1, "one barrier (%d)" % bs.size())
	var exit2 := room.find_child("Exit2", true, false) as RoomExit
	if bs.size() == 1:
		var b := bs[0] as DemoBarrier
		check(b.get_parent() == exit2.get_parent() and b.position == exit2.position and b.size == exit2.size,
			"the barrier covers Exit2 (%s %s)" % [b.position, b.size])
		check(b.collision_layer == CombatLayers.WORLD, "a world wall")
		check(b.target_room == RELAY, "leads to the Relay")
	check(not exit2.monitoring, "Exit2 never fires")
	check((room.find_child("Exit1", true, false) as RoomExit).monitoring and BuildInfo.room_allowed(BAY), "Exit1 (to CollectorBay) still works")
	BuildInfo.set_force_demo(0)
	SceneRouter.goto_room(TUNNEL)
	await physics_frames(2)
	check(_barriers(SceneRouter.current_room).is_empty(), "no barrier in the full game")
	check((SceneRouter.current_room.find_child("Exit2", true, false) as RoomExit).monitoring, "Exit2 live in the full game")


func test_walking_into_border_opens_card_and_never_pits() -> void:
	BuildInfo.set_force_demo(1)
	var host := await _boot_main(TUNNEL)
	check(host.has_screen(&"demo_end"), "MenuHost built the demo card")
	SceneRouter.goto_room(TUNNEL, &"from_relay")
	await physics_frames(3)
	var room := SceneRouter.current_room as Room
	check(_barriers(room).size() == 1, "Main's DemoGate placed the barrier")
	var p := room.player
	var deaths := Game.state.deaths
	var health := p.combat.health
	var card := host.screen(&"demo_end")
	var used := await _walk(p, 1, 240, func() -> bool: return card.is_open())
	check(card.is_open(), "the card opened (after %d frames)" % used)
	check(Game.state.deaths == deaths and p.combat.health == health and not p.combat.dead, "no death, no damage")
	check(p.global_position.x <= 1984.0, "the player never passed the gap (x %.1f)" % p.global_position.x)
	check(SceneRouter.current_room == room and not SceneRouter.transitioning, "no room change")
	card.close_menu()


func test_keep_exploring_unpauses_and_card_reopens_on_reentry() -> void:
	BuildInfo.set_force_demo(1)
	var host := await _boot_main(TUNNEL)
	SceneRouter.goto_room(TUNNEL, &"from_relay")
	await physics_frames(3)
	var p := (SceneRouter.current_room as Room).player
	var card := host.screen(&"demo_end")
	var opens: Array = []
	card.visibility_changed.connect(func() -> void:
		if card.visible:
			opens.append(1))
	await _walk(p, 1, 240, func() -> bool: return card.is_open())
	check(card.is_open() and get_tree().paused, "the card pauses the game")
	var keep := _buttons(card)[0]
	check(keep.has_focus(), "Keep exploring has focus")
	keep.pressed.emit()
	check(not card.is_open() and not get_tree().paused, "Keep exploring closes and unpauses")
	await _walk(p, 1, 20, func() -> bool: return card.is_open())
	check(not card.is_open(), "standing in the trigger does not reopen it")
	await _walk(p, -1, 40, func() -> bool: return false)
	await _walk(p, 1, 120, func() -> bool: return card.is_open())
	check(card.is_open() and opens.size() == 2, "walking back in reopens it (%d opens)" % opens.size())
	card.close_menu()


func test_save_and_quit_saves_and_returns_to_title() -> void:
	BuildInfo.set_force_demo(1)
	Game.start_campaign()
	var host := await _boot_main(TUNNEL)
	var title := host.get_node("TitleMenu") as MenuScreen
	check(host.open(&"demo_end"), "card opens")
	var card := host.screen(&"demo_end")
	var quit := _buttons(card)[1]
	check(quit.text == BuildInfo.config().quit_label, "second row is Save and quit (%s)" % quit.text)
	quit.pressed.emit()
	for i in 120:
		await get_tree().process_frame
		if not SceneRouter.transitioning and title.visible:
			break
	check(title.visible, "back on the title")
	check(FileAccess.file_exists(SAVE_DIR + "/profile_1.json"), "the profile was saved")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_DIR + "/profile_1.json"))
	check(data is Dictionary and (data.get("flags", {}) as Dictionary).get("demo_build", false), "the save carries demo_build")
	title.close_menu()


func test_demo_end_seen_set_once() -> void:
	BuildInfo.set_force_demo(1)
	var host := await _boot_main(TUNNEL)
	var sets: Array = []
	var on_flag := func(id: String, _v: Variant) -> void:
		if id == "demo_end_seen":
			sets.append(1)
	EventBus.flag_changed.connect(on_flag)
	check(not Game.has_flag("demo_end_seen"), "unseen")
	host.open(&"demo_end")
	check(Game.has_flag("demo_end_seen"), "the first open sets demo_end_seen")
	host.screen(&"demo_end").close_menu()
	host.open(&"demo_end")
	host.screen(&"demo_end").close_menu()
	EventBus.flag_changed.disconnect(on_flag)
	check(sets.size() == 1, "set once (%d)" % sets.size())


func test_start_campaign_marks_demo_build() -> void:
	Game.start_campaign()
	check(not Game.has_flag("demo_build"), "a full-game campaign is not demo-born")
	BuildInfo.set_force_demo(1)
	Game.start_campaign()
	check(Game.has_flag("demo_build") and Game.state.igt_complete, "a demo campaign carries demo_build")
	var enforce := Game.onboarding.enforce
	var ob := (Game.ONBOARDING as OnboardingConfig).duplicate() as OnboardingConfig
	ob.enforce = not enforce
	Game.onboarding = ob
	Game.start_campaign()
	check(Game.has_flag("demo_build"), "with onboarding.enforce = %s too" % (not enforce))
	Game.onboarding = Game.ONBOARDING


# --- Title, totals, settings ------------------------------------------------------

func _title() -> MenuScreen:
	var t: MenuScreen = load("res://ui/menus/TitleMenu.gd").new()
	_extra(t)
	t.open_menu()
	return t


func test_title_rows_demo() -> void:
	BuildInfo.set_force_demo(1)
	var t := _title()
	var labels := _labels(t)
	check(String(labels[0]).ends_with("DEMO"), "the wordmark carries the demo tag (%s)" % labels[0])
	check(labels.has(BuildInfo.config().title_subtitle), "the demo subtitle")
	check(not labels.has("Labs & dev starts…"), "no labs or Relay start even in a debug build")
	check(not labels.has("New Game+"), "no NG+")
	check(labels.has("Quit"), "Quit on desktop")
	check(labels.has(BuildInfo.label()), "the version label (%s)" % BuildInfo.label())
	t.close_menu()


func test_title_rows_full_unchanged() -> void:
	var t := _title()
	var labels := _labels(t)
	check(String(labels[0]) == "R E D L I N E", "no tag (%s)" % labels[0])
	check(labels.has("New Game") and labels.has("Settings") and labels.has("Quit"), "rows %s" % [labels])
	if OS.is_debug_build():
		check(labels.has("Labs & dev starts…"), "debug builds keep the labs row")
	t.close_menu()


func test_continue_disabled_for_full_game_save() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open(SAVE_DIR + "/profile_1.json", FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(FULL_SAVE))
	f.close()
	var t := _title()
	var cont := _buttons(t)[0]
	check(cont.text == "Continue" and not cont.disabled, "full game: Continue works")
	t.close_menu()
	BuildInfo.set_force_demo(1)
	t.open_menu()
	cont = _buttons(t)[0]
	check(cont.text == "Continue" and cont.disabled, "demo: Continue is disabled for a Relay save")
	check(_labels(t).has("This save is from the full game."), "and says why")
	check(_buttons(t).any(func(b: Button) -> bool: return b.text == "New Game" and b.has_focus()), "New Game has focus")
	t.close_menu()


func test_slice_stats_demo_counts_undercity_only() -> void:
	BuildInfo.set_force_demo(1)
	check(SliceStats.room_paths() == DataDir.list_scenes(UNDERCITY), "demo rooms = the Undercity (%s)" % [SliceStats.room_paths()])
	var ids := 0
	for path in DataDir.list_scenes(UNDERCITY):
		var inst := (load(path) as PackedScene).instantiate()
		for n in inst.find_children("*", "", true, false):
			if (n is Collectible and (n as Collectible).kind != Collectible.Kind.SCRAP_BUNDLE) or n is BreakableWall:
				ids += 1
		inst.free()
	check((SliceStats.totals()["secret_ids"] as Array).size() == ids, "secrets = a direct Undercity scan (%d)" % ids)


func test_settings_recording_default_off_in_demo() -> void:
	Settings.playtest_recording = true
	BuildInfo.set_force_demo(1)
	check(not Settings.playtest_recording, "recording defaults off in the demo")
	Settings.load_settings(TEST_DIR + "/fresh_settings.cfg")
	check(not Settings.playtest_recording, "a fresh demo settings file keeps it off")
	check(not Playtest.recording_allowed(), "nothing records")
	BuildInfo.set_force_demo(-1)
	check(Settings.playtest_recording, "the full game's value comes back")


func test_demo_keeps_every_setting() -> void:
	var host := await _boot_main(TUNNEL)
	check(host.open(&"settings"), "settings open")
	var full := _labels(host.settings)
	host.settings.close_menu()
	BuildInfo.set_force_demo(1)
	check(host.open(&"settings"), "settings open in the demo")
	var demo := _labels(host.settings)
	host.settings.close_menu()
	# Row names only: values may differ (recording defaults off in a demo).
	var names := func(rows: Array) -> Array: return rows.map(func(r: String) -> String: return r.get_slice(":", 0))
	check(names.call(full) == names.call(demo) and full.size() > 3, "the demo has every setting (§24): %s vs %s" % [full, demo])


# --- ACT_CLOSE, dev routes -----------------------------------------------------------

func test_act_close_mode_replaces_slice_card() -> void:
	BuildInfo.set_force_demo(1)
	var c := BuildInfo.config().duplicate() as DemoConfig
	c.end_mode = DemoConfig.EndMode.ACT_CLOSE
	BuildInfo._config = c
	var host := await _boot_main(TUNNEL)
	EventBus.slice_completed.emit()
	check(host.screen(&"demo_end").is_open(), "the demo card opened")
	check(not host.slice_end.is_open(), "not the Act I card")
	host.screen(&"demo_end").close_menu()


func test_dev_teleport_and_transit_refused_in_demo() -> void:
	BuildInfo.set_force_demo(1)
	SceneRouter.goto_room(TUNNEL)
	await physics_frames(2)
	DevActions.teleport(RELAY, "from_undercity")
	check(not SceneRouter.transitioning and SceneRouter.current_room_path == TUNNEL, "dev teleport to the Relay refused")
	Game.state.anchors_rested.assign(["%s|relay" % RELAY, "%s|tunnel" % TUNNEL])
	var stops := Game.transit_destinations()
	check(stops.size() == 1 and stops[0] == "%s|tunnel" % TUNNEL, "transit lists demo stops only (%s)" % [stops])
	check(not BuildInfo.enabled(&"transit"), "transit is off in the demo anyway")
	check(DemoDevActions.demo_border_target()[0] == TUNNEL, "the dev border target is the tunnel")


func test_gate_bypass_allows() -> void:
	BuildInfo.set_force_demo(1)
	SceneRouter.goto_room(TUNNEL)
	await physics_frames(2)
	DemoGate.dev_bypass = true
	DevActions.teleport(RELAY, "from_undercity")
	check(SceneRouter.transitioning, "the bypass walks past the boundary")
	while SceneRouter.transitioning:
		await get_tree().process_frame
	check(SceneRouter.current_room_path == RELAY, "the Relay loaded")
	Game.state.anchors_rested.assign(["%s|relay" % RELAY])
	DemoGate.dev_bypass = false
	check(Game.transit_destinations().is_empty(), "the bypass never widens transit")


func test_demo_session_toggle_restores() -> void:
	SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR
	DemoDevActions.set_demo_session(true)
	await get_tree().process_frame
	check(BuildInfo.is_demo() and DemoDevActions.demo_session_on(), "demo session on")
	check(SaveManager.save_dir == "user://demo/saves", "saves moved (%s)" % SaveManager.save_dir)
	check(not get_tree().get_nodes_in_group(&"demo_gate").is_empty(), "a DemoGate was added")
	DemoDevActions.set_demo_session(false)
	await get_tree().process_frame
	check(not BuildInfo.is_demo() and SaveManager.save_dir == SaveManager.DEFAULT_SAVE_DIR, "off restores")
	check(get_tree().get_nodes_in_group(&"demo_gate").is_empty(), "the gate is gone")
	SaveManager.save_dir = SAVE_DIR


# --- The card ---------------------------------------------------------------------

func test_card_fits_270_and_controller_reachable() -> void:
	BuildInfo.set_force_demo(1)
	var host := await _boot_main(TUNNEL)
	host.open(&"demo_end")
	var card := host.screen(&"demo_end")
	var h := await menu_height(card)
	check(h <= 270.0, "the card fits 270 px (%.0f)" % h)
	var buttons := _buttons(card)
	check(buttons.size() == 2, "two rows (%d)" % buttons.size())
	for b in buttons:
		check(b.focus_mode == Control.FOCUS_ALL and not b.disabled, "%s is focusable" % b.text)
	check(buttons[0].has_focus() and buttons[0].text == BuildInfo.config().keep_label, "Keep exploring has focus")
	await press_action(&"ui_cancel", 2)
	await get_tree().process_frame
	check(not card.is_open() and not get_tree().paused, "ui_cancel = keep exploring")
	check(SceneRouter.current_room_path == TUNNEL, "still in the tunnel")


func test_demo_end_card_has_no_deaths() -> void:
	BuildInfo.set_force_demo(1)
	Game.state.deaths = 7
	var host := await _boot_main(TUNNEL)
	host.open(&"demo_end")
	var text := " ".join(PackedStringArray(_labels(host.screen(&"demo_end"))))
	check(not text.to_lower().contains("death") and not text.contains("7"), "no deaths on the card (§24): %s" % text)
	check(text.contains("Time ") and text.contains("Secrets "), "time and secrets shown")
	host.screen(&"demo_end").close_menu()


func test_playtest_records_demo_end() -> void:
	BuildInfo.set_force_demo(1)
	Settings.playtest_recording = true
	Settings.playtest_variant = "baseline"
	Playtest.allow_headless = true
	Playtest.begin_session("new")
	SceneRouter.goto_room(TUNNEL)
	await physics_frames(2)
	SceneRouter.transition_to(RELAY)
	var ev: Array = Playtest.session.events_of("demo_end") if Playtest.session else []
	check(ev.size() == 1, "one demo_end event (%d)" % ev.size())
	if ev.size() == 1:
		check(ev[0].get("from", "") == TUNNEL and ev[0].get("to", "") == RELAY, "from/to recorded (%s)" % [ev[0]])


# --- Challenges and isolation (R05.1, R05.5, R05.9) -------------------------------------

func test_demo_gate_idle_during_challenge() -> void:
	BuildInfo.set_force_demo(1)
	Challenges.force_active = true
	_gate()
	SceneRouter.goto_room(TUNNEL)
	await physics_frames(2)
	check(_barriers(SceneRouter.current_room).is_empty(), "no barrier while a challenge runs (its FinishLine owns the exit)")
	check((SceneRouter.current_room.find_child("Exit2", true, false) as RoomExit).monitoring, "Exit2 untouched")


## A challenge whose run crosses the border is dropped from the demo's list.
## The fixture is written at runtime (its ChallengeData script lands with the
## challenge runtime); without that runtime the test has nothing to check.
func test_demo_blocked_fixture_absent_in_demo() -> void:
	var lib_path := "res://challenges/%s.gd" % "ChallengeLibrary"
	var data_path := "res://challenges/%s.gd" % "ChallengeData"
	if not (ResourceLoader.exists(lib_path) and ResourceLoader.exists(data_path)):
		print("  (skipped: the challenge runtime is not on this branch)")
		return
	var lib := load(lib_path) as GDScript
	var ch := (load(data_path) as GDScript).new() as Resource
	for kv: Array in [["id", "tt_demo_border_fixture"], ["start_room", TUNNEL], ["finish_exit_target", RELAY]]:
		if kv[0] in ch:
			ch.set(kv[0], kv[1])
	DirAccess.make_dir_recursive_absolute(TEST_DIR + "/challenges")
	check(ResourceSaver.save(ch, TEST_DIR + "/challenges/tt_demo_border_fixture.tres") == OK, "fixture written")
	var saved_dir: Variant = lib.get("data_dir")
	lib.set("data_dir", TEST_DIR + "/challenges")
	lib.call("clear_cache")
	var ids := func() -> Array:
		return (lib.call("all") as Array).map(func(c: Resource) -> String: return str(c.get("id")))
	BuildInfo.set_force_demo(-1)
	check(ids.call().has("tt_demo_border_fixture"), "listed in the full game (%s)" % [ids.call()])
	BuildInfo.set_force_demo(1)
	lib.call("clear_cache")
	check(not ids.call().has("tt_demo_border_fixture"), "absent from the demo")
	lib.set("data_dir", saved_dir)
	lib.call("clear_cache")


## A debug --demo session shares the full game's user dir: its saves land
## under user://demo/saves and the full game's save file is never touched.
func test_debug_demo_leaves_user_saves_untouched() -> void:
	SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR
	var real := SaveManager.DEFAULT_SAVE_DIR + "/profile_1.json"
	var demo := BuildInfo.DEMO_SAVE_DIR + "/profile_1.json"
	var real_before := FileAccess.get_file_as_bytes(real) if FileAccess.file_exists(real) else PackedByteArray()
	var demo_before := FileAccess.get_file_as_bytes(demo) if FileAccess.file_exists(demo) else PackedByteArray()
	var real_existed := FileAccess.file_exists(real)
	var demo_existed := FileAccess.file_exists(demo)
	BuildInfo.set_force_demo(1)
	Game.start_campaign()
	check(Game.save_game() == OK, "saved")
	check(FileAccess.file_exists(demo), "the save landed under user://demo/saves")
	check(FileAccess.file_exists(real) == real_existed
		and (not real_existed or FileAccess.get_file_as_bytes(real) == real_before), "user://saves is unchanged")
	BuildInfo.set_force_demo(-1)
	check(SaveManager.save_dir == SaveManager.DEFAULT_SAVE_DIR, "the full game's save dir is back")
	# Put the developer's own demo save back as it was.
	if demo_existed:
		var f := FileAccess.open(demo, FileAccess.WRITE)
		f.store_buffer(demo_before)
		f.close()
	else:
		AtomicJson.remove_tree(BuildInfo.DEMO_SAVE_DIR)
	SaveManager.save_dir = SAVE_DIR


## R05.5: stores read their files from the demo dir (they reload lazily when
## their dir changes), so a debug demo shows none of the full game's unlocks.
func test_force_demo_reloads_stores_from_demo_dir() -> void:
	Platform.reset_after_tests()
	BuildInfo.set_force_demo(1)
	check(Platform.store_dir == BuildInfo.DEMO_PLATFORM_DIR, "Platform reads user://demo/platform (%s)" % Platform.store_dir)
	check(Platform.unlocked_ids().is_empty(), "no full-game unlocks in the demo")
	var records := "res://challenges/%s.gd" % "RecordStore"
	if ResourceLoader.exists(records):
		var rs := load(records) as GDScript
		if rs.has_method("dir"):
			check(str(rs.call("dir")).begins_with(BuildInfo.DEMO_PLATFORM_DIR), "RecordStore follows Platform.store_dir")
	BuildInfo.set_force_demo(-1)
	check(Platform.store_dir == BuildInfo.DEFAULT_PLATFORM_DIR, "back to user://platform")


# --- Validator rules (DemoRules DM-1..DM-3, DM-5..DM-8) ----------------------------------

func _dm(c: DemoConfig) -> ContentValidator:
	var v := ContentValidator.new()
	v.check_resource(c, "res://tests/fixtures/demo_fixture.tres")
	DemoRules.check(c, v, "res://tests/fixtures/demo_fixture.tres")
	return v


func _has(list: PackedStringArray, rule: String) -> bool:
	return Array(list).any(func(e: String) -> bool: return e.contains("[%s] " % rule))


func test_demo_rules_real_config_clean() -> void:
	var v := _dm(BuildInfo.config())
	check(v.errors.is_empty(), "the shipped demo is clean: %s" % [v.errors])
	check(DemoRules.last_borders.size() == 1 and DemoRules.last_borders[0][1] == "Exit2", "one border exit, EscapeTunnel/Exit2 (%s)" % [DemoRules.last_borders])
	var run := ContentValidator.new()
	DemoRules.run(run)
	check(run.errors.is_empty(), "DemoRules.run is clean: %s" % [run.errors])


func test_dm1_start_room_outside() -> void:
	var c := BuildInfo.config().duplicate() as DemoConfig
	c.allowed_room_dirs = PackedStringArray(["res://world/rooms/lowlight"])
	check(_has(_dm(c).errors, "DM-1"), "the campaign start outside the demo is an error")
	c = BuildInfo.config().duplicate() as DemoConfig
	c.id = "Under City"
	check(_has(_dm(c).errors, "DM-1"), "a bad id is an error")


func test_dm2_no_border_is_error() -> void:
	var c := BuildInfo.config().duplicate() as DemoConfig
	c.allowed_room_dirs = PackedStringArray(["res://world/rooms/undercity", "res://world/rooms/lowlight"])
	check(_has(_dm(c).errors, "DM-2"), "a BORDER demo without a border has no end")
	c.end_mode = DemoConfig.EndMode.ACT_CLOSE
	check(not _has(_dm(c).errors, "DM-2"), "an ACT_CLOSE demo needs no border")


func test_dm5_unknown_feature() -> void:
	var c := BuildInfo.config().duplicate() as DemoConfig
	c.disabled_features = [&"labs", &"multiplayer"] as Array[StringName]
	check(_has(_dm(c).errors, "DM-5"), "unknown disabled feature")


func test_dm6_card_text() -> void:
	var c := BuildInfo.config().duplicate() as DemoConfig
	c.end_lines = PackedStringArray(["x".repeat(91)])
	check(_has(_dm(c).errors, "DM-6"), "a line over its cap")
	c = BuildInfo.config().duplicate() as DemoConfig
	c.keep_label = ""
	check(_has(_dm(c).errors, "DM-6"), "an empty button label")
	c = BuildInfo.config().duplicate() as DemoConfig
	c.end_lines = PackedStringArray(["Rook made it out."])
	check(_has(_dm(c).warnings, "DM-6"), "the knowledge lint warns on the card")


func test_dm7_act_close_needs_close_room() -> void:
	var c := BuildInfo.config().duplicate() as DemoConfig
	c.end_mode = DemoConfig.EndMode.ACT_CLOSE
	var act := ActLibrary.act(1)
	var close_room: String = act.close_sequence.room if act and act.close_sequence else ""
	check(close_room != "" and not c.allows(close_room), "the Act I close plays outside the Undercity (%s)" % close_room)
	check(_has(_dm(c).errors, "DM-7"), "ACT_CLOSE over the Undercity only is an error")
	c.allowed_room_dirs = PackedStringArray(["res://world/rooms/undercity", "res://world/rooms/lowlight"])
	check(not _has(_dm(c).errors, "DM-7"), "an Act I demo is fine")


func test_dm8_web_redirect_source_check() -> void:
	var v := ContentValidator.new()
	DemoRules.check_web_redirect(v, FileAccess.get_file_as_string(DemoRules.BUILD_INFO_SOURCE), FileAccess.get_file_as_string(DemoRules.WEB_TEST_SOURCE))
	check(v.errors.is_empty(), "the real sources pass: %s" % [v.errors])
	v = ContentValidator.new()
	DemoRules.check_web_redirect(v, "static func redirects_dirs() -> bool:\n\treturn true\n", "")
	check(Array(v.errors).filter(func(e: String) -> bool: return e.begins_with("[DM-8] ")).size() == 2, "both halves caught (%s)" % [v.errors])
