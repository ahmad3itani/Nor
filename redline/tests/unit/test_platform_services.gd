extends RedlineTestCase
## M9 T02 platform services: the Platform autoload's gates (headless, theatre,
## dev taint, challenge runs), the lazy local store (atomic writes, .bak
## recovery, version round trip, reload on a store_dir change), the backend
## factory and SaveManager's cloud hook, the no-network lint, rich presence and
## the DebugOverlay lines. Every test writes only under TEST_DIR.

const ROOM_A := "res://tests/fixtures/WorldA.tscn"
const TEST_DIR := "user://test_platform_services"
const DIR_B := "user://test_platform_services_b"
const SAVE_DIR := "user://test_platform_services_saves"
const REAL_STORE := "user://platform/achievements.json"
## Rule modules are plain scripts loaded by path (ContentValidator.RULE_MODULES).
const PlatformRules := preload("res://devtools/content/rules/PlatformRules.gd")

var root: Node2D


class SpyBackend:
	extends PlatformBackend
	var written: Array[String] = []
	var unlocked: Array[String] = []

	func backend_id() -> StringName:
		return &"spy"

	func cloud_file_written(path: String) -> void:
		written.append(path)

	func unlock(api_name: String) -> void:
		unlocked.append(api_name)


func before_each() -> void:
	get_tree().paused = false
	for d in [TEST_DIR, DIR_B, SAVE_DIR]:
		AtomicJson.remove_tree(d)
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	Game.new_game()
	# Let the new game's (retroactive) evaluation pass run before the test.
	await get_tree().process_frame


func after_each() -> void:
	await get_tree().process_frame
	get_tree().paused = false
	CinematicMode.theatre = false
	Challenges.reset_for_tests()
	Platform.reset_after_tests()
	SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR
	SceneRouter.current_room = null
	SceneRouter.current_room_path = ""
	SceneRouter.world_root = null
	root.queue_free()
	Game.new_game()
	for d in [TEST_DIR, DIR_B, SAVE_DIR]:
		AtomicJson.remove_tree(d)
	await physics_frames(2)


func _ach(id: String, conditions: PackedStringArray = [], stat_id: StringName = &"", target: float = 0.0) -> AchievementData:
	var a := AchievementData.new()
	a.id = id
	a.title = "Probe %s" % id
	a.description = "A test achievement."
	a.conditions = conditions
	a.stat_id = stat_id
	a.stat_target = target
	return a


func _use(list: Array[AchievementData]) -> void:
	AchievementLibrary.use_for_tests(list)


func _file(dir: String) -> String:
	return "%s/%s" % [dir, Platform.config.store_file]


# --- Gates and the store ---

func test_inactive_headless_by_default_writes_nothing() -> void:
	check(DisplayServer.get_name() == "headless", "the suite runs headless")
	Platform.store_dir = TEST_DIR
	check(not Platform.allow_headless and not Platform.active(), "headless without opt-in is inactive")
	check(not Platform.earning_allowed(), "nothing is earned while inactive")
	_use([_ach("probe_a", ["flag:t02_probe"])])
	Game.set_flag("t02_probe")
	await physics_frames(3)
	check(not Platform.is_unlocked("probe_a"), "no unlock while inactive")
	var seen: Array = []
	var spy := func(id: String, _retro: bool) -> void: seen.append(id)
	EventBus.achievement_unlocked.connect(spy)
	Platform.dev_unlock("probe_a")
	await physics_frames(2)
	EventBus.achievement_unlocked.disconnect(spy)
	check(not Platform.is_unlocked("probe_a") and seen.is_empty(), "an inactive dev unlock records and announces nothing")
	Platform.flush()
	Platform.notify_file_written("user://x.json")
	Platform._exit_tree()
	check(not DirAccess.dir_exists_absolute(TEST_DIR), "no file or folder written while inactive")


func test_reset_for_tests_uses_temp_dir() -> void:
	var real_before := FileAccess.get_modified_time(REAL_STORE) if FileAccess.file_exists(REAL_STORE) else -1
	Platform.reset_for_tests(TEST_DIR)
	check(Platform.store_dir == TEST_DIR and Platform.allow_headless and Platform.active(), "opted in to the temp dir")
	_use([_ach("probe_a", ["flag:t02_probe"])])
	Platform.dev_unlock("probe_a")
	check(FileAccess.file_exists(_file(TEST_DIR)), "the unlock is written in the temp dir")
	check(Platform.store().path == _file(TEST_DIR), "the store points at the temp dir")
	var real_after := FileAccess.get_modified_time(REAL_STORE) if FileAccess.file_exists(REAL_STORE) else -1
	check(real_after == real_before, "the real user store is untouched")


