extends RedlineTestCase
## M9 T07 achievement content and rules: the thirty shipped files validate
## and the validator is clean on them; unlocks (once, AND semantics, style
## rank, top marks); where they count (not in labs, not in the theatre, not
## on a dev-tainted profile, not during a challenge run until the restore);
## retroactive unlocks on load collapsing into one toast; the cross-file
## rules (completion drift, future flags, grind cap); the spoiler guards and
## every flag an achievement reads being produced; the NG+ row; the Circuit
## economy behind circuits_8. Every test writes only under its temp dirs.

const ROOM_A := "res://tests/fixtures/WorldA.tscn"
const TEST_DIR := "user://test_achievements_platform"
const SAVE_DIR := "user://test_achievements_saves"
const NEEDLE := preload("res://enemies/variants/Needle.tscn")
const NEEDLE_DATA := preload("res://data/enemies/needle.tres")
const MENU_SCRIPT := "res://ui/menus/AchievementsMenu.gd"

var root: Node2D
var _settings: Dictionary = {}
var _seen: Array = []
var _extras: Array[Node] = []


func before_each() -> void:
	get_tree().paused = false
	for d in [TEST_DIR, SAVE_DIR]:
		AtomicJson.remove_tree(d)
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	SaveManager.save_dir = SAVE_DIR
	_settings = snapshot_settings()
	Settings.achievement_toasts = true
	AchievementLibrary.clear_cache()
	Game.new_game()
	await get_tree().process_frame
	Platform.reset_for_tests(TEST_DIR)
	_seen.clear()
	EventBus.achievement_unlocked.connect(_spy)


func after_each() -> void:
	EventBus.achievement_unlocked.disconnect(_spy)
	for n in _extras:
		if is_instance_valid(n):
			if n is MenuScreen and (n as MenuScreen).is_open():
				(n as MenuScreen).close_menu()
			n.queue_free()
	_extras.clear()
	await get_tree().process_frame
	get_tree().paused = false
	CinematicMode.theatre = false
	Challenges.reset_for_tests()
	Platform.reset_after_tests()
	_toast().clear()
	restore_settings(_settings)
	SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR
	SceneRouter.current_room = null
	SceneRouter.current_room_path = ""
	SceneRouter.world_root = null
	root.queue_free()
	Game.new_game()
	for d in [TEST_DIR, SAVE_DIR]:
		AtomicJson.remove_tree(d)
	await physics_frames(2)


func _spy(id: String, retro: bool) -> void:
	_seen.append([id, retro])


func _emitted(id: String) -> int:
	return _seen.filter(func(e: Array) -> bool: return e[0] == id).size()


func _toast() -> AchievementToast:
	return Platform.get_node("AchievementToast") as AchievementToast


func _enter_world() -> Room:
	SceneRouter.goto_room(ROOM_A, &"start")
	await physics_frames(2)
	return SceneRouter.current_room as Room


func _fixture(id: String, conditions: PackedStringArray = [], stat_id: StringName = &"", target: float = 0.0) -> AchievementData:
	var a := AchievementData.new()
	a.id = id
	a.title = "Probe %s" % id
	a.description = "A test achievement."
	a.conditions = conditions
	a.stat_id = stat_id
	a.stat_target = target
	a.sort = 9000 + randi() % 1000
	return a


static func _rule_errors(list: Array[AchievementData], rule: String) -> PackedStringArray:
	var out := PackedStringArray()
	for e: String in AchievementRules.check_list(list)["errors"]:
		if e.begins_with("[%s]" % rule):
			out.append(e)
	return out


func _save_with_flags(flags: Dictionary) -> void:
	var d := GameState.new().to_dict()
	d["flags"] = flags
	SaveManager.save_profile(1, d)


# --- Content and rules ---------------------------------------------------------------

func test_every_shipped_achievement_validates_and_validator_clean() -> void:
	var all := AchievementLibrary.all()
	check(all.size() == 30, "thirty Act I achievements ship (%d)" % all.size())
	for a in all:
		check(a.validate().is_empty(), "%s validates: %s" % [a.id, a.validate()])
		var hard := Array(a.content_check()).filter(func(e: String) -> bool: return not e.begins_with("WARN:"))
		check(hard.is_empty(), "%s content_check: %s" % [a.id, hard])
		check(a.act == 1, "%s belongs to Act I" % a.id)
	var v := ContentValidator.new().run(true)
	var r := AchievementRules.check_list(all, v)
	check((r["errors"] as PackedStringArray).is_empty(), "no AchievementRules error: %s" % [r["errors"]])
	for e in v.errors:
		check(not e.contains("data/achievements") and not e.contains("achievement"), "validator error on achievement data: %s" % e)
	# The report table lists every one as earnable.
	check(AchievementRules.last_table.size() == 30, "the report has a row per achievement")
	for row: Array in AchievementRules.last_table:
		check(row[5] == "yes", "%s is earnable in the report" % row[0])


