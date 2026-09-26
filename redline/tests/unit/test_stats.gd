extends RedlineTestCase
## M9 T02 stats: where campaign stats count (world rooms, player kills, no
## bosses), the feat detectors (boss no-hit and time, clean chase, style
## rank), profile vs lifetime scope, the challenge feat whitelist and medal
## counter (lifetime only, R02.3/R02.7), and the in-run pass for lifetime-only
## achievements with its held toast (R02.9).

const ROOM_A := "res://tests/fixtures/WorldA.tscn"
const TEST_DIR := "user://test_stats_platform"
const SAVE_DIR := "user://test_stats_saves"
const NEEDLE := preload("res://enemies/variants/Needle.tscn")
const NEEDLE_DATA := preload("res://data/enemies/needle.tres")

var root: Node2D


## Stands in for T01's MenuHost: a node in group menu_host with a menu open.
class StubMenuHost:
	extends Node
	var open := true

	func any_open() -> bool:
		return open


func before_each() -> void:
	get_tree().paused = false
	for d in [TEST_DIR, SAVE_DIR]:
		AtomicJson.remove_tree(d)
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	SaveManager.save_dir = SAVE_DIR
	Game.new_game()
	await get_tree().process_frame
	Platform.reset_for_tests(TEST_DIR)


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
	for d in [TEST_DIR, SAVE_DIR]:
		AtomicJson.remove_tree(d)
	await physics_frames(2)


func _enter_world() -> Room:
	SceneRouter.goto_room(ROOM_A, &"start")
	await physics_frames(2)
	return SceneRouter.current_room as Room


func _lt(id: StringName) -> float:
	return Platform.stat(id, true)


func _pf(id: StringName) -> float:
	return Platform.profile_stat(id)


func _kill(attacker: Node2D, enemy: Enemy, tags: Array[StringName] = []) -> void:
	EventBus.enemy_killed.emit(enemy, HitInfo.create(attacker, NEEDLE_DATA.attacks[0], Vector2.ZERO, Vector2.RIGHT, tags))


func test_kills_only_world_rooms_player_attacker_non_boss() -> void:
	var room: Room = await _enter_world()
	var enemy: Enemy = NEEDLE.instantiate()
	enemy.ai_enabled = false
	enemy.position = Vector2(-4000, -4000)
	room.add_child(enemy)
	_kill(room.player, enemy)
	check(_lt(&"kills") == 1.0 and _pf(&"kills") == 1.0, "a player kill counts in both scopes")
	_kill(room.player, enemy, [&"environmental", &"aerial"] as Array[StringName])
	check(_lt(&"kills") == 2.0 and _lt(&"kills_environmental") == 1.0 and _lt(&"kills_aerial") == 1.0, "tagged kills")
	_kill(enemy, enemy)
	check(_lt(&"kills") == 2.0, "a kill not by the player does not count")
	var boss_data := NEEDLE_DATA.duplicate() as EnemyData
	boss_data.boss = true
	enemy.data = boss_data
	_kill(room.player, enemy)
	check(_lt(&"kills") == 2.0, "boss kills are not kills")
	enemy.data = NEEDLE_DATA
	room.world_room = false
	_kill(room.player, enemy)
	check(_lt(&"kills") == 2.0, "lab kills never count")
	room.world_room = true
	enemy.queue_free()


func test_boss_nohit_detector() -> void:
	var room: Room = await _enter_world()
	# The room's own death handling (respawn timer) is not under test.
	room.death_override = func(_p: Node2D) -> bool: return true
	var s := Platform.stats
	s.begin_fight("warden_krail")
	EventBus.boss_defeated.emit("warden_krail")
	check(_lt(&"boss_nohit_warden_krail") == 1.0 and _lt(&"bosses_defeated") == 1.0, "a clean fight counts")
	s.begin_fight("collector_drone")
	EventBus.player_damaged.emit(1, 3)
	EventBus.boss_defeated.emit("collector_drone")
	check(_lt(&"boss_nohit_collector_drone") == 0.0, "a hit spoils it")
	s.begin_fight("collector_drone")
	EventBus.player_damaged.emit(1, 3)
	EventBus.player_died.emit()
	s.begin_fight("collector_drone")
	EventBus.boss_defeated.emit("collector_drone")
	check(_lt(&"boss_nohit_collector_drone") == 1.0, "a death, then a clean retry counts")
	check(_pf(&"boss_nohit_collector_drone") == 1.0, "profile scope too")