func test_unknown_backend_falls_back_to_local() -> void:
	var b := PlatformBackends.create(&"no_such_store")
	check(b is LocalPlatformBackend and b.backend_id() == &"local", "unknown ids play on the local backend")
	check(PlatformBackends.create(&"local") is LocalPlatformBackend, "local is local")
	check(Platform.backend is LocalPlatformBackend and Platform.config.backend_id == &"local", "the shipped config is local")
	Platform.reset_for_tests(TEST_DIR)
	Platform.backend = b
	_use([_ach("probe_a")])
	Platform.dev_unlock("probe_a")
	check(Platform.is_unlocked("probe_a"), "unlocks still work on the fallback")


func test_local_store_atomic_and_bak_recovery() -> void:
	Platform.reset_for_tests(TEST_DIR)
	_use([_ach("probe_a"), _ach("probe_b")])
	Platform.dev_unlock("probe_a")
	Platform.dev_unlock("probe_b")
	var path := _file(TEST_DIR)
	check(FileAccess.file_exists(path) and FileAccess.file_exists(path + ".bak"), "second write keeps a .bak")
	check(not FileAccess.file_exists(path + ".tmp"), "no .tmp left behind")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	var s := LocalStore.new()
	s.load_from(TEST_DIR, Platform.config.store_file, 1)
	check(s.is_unlocked("probe_a"), "a corrupt primary recovers from .bak")


func test_store_version_roundtrip() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	AtomicJson.write(_file(TEST_DIR), {"store_version": 1, "unlocked": {"probe_x": {"t": 5, "profile": 2}},
		"lifetime": {"kills": 3}, "presence": {}, "later_section": {"k": 1}})
	Platform.reset_for_tests(TEST_DIR)
	check(Platform.is_unlocked("probe_x") and Platform.unlock_record("probe_x") == {"t": 5, "profile": 2}, "unlock record read")
	check(Platform.stat(&"kills") == 3.0, "lifetime stat read")
	_use([_ach("probe_y")])
	Platform.dev_unlock("probe_y")
	var d := AtomicJson.read(_file(TEST_DIR))
	check(int(d.get("store_version", 0)) == Platform.config.store_version, "store_version written")
	check(int((d.get("later_section", {}) as Dictionary).get("k", 0)) == 1, "unknown sections survive")
	check((d["unlocked"] as Dictionary).has("probe_x") and (d["unlocked"] as Dictionary).has("probe_y"), "both unlocks kept")
	check(int(d["unlocked"]["probe_x"]["t"]) == 5, "unlock time kept")


func test_store_reloads_when_store_dir_changes() -> void:
	Platform.reset_for_tests(TEST_DIR)
	_use([_ach("probe_a"), _ach("probe_b")])
	Platform.dev_unlock("probe_a")
	var text_a := FileAccess.get_file_as_string(_file(TEST_DIR))
	Platform.store_dir = DIR_B
	check(not Platform.is_unlocked("probe_a"), "dir B does not see dir A's unlock")
	Platform.dev_unlock("probe_b")
	check(FileAccess.file_exists(_file(DIR_B)), "dir B written")
	check(FileAccess.get_file_as_string(_file(TEST_DIR)) == text_a, "dir A file unchanged")
	Platform.store_dir = TEST_DIR
	check(Platform.is_unlocked("probe_a") and not Platform.is_unlocked("probe_b"), "back in A: A's state only")


func test_unlock_global_across_new_game() -> void:
	Platform.reset_for_tests(TEST_DIR)
	_use([_ach("probe_a", ["flag:t02_probe"])])
	var seen: Array = []
	var spy := func(id: String, retro: bool) -> void: seen.append([id, retro])
	EventBus.achievement_unlocked.connect(spy)
	Game.set_flag("t02_probe")
	await physics_frames(2)
	check(Platform.is_unlocked("probe_a"), "a met condition unlocks next frame")
	check(seen == [["probe_a", false]], "announced once, not retroactive (%s)" % [seen])
	check(int(Platform.unlock_record("probe_a")["profile"]) == Game.profile_id, "the earning profile is recorded")
	Game.set_flag("t02_probe", false)
	Game.set_flag("t02_probe")
	await physics_frames(2)
	check(seen.size() == 1, "no second announcement")
	Game.new_game()
	await physics_frames(2)
	check(Platform.is_unlocked("probe_a"), "unlocks are global: a new game keeps them")
	check((AtomicJson.read(_file(TEST_DIR))["unlocked"] as Dictionary).has("probe_a"), "on disk")
	EventBus.achievement_unlocked.disconnect(spy)