func test_condition_unlock_emits_once() -> void:
	Game.set_flag("warden_krail_defeated")
	await physics_frames(2)
	check(Platform.is_unlocked("krail_down"), "krail_down unlocks on its flag")
	check(_emitted("krail_down") == 1, "announced once (%s)" % [_seen])
	Game.set_flag("warden_krail_defeated")
	Game.set_flag("t07_unrelated")
	await physics_frames(2)
	check(_emitted("krail_down") == 1, "setting it again announces nothing (%s)" % [_seen])
	check(_seen.all(func(e: Array) -> bool: return not bool(e[1])), "live unlocks are not retroactive")


func test_and_semantics_dash_ledges() -> void:
	Game.mark_collected("cs_alley_dash")
	Game.mark_collected("cs_smuggler_dash")
	EventBus.collectible_taken.emit("cs_smuggler_dash", 0)
	await physics_frames(2)
	check(not Platform.is_unlocked("dash_ledges"), "two of three ledges is not enough")
	Game.mark_collected("cs_uc_tunnel_dash")
	EventBus.collectible_taken.emit("cs_uc_tunnel_dash", 0)
	await physics_frames(2)
	check(Platform.is_unlocked("dash_ledges"), "all three unlock it")


func test_completion_drift_errors() -> void:
	var low := _fixture("drift_low", PackedStringArray(["count:secrets:21"]))
	low.completion = true
	var high := _fixture("drift_high", PackedStringArray(["count:secrets:23"]))
	high.completion = true
	var over := _fixture("drift_over", PackedStringArray(["count:secrets:23"]))
	var ok := _fixture("drift_ok", PackedStringArray(["count:secrets:22"]))
	ok.completion = true
	check(not _rule_errors([low] as Array[AchievementData], "PL-7").is_empty(), "completion below the live total is an error")
	check(not _rule_errors([high] as Array[AchievementData], "PL-7").is_empty(), "completion above the live total is an error")
	check(not _rule_errors([over] as Array[AchievementData], "PL-7").is_empty(), "any count above the total is unearnable, even without completion")
	check(_rule_errors([ok] as Array[AchievementData], "PL-7").is_empty(), "the live total passes")


func test_future_flag_guard() -> void:
	var a := _fixture("future_probe", PackedStringArray(["flag:act5_finale_reached"]))
	check(not _rule_errors([a] as Array[AchievementData], "PL-9").is_empty(), "a future flag read in Act I is an error")
	var r := _fixture("future_reveal")
	r.conditions = PackedStringArray(["flag:act1_complete"])
	r.reveal_when = "flag:redline_archive_opened"
	check(not _rule_errors([r] as Array[AchievementData], "PL-9").is_empty(), "so is a future flag in reveal_when")
	a.act = 5
	check(_rule_errors([a] as Array[AchievementData], "PL-9").is_empty(), "an act beyond the built ones may wait for it")


func test_grind_cap() -> void:
	var a := _fixture("grind_probe", [], &"kills", 26.0)
	check(not _rule_errors([a] as Array[AchievementData], "PL-6").is_empty(), "a counter target over the cap is an error")
	a.stat_target = 25.0
	check(_rule_errors([a] as Array[AchievementData], "PL-6").is_empty(), "the cap itself is fine")
	var rank := _fixture("rank_probe", [], &"best_style_rank", 8.0)
	check(not _rule_errors([rank] as Array[AchievementData], "PL-6").is_empty(), "a rank past REDLINE is an error")
	var unknown := _fixture("stat_probe", [], &"no_such_stat", 1.0)
	check(not _rule_errors([unknown] as Array[AchievementData], "PL-6").is_empty(), "an unknown stat is an error")
	var dup := _fixture("grind_probe", [], &"kills", 5.0)
	dup.sort = a.sort
	check(not _rule_errors([a, dup] as Array[AchievementData], "PL-5").is_empty(), "duplicate ids and sorts are errors")
	var setting := _fixture("setting_probe", PackedStringArray(["flag:currency_loss"]))
	check(not _rule_errors([setting] as Array[AchievementData], "PL-10").is_empty(), "a condition naming a setting is an error")


func test_style_redline_unlocks_on_rank_7() -> void:
	await _enter_world()
	EventBus.style_changed.emit(1500.0, 7)
	await physics_frames(2)
	check(Platform.is_unlocked("style_redline"), "rank 7 is REDLINE")
	check(Platform.is_unlocked("style_s"), "and passes S on the way")