func test_boss_time_min_keeps_best() -> void:
	await _enter_world()
	var s := Platform.stats
	s.begin_fight("warden_krail")
	await physics_frames(30)
	EventBus.boss_defeated.emit("warden_krail")
	var first := _lt(&"boss_time_warden_krail")
	check_near(first, 0.5, 0.05, "first time")
	s.begin_fight("warden_krail")
	await physics_frames(12)
	EventBus.boss_defeated.emit("warden_krail")
	var best := _lt(&"boss_time_warden_krail")
	check(best < first and best > 0.0, "a faster fight replaces it (%.3f)" % best)
	s.begin_fight("warden_krail")
	await physics_frames(40)
	EventBus.boss_defeated.emit("warden_krail")
	check(_lt(&"boss_time_warden_krail") == best and _pf(&"boss_time_warden_krail") == best, "a slower fight keeps the best")
	EventBus.boss_defeated.emit("warden_krail")
	check(_lt(&"bosses_defeated") == 4.0 and _lt(&"boss_time_warden_krail") == best, "no open fight: no time")


func test_chase_clean_counter() -> void:
	await _enter_world()
	EventBus.chase_completed.emit("rainline", 40.0, 0, 12.0)
	check(_lt(&"chase_clean") == 1.0 and _lt(&"chase_best_rainline") == 40.0, "clean chase and its time")
	EventBus.chase_completed.emit("rainline", 30.0, 1, 5.0)
	check(_lt(&"chase_clean") == 1.0 and _lt(&"chase_best_rainline") == 30.0, "a caught run is not clean, but faster")
	EventBus.shutter_passed.emit("s1", 0.2)
	EventBus.shutter_passed.emit("s1", 0.6)
	check(_lt(&"shutter_close_calls") == 1.0, "only margins <= close_call_margin_s")
	EventBus.clamp_dropped.emit("c1", false)
	EventBus.clamp_dropped.emit("c1", true)
	check(_lt(&"clamp_boss_staggers") == 1.0, "only boss staggers")


func test_style_best_rank_max() -> void:
	await _enter_world()
	EventBus.style_changed.emit(10.0, 3)
	EventBus.style_changed.emit(0.0, 1)
	check(_lt(&"best_style_rank") == 3.0 and _pf(&"best_style_rank") == 3.0, "keeps the best rank")
	EventBus.style_changed.emit(99.0, 7)
	check(_lt(&"best_style_rank") == 7.0, "REDLINE is rank 7")


func test_profile_stats_reset_on_new_game_lifetime_persists() -> void:
	await _enter_world()
	EventBus.perfect_dodge.emit(null)
	EventBus.perfect_dodge.emit(null)
	check(_pf(&"perfect_dodges") == 2.0 and _lt(&"perfect_dodges") == 2.0, "both scopes")
	Game.state.deaths = 3
	check(_pf(&"deaths") == 3.0, "deaths are derived from the profile")
	Game.new_game()
	await physics_frames(1)
	check(_pf(&"perfect_dodges") == 0.0 and _pf(&"deaths") == 0.0, "a new game starts at zero")
	check(_lt(&"perfect_dodges") == 2.0, "the lifetime total persists")
	Platform.flush()
	check(float(AtomicJson.read(TEST_DIR + "/achievements.json")["lifetime"]["perfect_dodges"]) == 2.0, "flushed to disk")