func test_retro_unlock_on_game_state_reset() -> void:
	Platform.reset_for_tests(TEST_DIR)
	_use([_ach("probe_a", ["flag:t02_probe"])])
	var seen: Array = []
	var spy := func(id: String, retro: bool) -> void: seen.append([id, retro])
	EventBus.achievement_unlocked.connect(spy)
	Game.state.flags["t02_probe"] = true
	EventBus.game_state_reset.emit()
	await physics_frames(2)
	check(seen == [["probe_a", true]], "a load that already earned it unlocks retroactively (%s)" % [seen])
	EventBus.achievement_unlocked.disconnect(spy)


func test_earning_blocked_when_theatre_tainted_or_challenge_active() -> void:
	Platform.reset_for_tests(TEST_DIR)
	check(Platform.earning_allowed(), "a clean profile earns")
	CinematicMode.theatre = true
	check(not Platform.earning_allowed(), "the Ending theatre never earns")
	CinematicMode.theatre = false
	Game.state.dev_tainted = true
	check(not Platform.earning_allowed(), "a dev-tainted profile never earns")
	Platform.dev_allow_tainted = true
	check(Platform.earning_allowed(), "the dev override lets it earn")
	Platform.dev_allow_tainted = false
	Game.state.dev_tainted = false
	Challenges.force_active = true
	check(not Platform.earning_allowed() and Platform.lifetime_allowed(), "a run blocks earning, not lifetime feats")
	Challenges.force_active = false
	# Blocked passes run once earning is allowed again.
	_use([_ach("probe_a", ["flag:t02_probe"])])
	CinematicMode.theatre = true
	Game.set_flag("t02_probe")
	await physics_frames(3)
	check(not Platform.is_unlocked("probe_a"), "no unlock during the theatre")
	CinematicMode.theatre = false
	await physics_frames(3)
	check(Platform.is_unlocked("probe_a"), "unlocked once the theatre ends")


func test_notify_file_written_called_by_save_manager() -> void:
	var spy := SpyBackend.new()
	Platform.backend = spy
	SaveManager.save_dir = SAVE_DIR
	check(SaveManager.save_profile(1, GameState.new().to_dict()) == OK, "saved")
	check(spy.written.size() == 1 and spy.written[0] == SaveManager.profile_path(1), "the cloud hook saw the write (%s)" % [spy.written])


func test_save_manager_works_without_platform() -> void:
	SaveManager.save_dir = SAVE_DIR
	Platform.name = "PlatformAway"
	var err := SaveManager.save_profile(1, GameState.new().to_dict())
	Platform.name = "Platform"
	check(get_node_or_null("/root/Platform") == Platform, "the autoload is back")
	check(err == OK and FileAccess.file_exists(SaveManager.profile_path(1)), "SaveManager saves without Platform")


func test_reset_after_tests_restores_defaults() -> void:
	Platform.reset_for_tests(TEST_DIR)
	_use([_ach("probe_a")])
	Platform.dev_allow_tainted = true
	Platform.backend = SpyBackend.new()
	Platform.pending_toasts.append(["probe_a", false])
	Platform.stats.begin_fight("warden_krail")
	Platform.reset_after_tests()
	check(Platform.store_dir == Platform.DEFAULT_STORE_DIR and not Platform.allow_headless, "store and gate reset")
	check(not Platform.dev_allow_tainted and Platform.backend is LocalPlatformBackend, "override and backend reset")
	check(Platform.pending_toasts.is_empty() and Platform.stats._boss_fight.is_empty(), "no held toast or open fight")
	check(AchievementLibrary.by_id("probe_a") == null, "the fixture library is dropped")
	check(Platform.store().dir == Platform.DEFAULT_STORE_DIR, "the store reloads from the real dir")
	check(DebugOverlay.providers.has(Callable(Platform, "overlay_lines")), "the overlay provider is registered")