func test_lab_kills_do_not_count() -> void:
	var room: Room = await _enter_world()
	room.world_room = false
	var enemy: Enemy = NEEDLE.instantiate()
	enemy.ai_enabled = false
	enemy.position = Vector2(-4000, -4000)
	room.add_child(enemy)
	var tags: Array[StringName] = [&"environmental"]
	EventBus.enemy_killed.emit(enemy, HitInfo.create(room.player, NEEDLE_DATA.attacks[0], Vector2.ZERO, Vector2.RIGHT, tags))
	await physics_frames(2)
	check(Platform.stat(&"kills_environmental", true) == 0.0, "a lab kill counts nothing")
	check(not Platform.is_unlocked("use_the_city"), "and earns nothing")
	room.world_room = true
	EventBus.enemy_killed.emit(enemy, HitInfo.create(room.player, NEEDLE_DATA.attacks[0], Vector2.ZERO, Vector2.RIGHT, tags))
	await physics_frames(2)
	check(Platform.is_unlocked("use_the_city"), "the same kill in a world room does")


func test_theatre_and_tainted_block_and_override() -> void:
	CinematicMode.theatre = true
	Game.set_flag("act1_complete")
	await physics_frames(3)
	check(not Platform.is_unlocked("act1_complete"), "nothing unlocks in the Ending theatre")
	CinematicMode.theatre = false
	await physics_frames(3)
	check(Platform.is_unlocked("act1_complete"), "the held pass runs once the theatre ends")
	Game.state.dev_tainted = true
	Game.set_flag("warden_krail_defeated")
	await physics_frames(3)
	check(not Platform.is_unlocked("krail_down"), "a dev-tainted profile earns nothing")
	Platform.dev_allow_tainted = true
	await physics_frames(3)
	check(Platform.is_unlocked("krail_down"), "the dev override lets it earn")


func test_suspended_during_challenge_then_unlocks_after_restore() -> void:
	Challenges.force_active = true
	Game.set_flag("collector_drone_defeated")
	await physics_frames(3)
	check(not Platform.is_unlocked("collector_down"), "a flag achievement waits while a run is live")
	Challenges.force_active = false
	EventBus.game_state_reset.emit()
	await physics_frames(3)
	check(Platform.is_unlocked("collector_down"), "it unlocks after the restore")
	check(_seen.any(func(e: Array) -> bool: return e[0] == "collector_down"), "and is announced")


func test_retro_on_load_collapses_toast() -> void:
	_save_with_flags({"got_pulse_blade": true, "collector_drone_defeated": true, "met_orr": true,
		"warden_krail_defeated": true, "act1_complete": true})
	var toast := _toast()
	toast.clear()
	var before := toast.shown_count
	check(Game.load_game(1), "the save loads")
	await physics_frames(3)
	for id in ["first_blade", "collector_down", "reach_relay", "krail_down", "act1_complete"]:
		check(Platform.is_unlocked(id), "%s unlocks on load" % id)
	check(_seen.size() >= 5 and _seen.all(func(e: Array) -> bool: return bool(e[1])), "every load unlock is retroactive (%s)" % [_seen])
	check(toast.shown_count == before + 1, "one toast for all of them (%d)" % (toast.shown_count - before))
	check(toast.collapsed(), "the toast is the collapsed one")
	check(toast.lines()[0] == "%d ACHIEVEMENTS UNLOCKED" % _seen.size(), "it counts them: %s" % [toast.lines()])


func test_top_marks_from_challenge_finished() -> void:
	EventBus.challenge_started.emit("tt_market_run", 1)
	EventBus.challenge_finished.emit("tt_market_run", 0, 3000, 1, true)
	await physics_frames(2)
	check(not Platform.is_unlocked("top_marks"), "Bronze is not enough")
	EventBus.challenge_started.emit("tt_market_run", 2)
	EventBus.challenge_finished.emit("tt_market_run", 0, 2500, 2, true)
	await physics_frames(2)
	check(Platform.is_unlocked("top_marks"), "a Silver finish earns Top Marks")
	var a := AchievementLibrary.by_id("top_marks")
	check(a.description.contains("Silver") and not a.description.contains(" S "), "medal words, never style letters: %s" % a.description)


func test_depth_hidden_until_unlocked() -> void:
	var a := AchievementLibrary.by_id("depth")
	check(a != null and a.hidden and a.conditions == PackedStringArray(["flag:null_depth_reached"]), "depth is hidden and reads the T10 flag")
	var m: AchievementsMenu = (load(MENU_SCRIPT) as GDScript).new()
	add_child(m)
	_extras.append(m)
	m.open_menu()
	check(m.entry_text(a)[0].contains("???"), "a fresh profile sees ??? (%s)" % [m.entry_text(a)])
	Game.set_flag("null_open")
	check(m.entry_text(a)[0].contains("Hidden achievement") and m.entry_text(a)[1] == a.hint_when_hidden,
		"after Act I: hidden with its nudge (%s)" % [m.entry_text(a)])
	m.show_hidden = true
	check(m.entry_text(a)[0].contains("Depth"), "the spoiler toggle shows the title")
	m.show_hidden = false
	Game.set_flag("null_depth_reached")
	await physics_frames(2)
	check(Platform.is_unlocked("depth"), "reaching the bottom unlocks it")
	check(m.entry_text(a)[0] == "✓ Depth", "and the row reads in full (%s)" % [m.entry_text(a)])