func test_lifetime_play_time_counts_world_rooms_only() -> void:
	var room: Room = await _enter_world()
	var t0 := _lt(&"play_time")
	await physics_frames(20)
	check(_lt(&"play_time") > t0, "lifetime play time grows in a world room")
	room.world_room = false
	var t1 := _lt(&"play_time")
	await physics_frames(10)
	check(_lt(&"play_time") == t1, "not in a lab")
	room.world_room = true


func test_challenge_silver_medals_counts_lifetime_only() -> void:
	Challenges.force_active = true
	EventBus.challenge_started.emit("tt_market_run", 1)
	EventBus.challenge_finished.emit("tt_market_run", 0, 3600, 2, true)
	check(_lt(&"challenge_silver_medals") == 1.0, "Silver counts while the run is live")
	EventBus.challenge_started.emit("tt_market_run", 2)
	EventBus.challenge_finished.emit("tt_market_run", 0, 3000, 4, true)
	EventBus.challenge_started.emit("tt_market_run", 3)
	EventBus.challenge_finished.emit("tt_market_run", 0, 5000, 1, false)
	EventBus.challenge_started.emit("tt_market_run", 4)
	EventBus.challenge_finished.emit("tt_market_run", 3, -1, -1, false)
	check(_lt(&"challenge_silver_medals") == 2.0, "Redline counts; Bronze and a death do not")
	check(not Game.state.stats.has("challenge_silver_medals"), "never in the profile or sandbox")


func test_challenge_feat_whitelist_counts_lifetime_only() -> void:
	await _enter_world()
	Challenges.force_active = true
	EventBus.challenge_started.emit("br_krail_nohit", 1)
	EventBus.perfect_dodge.emit(null)
	EventBus.challenge_finished.emit("br_krail_nohit", 0, 5000, 3, true)
	check(_lt(&"boss_nohit_warden_krail") == 1.0 and _pf(&"boss_nohit_warden_krail") == 0.0, "no-hit rematch: lifetime only")
	check(_lt(&"perfect_dodges") == 0.0 and _lt(&"bosses_defeated") == 0.0, "other stats stay suspended in runs")
	EventBus.challenge_started.emit("br_krail", 1)
	EventBus.clamp_dropped.emit("c1", true)
	EventBus.challenge_finished.emit("br_krail", 3, -1, -1, false)
	check(_lt(&"clamp_boss_staggers") == 0.0, "a failed run counts nothing")
	EventBus.challenge_started.emit("br_krail", 2)
	EventBus.clamp_dropped.emit("c1", true)
	EventBus.challenge_finished.emit("br_krail", 0, 6000, 1, false)
	check(_lt(&"clamp_boss_staggers") == 1.0, "a finished Krail rematch with a clamp stagger counts")
	EventBus.challenge_started.emit("tt_rainline", 1)
	EventBus.chase_caught.emit("rainline", 1)
	EventBus.challenge_finished.emit("tt_rainline", 0, 3000, 2, false)
	check(_lt(&"chase_clean") == 0.0, "a caught trial is not clean")
	EventBus.challenge_started.emit("tt_rainline", 2)
	EventBus.challenge_reset.emit("tt_rainline", &"reset")
	EventBus.chase_completed.emit("rainline", 30.0, 0, 4.0)
	EventBus.challenge_finished.emit("tt_rainline", 0, 2800, 2, true)
	check(_lt(&"chase_clean") == 1.0 and _lt(&"chase_best_rainline") == 0.0, "a clean trial counts, its time does not")
	EventBus.challenge_started.emit("pit_style", 1)
	EventBus.style_changed.emit(50.0, 5)
	EventBus.challenge_finished.emit("pit_style", 0, 5, 0, true)
	check(_lt(&"best_style_rank") == 5.0 and _pf(&"best_style_rank") == 0.0, "Pulse Pit feeds the lifetime best rank")
	Game.state.dev_tainted = true
	EventBus.challenge_started.emit("br_krail_nohit", 2)
	EventBus.challenge_finished.emit("br_krail_nohit", 0, 5000, 3, false)
	check(_lt(&"boss_nohit_warden_krail") == 1.0, "a dev-tainted profile counts nothing")