# --- Network ban ---

func test_no_network_or_steam_symbols_in_platform() -> void:
	var hits := PlatformRules.network_violations()
	check(hits.is_empty(), "no network or storefront code under res://platform: %s" % [hits])
	check(DataDir.list_files("res://platform", "gd").size() >= 10, "the platform scripts are scanned")


func test_network_lint_ignores_comments() -> void:
	var ok := "## Adapter slot: Steam.setAchievement(api) would go here.\n# HTTPRequest is banned\nfunc f() -> void:\n\tpass # ENet later"
	check(PlatformRules.scan_source(ok).is_empty(), "comments may name APIs: %s" % [PlatformRules.scan_source(ok)])
	check(PlatformRules.scan_source("var r := HTTPRequest.new()").size() == 1, "HTTPRequest in code fails")
	check(PlatformRules.scan_source("var s := \"# no comment\"; var c := HTTPClient.new()").size() == 1,
		"a # inside a string does not start a comment")
	check(PlatformRules.scan_source("var p := Engine.get_singleton(\"Steam\")").size() == 1, "the storefront singleton fails")
	check(PlatformRules.strip_comment("x = 'a#b' # c") == "x = 'a#b' ", "single quotes are strings too")


# --- Data and validation ---

func test_shipped_platform_data_valid() -> void:
	check(Platform.config.validate().is_empty(), "platform_config valid: %s" % [Platform.config.validate()])
	var cat := StatCatalog.shipped()
	check(cat.validate().is_empty(), "stats valid: %s" % [cat.validate()])
	check(PlatformRules.stat_errors(cat).is_empty(), "PL-12 clean: %s" % [PlatformRules.stat_errors(cat)])
	check(PlatformRules.boss_stat_errors(cat, PackedStringArray(["collector_drone", "warden_krail"])).is_empty(), "PL-11 clean")
	check(not PlatformRules.boss_stat_errors(cat, PackedStringArray(["collector_drone"])).is_empty(), "PL-11 catches a missing boss")
	var deaths := cat.stat(&"deaths")
	check(deaths != null and not deaths.shown, "deaths are never listed on Records (R02.8)")
	var medals := cat.stat(&"challenge_silver_medals")
	check(medals != null and medals.lifetime and not medals.profile and medals.label == "Silver medals or better", "medal stat (R02.7)")
	var table := load("res://data/platform/presence.tres") as PresenceTable
	check(table.validate().is_empty(), "presence valid: %s" % [table.validate()])
	var v := ContentValidator.new().run(true)
	check(v.stats["rooms"] > 0, "room pass ran")
	var bosses := PlatformRules.world_boss_ids(v)
	check(bosses.has("collector_drone") and bosses.has("warden_krail"), "the flags-only room pass finds both bosses: %s" % [bosses])
	check(PlatformRules.boss_stat_errors(cat, bosses).is_empty(), "PL-11 clean against the scanned rooms: %s"
		% [PlatformRules.boss_stat_errors(cat, bosses)])
	var krail := cat.stat(&"boss_nohit_warden_krail")
	check(krail.reveal_when == "flag:warden_krail_intro_seen", "boss rows hide behind the intro flag")
	check(not krail.revealed(0.0), "a boss row is hidden before the meeting")
	check(krail.revealed(1.0), "a row with a value is always listed")
	Game.set_flag("warden_krail_intro_seen")
	check(krail.revealed(0.0), "listed once the boss was met")
	check(not deaths.revealed(3.0), "an unshown stat is never listed")
	var unguarded := StatCatalog.new()
	var ub := StatDef.new()
	ub.id = &"boss_time_warden_krail"
	ub.label = "X"
	unguarded.stats.append(ub)
	check(PlatformRules.boss_stat_errors(unguarded, bosses).size() == 1, "PL-11 wants the spoiler guard")
	ub.reveal_when = "nonsense"
	check(not ub.validate().is_empty(), "reveal_when must be a valid condition")
	var dup := StatCatalog.new()
	var s1 := StatDef.new()
	s1.id = &"x"
	s1.label = "X"
	var s2 := StatDef.new()
	s2.id = &"x"
	s2.label = "X"
	s2.kind = StatDef.Kind.DERIVED
	dup.stats.append(s1)
	dup.stats.append(s2)
	check(PlatformRules.stat_errors(dup).size() == 3, "duplicate id, api name and unknown DERIVED are errors")