func test_reveal_flags_are_produced() -> void:
	var v := ContentValidator.new().run(true)
	for f in ["warden_krail_intro_seen", "collector_drone_intro_seen"]:
		check(v.produced.has(f), "%s is produced" % f)
	for id in ["krail_down", "krail_nohit", "clamp_krail"]:
		check(AchievementLibrary.by_id(id).reveal_when == "flag:warden_krail_intro_seen", "%s hides until Krail's intro" % id)
	for id in ["collector_down", "collector_nohit"]:
		check(AchievementLibrary.by_id(id).reveal_when == "flag:collector_drone_intro_seen", "%s hides until the Collector's intro" % id)
	var bad := _fixture("reveal_probe", PackedStringArray(["flag:act1_complete"]))
	bad.reveal_when = "flag:t07_nothing_sets_this"
	var errs := PackedStringArray()
	for e: String in AchievementRules.check_list([bad] as Array[AchievementData], v)["errors"]:
		if e.begins_with("[PL-15]"):
			errs.append(e)
	check(not errs.is_empty(), "a reveal flag nothing sets is an error")


func test_second_run_needs_ng_cycle() -> void:
	Game.set_flag("act1_complete")
	await physics_frames(2)
	check(Platform.is_unlocked("act1_complete") and not Platform.is_unlocked("second_run"), "the first clear is not the second run")
	var s := NewGamePlus.carry(Game.state, NewGamePlus.config(), {"remix": true, "keep_dash": true}, Game.onboarding)
	check(int(s.flags.get("ng_cycle", 0)) == 1 and not bool(s.flags.get("act1_complete", false)), "NG+ starts cycle 1 with Act I open again")
	Game.state = s
	EventBus.game_state_reset.emit()
	await physics_frames(2)
	check(not Platform.is_unlocked("second_run"), "not yet: Act I is not finished in NG+")
	Game.set_flag("act1_complete")
	await physics_frames(2)
	check(Platform.is_unlocked("second_run"), "finishing Act I in NG+ earns it")


func test_every_flag_condition_is_produced() -> void:
	var produced := ContentValidator.new().run(true).produced
	for a in AchievementLibrary.all():
		var reads := Array(a.conditions)
		if a.reveal_when != "":
			reads.append(a.reveal_when)
		for c: String in reads:
			var f := AchievementRules.flag_of(c)
			if f != "":
				check(produced.has(f), "%s reads '%s', which something sets" % [a.id, f])


func test_circuits_8_affordable() -> void:
	var cat := load("res://data/catalog.tres") as ItemCatalog
	var prices: Dictionary = {}
	for shop in ["shop_vell", "shop_iko"]:
		var data := load("res://data/shops/%s.tres" % shop) as ShopData
		for item in data.items:
			if item.kind != ShopItem.Kind.CIRCUIT:
				continue
			var c := cat.circuit(item.item_id) as CircuitData
			prices[item.item_id] = item.price if item.price > 0 else (c.price if c else 0)
	check(prices.size() == 13, "13 Circuits are sold (%d)" % prices.size())
	for free in ["scavenger", "longline"]:
		check(cat.circuit(free) != null and not prices.has(free), "%s is obtained without a shop" % free)
	var sorted: Array = prices.values()
	sorted.sort()
	var six := 0
	for i in 6:
		six += int(sorted[i])
	var nix := load("res://data/shops/shop_nix.tres") as ShopData
	var essentials := 0
	for item in nix.items:
		essentials += item.price * maxi(1, item.max_purchases if item.kind == ShopItem.Kind.UPGRADE else 1)
	var one_time := int(EconomyAudit.compute()["one_time"])
	check(six <= one_time - essentials, "the six cheapest Circuits (%d) fit the one-time Scrap (%d) after Nix's essentials (%d)" % [six, one_time, essentials])


func test_reach_relay_retroactive_for_met_orr_save() -> void:
	_save_with_flags({"met_orr": true})
	check(Game.load_game(1), "the save loads")
	await physics_frames(3)
	check(not Game.has_flag("seen_seq_relay_arrival"), "the save never saw the arrival scene")
	check(Platform.is_unlocked("reach_relay"), "met_orr alone earns Signal in the Rain")
	check(_seen.has(["reach_relay", true]), "retroactively (%s)" % [_seen])