## T04 keeps theatre on for the whole run and restores it only after
## challenge_finished: the medal and the feats must still count.
func test_run_theatre_does_not_block_lifetime_feats() -> void:
	await _enter_world()
	CinematicMode.theatre = true
	Challenges.force_active = true
	EventBus.challenge_started.emit("br_krail_nohit", 1)
	EventBus.clamp_dropped.emit("c1", true)
	EventBus.challenge_finished.emit("br_krail_nohit", 0, 5000, 3, true)
	check(_lt(&"challenge_silver_medals") == 1.0, "the medal counts under the run's theatre")
	check(_lt(&"boss_nohit_warden_krail") == 1.0, "the no-hit feat counts under the run's theatre")
	EventBus.challenge_started.emit("br_krail", 1)
	EventBus.clamp_dropped.emit("c1", true)
	EventBus.challenge_finished.emit("br_krail", 0, 6000, 1, false)
	check(_lt(&"clamp_boss_staggers") == 2.0, "both Krail clamp feats count under the run's theatre")
	check(float(AtomicJson.read(TEST_DIR + "/achievements.json")["lifetime"]["challenge_silver_medals"]) == 1.0, "and is flushed at once")
	Challenges.force_active = false
	EventBus.challenge_started.emit("tt_market_run", 1)
	EventBus.challenge_finished.emit("tt_market_run", 0, 3000, 2, true)
	check(_lt(&"challenge_silver_medals") == 1.0, "outside a run, the Ending theatre blocks it")


func test_lifetime_only_achievement_unlocks_during_run_toast_after_result() -> void:
	var top := AchievementData.new()
	top.id = "probe_top"
	top.title = "Probe"
	top.description = "Probe."
	top.stat_id = &"challenge_silver_medals"
	top.stat_target = 1.0
	var flagged := AchievementData.new()
	flagged.id = "probe_flag"
	flagged.title = "Probe flag"
	flagged.description = "Probe."
	flagged.conditions = PackedStringArray(["flag:t02_run_flag"])
	AchievementLibrary.use_for_tests([top, flagged] as Array[AchievementData])
	var seen: Array = []
	var spy := func(id: String, retro: bool) -> void: seen.append([id, retro])
	EventBus.achievement_unlocked.connect(spy)
	# As in T04: theatre is on for the run and stays on until its restore,
	# which keeps the full pass blocked until game_state_reset.
	CinematicMode.theatre = true
	Challenges.force_active = true
	EventBus.challenge_started.emit("tt_market_run", 1)
	Game.set_flag("t02_run_flag")
	EventBus.challenge_finished.emit("tt_market_run", 0, 3000, 2, true)
	await physics_frames(2)
	check(Platform.is_unlocked("probe_top"), "a lifetime-only achievement unlocks during the run")
	check(not Platform.is_unlocked("probe_flag"), "a flag achievement waits for the restore")
	check(Platform.pending_toasts.size() == 1 and Platform.pending_toasts[0][0] == "probe_top", "its toast is held")
	check(seen.is_empty(), "nothing announced during the run")
	Challenges.force_active = false
	Challenges.force_finishing = true
	await physics_frames(2)
	check(seen.is_empty(), "held while the result card is pending")
	Challenges.force_finishing = false
	get_tree().paused = true
	await get_tree().process_frame
	check(seen.is_empty(), "held while paused")
	get_tree().paused = false
	var host := StubMenuHost.new()
	host.add_to_group(&"menu_host")
	add_child(host)
	await physics_frames(2)
	check(seen.is_empty() and not Platform.pending_toasts.is_empty(), "held while a MenuScreen is open (%s)" % [seen])
	host.open = false
	await physics_frames(2)
	host.queue_free()
	check(seen == [["probe_top", false]], "announced on the first free frame (%s)" % [seen])
	check(Platform.pending_toasts.is_empty(), "queue drained")
	check(not Platform.is_unlocked("probe_flag"), "still locked before the restore")
	CinematicMode.theatre = false
	EventBus.game_state_reset.emit()
	await physics_frames(2)
	check(Platform.is_unlocked("probe_flag"), "the restore's pass unlocks the rest")
	check(seen == [["probe_top", false], ["probe_flag", true]], "the restore's unlock is retroactive (%s)" % [seen])
	EventBus.achievement_unlocked.disconnect(spy)