func test_reveal_when_consumed_and_validated() -> void:
	var a := _ach("probe_reveal", ["flag:t02_probe"])
	a.reveal_when = "flag:t02_probe_seen"
	check(Array(a.content_flags()["conditions"]).has("flag:t02_probe_seen"), "reveal_when is a read")
	check(a.validate().is_empty(), "valid: %s" % [a.validate()])
	var v := ContentValidator.new()
	v.check_resource(a, "res://data/achievements/probe_reveal.tres")
	check(v.consumed.has("t02_probe_seen") and v.consumed.has("t02_probe"), "the validator registers both reads")
	a.reveal_when = "bogus"
	check(Array(a.validate()).any(func(e: String) -> bool: return e.contains("reveal_when")), "bad grammar is an error")


func test_achievement_data_local_rules() -> void:
	var a := _ach("Bad Id")
	check(not a.validate().is_empty(), "id charset checked")
	a = _ach("probe_b")
	check(Array(a.validate()).any(func(e: String) -> bool: return e.contains("condition or a stat")), "needs a condition or stat")
	a = _ach("probe_c", [], &"kills", 0.0)
	check(Array(a.validate()).any(func(e: String) -> bool: return e.contains("stat_target")), "stat target must be > 0")
	a = _ach("probe_d", ["flag:x"])
	a.hidden = true
	a.hint_when_hidden = "Find the probe probe_d here"
	a.title = "probe_d"
	check(Array(a.validate()).any(func(e: String) -> bool: return e.contains("spoils")), "a hint may not name the title")
	a = _ach("probe_e", ["nonsense"])
	check(not a.content_check().is_empty(), "bad condition grammar")
	check(_ach("probe_f").api() == "ACH_PROBE_F", "default api name")
	check(_ach("probe_g", [], &"kills", 3.0).lifetime_only() and not _ach("probe_h", ["flag:x"]).lifetime_only(), "lifetime_only")


# --- Presence and debug overlay ---

func test_presence_room_boss_memory_title_challenge() -> void:
	check(Platform.presence_text() == "In the menus", "no room: the menus (%s)" % Platform.presence_text())
	SceneRouter.goto_room(ROOM_A, &"start")
	await physics_frames(2)
	check(Platform.presence_text() == "Test — WorldA", "world room (%s)" % Platform.presence_text())
	check((Platform.backend as LocalPlatformBackend).presence_text == "Test — WorldA", "pushed to the backend")
	var boss := Node2D.new()
	EventBus.boss_started.emit(boss, "WARDEN KRAIL")
	check(Platform.presence_text() == "Fighting WARDEN KRAIL", "boss (%s)" % Platform.presence_text())
	EventBus.memory_scene_started.emit("probe", &"test")
	check(Platform.presence_text() == "Remembering", "memory")
	EventBus.memory_playback_finished.emit(&"test")
	EventBus.boss_defeated.emit("warden_krail")
	boss.free()
	check(Platform.presence_text() == "Test — WorldA", "back to the room")
	Game.set_flag("act1_complete")
	check(Platform.presence_text() == "Act I complete — WorldA", "act done (%s)" % Platform.presence_text())
	Challenges.force_active = true
	EventBus.challenge_started.emit("br_krail", 1)
	check(Platform.presence_text().begins_with("Challenge — "), "challenge (%s)" % Platform.presence_text())
	Challenges.force_active = false
	Platform.set_presence("lab", "Movement Lab")
	check(Platform.presence_text() == "In the Movement Lab", "manual override")
	await physics_frames(1)
	(SceneRouter.current_room as Room).world_room = false
	EventBus.room_loaded.emit(SceneRouter.current_room)
	check(Platform.presence_text() == "In the WorldA", "a lab room (%s)" % Platform.presence_text())


func test_debug_overlay_provider_lines() -> void:
	Platform.reset_for_tests(TEST_DIR)
	_use([_ach("probe_a"), _ach("probe_b")])
	DebugOverlay.clear_cache()
	Platform.register_overlay()
	Platform.register_overlay()
	check(DebugOverlay.providers.size() == 1, "registered once")
	Platform.dev_unlock("probe_a")
	var lines := DebugOverlay.provider_lines()
	check(lines.has("PRESENCE: In the menus") and lines.has("ACH 1/2"), "overlay lines: %s" % [lines])