func test_run_pass_keeps_the_retro_mark() -> void:
	var flagged := AchievementData.new()
	flagged.id = "probe_retro"
	flagged.title = "Probe retro"
	flagged.description = "Probe."
	flagged.conditions = PackedStringArray(["flag:t02_retro_flag"])
	AchievementLibrary.use_for_tests([flagged] as Array[AchievementData])
	var seen: Array = []
	var spy := func(id: String, retro: bool) -> void: seen.append([id, retro])
	EventBus.achievement_unlocked.connect(spy)
	Challenges.force_active = true
	Game.state.flags["t02_retro_flag"] = true
	EventBus.game_state_reset.emit()
	await physics_frames(2)
	check(not Platform.is_unlocked("probe_retro"), "the in-run pass skips campaign achievements")
	Challenges.force_active = false
	await physics_frames(3)
	check(seen == [["probe_retro", true]], "the first full pass after the reset is still retroactive (%s)" % [seen])
	EventBus.achievement_unlocked.disconnect(spy)


func test_lifetime_only_stats_flush_on_finish_and_exit() -> void:
	Challenges.force_active = true
	EventBus.challenge_started.emit("tt_market_run", 1)
	EventBus.challenge_finished.emit("tt_market_run", 0, 3600, 2, true)
	var file := TEST_DIR + "/achievements.json"
	check(float(AtomicJson.read(file)["lifetime"]["challenge_silver_medals"]) == 1.0, "a finished run persists its medal at once")
	Challenges.force_active = false
	Platform.store().set_lifetime(&"chase_clean", 4.0)
	check(Platform.store().dirty, "an unsaved lifetime value")
	# get_tree().quit() sends no close request; leaving the tree must flush.
	Platform._exit_tree()
	check(float(AtomicJson.read(file)["lifetime"]["chase_clean"]) == 4.0, "flushed when the autoload leaves the tree")
	check(not Platform.store().dirty, "nothing left unsaved")


func test_game_state_reset_drops_open_fight_and_stale_run() -> void:
	Platform.stats.begin_fight("warden_krail")
	EventBus.challenge_started.emit("br_krail", 1)
	EventBus.game_state_reset.emit()
	check(Platform.stats._boss_fight.is_empty(), "no open fight carries into the next profile")
	check(Platform.stats._run.is_empty(), "a stale run is dropped outside a live run")
	Challenges.force_active = true
	EventBus.challenge_started.emit("br_krail", 2)
	EventBus.game_state_reset.emit()
	check(not Platform.stats._run.is_empty(), "the sandbox swap mid-run keeps the run's feats")


func test_act1_clear_time_not_set_by_load_derivation() -> void:
	var data := GameState.new().to_dict()
	data["flags"] = {"slice_end_seen": true}
	data["play_time_sec"] = 100.0
	check(SaveManager.save_profile(1, data) == OK, "fixture saved")
	await _enter_world()
	check(Game.load_game(1) and Game.has_flag("act1_complete"), "the load derives act1_complete")
	await physics_frames(1)
	check(_lt(&"act1_clear_time") == 0.0, "a load is not a clear")
	Game.new_game()
	Game.state.play_time_sec = 50.0
	Game.set_flag("act1_complete")
	check(_lt(&"act1_clear_time") == 50.0, "finishing Act I in play records the time")
	check(_pf(&"act1_clear_time") == 0.0, "lifetime only")
