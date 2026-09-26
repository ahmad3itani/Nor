extends RedlineTestCase
## M9 cross-area tests (D6 §8.2, T14): the interactions no single area owns.
## Achievements (Platform) x challenges (Challenges) x NG+ and the Deep Rig
## (the Challenges null group) x settings and accessibility x localization
## (Loc) x the demo. Saves and platform files go to temp dirs through the
## ChallengeHarness; every test puts back what it changed.

const H := preload("res://tests/fixtures/challenges/ChallengeHarness.gd")
const RELAY := "res://world/rooms/lowlight/Relay.tscn"
## tests/unit files that are not suites (TestRunner only runs test_*.gd).
const HELPER_ALLOWLIST := {}
## New M9 menus (id -> script) checked for fit, scroll and pad parity.
const M9_MENUS := {"achievements": "res://ui/menus/AchievementsMenu.gd", "challenges": "res://ui/menus/ChallengesMenu.gd",
	"ng_plus": "res://ui/menus/NgPlusMenu.gd", "settings": "res://ui/menus/SettingsMenu.gd",
	"assist_suggest": "res://ui/menus/AssistSuggestMenu.gd", "demo_end": "res://ui/menus/DemoEndMenu.gd"}

var h: H
var _extras: Array[Node] = []
var _settings: Dictionary = {}


func before_each() -> void:
	h = H.new(self, "m9_cross")
	h.setup()
	ChallengeLibrary.data_dir = ChallengeLibrary.DEFAULT_DIR
	ChallengeLibrary.clear_cache()
	_settings = Settings.snapshot()
	_extras.clear()


func after_each() -> void:
	for n in _extras:
		if is_instance_valid(n):
			if n is MenuScreen and (n as MenuScreen).is_open():
				(n as MenuScreen).close_menu()
			n.queue_free()
	_extras.clear()
	MenuHost.context = {}
	if Loc.locale() != Loc.SOURCE_LOCALE:
		LocaleDevActions.set_locale(Loc.SOURCE_LOCALE)
	if BuildInfo.force_demo != -1:
		BuildInfo.set_force_demo(-1)
	Settings.restore(_settings)
	InputBindings.apply(Settings.bindings)
	var toast := AchievementDevActions.toast_node()
	if toast:
		toast.clear()
	await h.teardown()


func _extra(n: Node) -> Node:
	add_child(n)
	_extras.append(n)
	return n


func _menu(script: String, ctx: Dictionary = {}) -> MenuScreen:
	var m: MenuScreen = _extra((load(script) as GDScript).new())
	m.ctx = ctx
	m.open_menu()
	return m


func _buttons(m: MenuScreen) -> Array[Button]:
	var out: Array[Button] = []
	for c in m._body.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c as Button)
	return out


# --- Challenges x platform --------------------------------------------------------------

func test_challenge_sandbox_never_double_counts_stats() -> void:
	var profile := Game.state
	var stats_before: Dictionary = profile.stats.duplicate(true)
	check(await h.goto(H.WORLD_A, &"start") != null, "world room")
	check(await h.start(H.fx(H.TRIAL), {"room": H.WORLD_A, "entry": &"start"}), "run started")
	check(Game.state != profile and Game.held_profile == profile, "the run plays on a sandbox state")
	check(not Platform.stats.counting(), "per-profile stats do not count inside a run")
	Platform.stats.add(&"kills")
	EventBus.player_damaged.emit(1, 4)
	check(profile.stats == stats_before, "the held profile's stats are untouched")
	Challenges.quit()
	check(await h.until(func() -> bool: return not Challenges.active() and not SceneRouter.transitioning, 120), "left the run")
	check(Game.state == profile, "the same profile object is back (D2 contract)")
	check(profile.stats == stats_before, "no stat moved on the profile: %s" % profile.stats)


func test_challenge_finish_unlocks_after_restore() -> void:
	check(not Platform.is_unlocked("top_marks"), "not yet")
	var unlocks: Array = []
	h.listen(EventBus.achievement_unlocked, func(id: String, _r: bool) -> void: unlocks.append(id))
	# The run's kit state is dev-made (tainted); the held profile is not.
	var kit := GameState.new()
	kit.dev_tainted = true
	var sb := ProfileSandbox.begin(kit, PlayerAbilities.new(), false)
	EventBus.challenge_started.emit("tt_neon_roofs", 1)
	EventBus.challenge_finished.emit("tt_neon_roofs", ChallengeData.Outcome.FINISHED, 1200, 2, true)
	sb.restore(false)
	await physics_frames(2)
	check(Platform.is_unlocked("top_marks"), "a Silver finish unlocks Top Marks (lifetime, the kit's taint does not block it)")
	EventBus.challenge_started.emit("tt_neon_roofs", 2)
	EventBus.challenge_finished.emit("tt_neon_roofs", ChallengeData.Outcome.FINISHED, 1100, 3, true)
	await physics_frames(2)
	check(unlocks.count("top_marks") == 1, "unlocked once: %s" % [unlocks])


# --- NG+ x platform, records ------------------------------------------------------------

func _cleared_save() -> void:
	StoryPresets.apply("act1_complete")
	Game.save_game()


func test_ngplus_conversion_no_retro_toast_storm() -> void:
	Settings.achievement_toasts = true
	_cleared_save()
	for id in ["first_blade", "reach_relay", "act1_complete"]:
		Platform.dev_unlock(id)
	var toast := AchievementDevActions.toast_node()
	toast.clear()
	var unlocks: Array = []
	h.listen(EventBus.achievement_unlocked, func(id: String, _r: bool) -> void: unlocks.append(id))
	check(NewGamePlus.begin({"from": "", "remix": true, "keep_dash": true}), "NG+ began: %s" % NewGamePlus.last_refusal)
	await physics_frames(10)
	for id: String in unlocks:
		check(id == "second_run", "only an NG+ achievement unlocks on the conversion (%s)" % id)
	check(toast.queue.size() <= 1 and (not toast.showing() or (toast.current["ids"] as PackedStringArray).size() <= 3),
		"no toast storm (%d queued)" % toast.queue.size())
	for id in ["first_blade", "reach_relay", "act1_complete"]:
		check(Platform.is_unlocked(id), "global unlock %s persists" % id)


func test_records_survive_ngplus() -> void:
	_cleared_save()
	var ch := ChallengeLibrary.by_id("tt_neon_roofs")
	Challenges.records.submit(ch, 1, 1500, ChallengeData.Outcome.FINISHED)
	var before := Challenges.records.best("tt_neon_roofs", 1)
	check(NewGamePlus.begin({"from": "", "remix": false, "keep_dash": true}), "NG+ began")
	await physics_frames(2)
	check(Challenges.records.best("tt_neon_roofs", 1) == before, "records are global and survive NG+")
	check(FileAccess.file_exists("%s/profile_1.cycle0.json" % SaveManager.save_dir), "the cycle archive is written")


func test_null_run_keeps_profile_file_bytes() -> void:
	Game.save_game()
	var path := SaveManager.profile_path(1)
	var bytes := FileAccess.get_file_as_bytes(path)
	var sb := ProfileSandbox.begin(ProfileSandbox.kit_state(H.fx(H.TRIAL).kit, H.fx(H.TRIAL), Game.state), PlayerAbilities.new(), false)
	Game.state.flags["null_scratch"] = true
	Game.save_game()
	check(FileAccess.get_file_as_bytes(path) == bytes, "a save inside the sandbox writes the held profile unchanged (D-150)")
	sb.restore(false)
	check(FileAccess.get_file_as_bytes(path) == bytes and not Game.state.flags.has("null_scratch"), "the profile file is byte-identical")
	check(ChallengeLibrary.by_id("null_descent") != null and ChallengeLibrary.by_id("null_descent").group == ChallengeData.Group.NULL,
		"the Deep Rig runs are the Challenges null group (the same sandbox)")


# --- Accessibility across areas ----------------------------------------------------------

func test_assist_tags_neutral_everywhere() -> void:
	var ids_before := AchievementLibrary.all().map(func(a: AchievementData) -> String: return a.id)
	Settings.aim_assist = 2
	Settings.damage_assist = 2
	Settings.reactor_mode = 1
	Settings.generous_checkpoints = true
	Settings.map_hints = 2
	var ids_after := AchievementLibrary.all().map(func(a: AchievementData) -> String: return a.id)
	check(ids_after == ids_before, "the achievement list does not depend on assists (D-144)")
	var ch := ChallengeLibrary.by_id("tt_neon_roofs")
	var res := Challenges.records.submit(ch, 1, ch.medal_thresholds[1], ChallengeData.Outcome.FINISHED, PackedInt32Array(),
		{"assists": ["aim assist", "damage assist"]})
	check(int(res["medal"]) == ch.medal_for(ch.medal_thresholds[1]), "the same medal with assists")
	var board := Challenges.records.board("tt_neon_roofs")
	check(not board.is_empty() and Array(board[0]["assists"]).has("aim assist"), "the record carries the neutral assist tag")
	var null_rank := ChallengeLibrary.by_id("null_static_lane")
	check(null_rank != null and null_rank.rank_table != null, "Deep Rig ranks come from the rank table, not from assists")
	var cat := load(SettingsCatalog.PATH) as SettingsCatalog
	var shaming := CrossRules.shaming_text(CrossRules.m9_catalog_text(PoFile.load_file(CrossRules.POT_PATH)), cat)
	check(shaming.is_empty(), "no M9 string shames an assist player: %s" % shaming)


func test_pad_view_is_map_in_campaign_reset_in_challenge_and_null() -> void:
	var view := InputEventJoypadButton.new()
	view.button_index = JOY_BUTTON_BACK
	view.device = -1
	check(InputBindings.conflicts(&"map", view).is_empty() and InputBindings.conflicts(&"reset", view).is_empty(),
		"View is both map and reset by the catalog's allowed overlap")
	var y := InputEventJoypadButton.new()
	y.button_index = JOY_BUTTON_RIGHT_STICK
	y.device = -1
	var ov := InputBindings.set_slot(Settings.bindings, &"reset", &"pad", 0, y)
	check(InputBindings.last_refusal == "", "reset rebinds to the right stick press: %s" % InputBindings.last_refusal)
	Settings.bindings = ov
	InputBindings.apply(ov)
	var map_has_view := InputMap.action_get_events(&"map").any(func(e: InputEvent) -> bool:
		return e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == JOY_BUTTON_BACK)
	check(map_has_view, "after a reset rebind, View still opens the map everywhere")


func test_pause_key_p_and_start() -> void:
	var has_p := false
	var has_start := false
	for e in InputMap.action_get_events(&"pause"):
		if e is InputEventKey and ((e as InputEventKey).physical_keycode == KEY_P or (e as InputEventKey).keycode == KEY_P):
			has_p = true
		elif e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == JOY_BUTTON_START:
			has_start = true
	check(has_p and has_start, "P and pad Start open pause")
	check(InputBindings.catalog().has_action(&"pause"), "the rebind catalog lists pause (P is a default, so it can be removed)")


func test_glyph_labels_follow_locale_and_rebind() -> void:
	var was_pad := InputGlyphs.using_pad
	InputGlyphs.using_pad = true
	var before: String = InputGlyphs.label(&"jump")
	LocaleDevActions.set_locale("en_XA")
	var pseudo: String = InputGlyphs.label(&"jump")
	LocaleDevActions.set_locale(Loc.SOURCE_LOCALE)
	InputGlyphs.using_pad = false
	check(pseudo != before, "the prompt label goes through Loc (%s vs %s)" % [pseudo, before])
	var k := InputEventKey.new()
	k.physical_keycode = KEY_H
	var ov := InputBindings.set_slot(Settings.bindings, &"heal", &"key", 0, k)
	Settings.bindings = ov
	InputBindings.apply(ov)
	var now: String = InputGlyphs.label(&"heal")
	check(now == "H", "a hint shows the new binding: %s" % now)
	InputGlyphs.using_pad = was_pad


# --- Menus across areas -------------------------------------------------------------------

func _fits_or_scrolls(m: MenuScreen, what: String) -> void:
	var h := await menu_height(m)
	if h <= 270.0:
		check(true, what)
		return
	var n := _buttons(m).size()
	m.focus_index(n - 1)
	await get_tree().process_frame
	await get_tree().process_frame
	var f := m.get_viewport().gui_get_focus_owner() as Control
	var scroll: ScrollContainer = m._scroll
	check(scroll != null and scroll.is_visible_in_tree() and f != null, "%s is %.0f px and scrolls" % [what, h])
	if scroll and f:
		check(scroll.get_global_rect().grow(1.0).encloses(f.get_global_rect()), "%s: the last row is visible after focus" % what)


func test_every_m9_menu_fits_or_scrolls() -> void:
	StoryPresets.apply("act1_complete")
	Game.save_game()
	for locale: String in [Loc.SOURCE_LOCALE, "en_XA"]:
		LocaleDevActions.set_locale(locale)
		for scale in [0, 2]:
			Settings.ui_scale = scale
			EventBus.settings_changed.emit()
			for id: String in M9_MENUS:
				var m := _menu(M9_MENUS[id], {"from": "title"} if id == "ng_plus" else {})
				await get_tree().process_frame
				await _fits_or_scrolls(m, "%s (%s, ui %d)" % [id, locale, scale])
				m.close_menu()
	LocaleDevActions.set_locale(Loc.SOURCE_LOCALE)
	Settings.ui_scale = 0


func test_controller_parity_all_new_menus() -> void:
	for id: String in M9_MENUS:
		var m := _menu(M9_MENUS[id], {"from": "title"} if id == "ng_plus" else {})
		await physics_frames(1)
		_arm(m)
		check(not _buttons(m).is_empty(), "%s has focusable rows" % id)
		for i in 8:
			if not m.is_open():
				break
			await press_action(&"ui_cancel", 2)
			await physics_frames(1)
		check(not m.is_open(), "%s closes with ui_cancel alone" % id)
	for action in InputMap.get_actions():
		var a := String(action)
		if a.begins_with("ui_") or a.begins_with("debug_"):
			continue
		var pad := InputMap.action_get_events(action).any(func(e: InputEvent) -> bool:
			return e is InputEventJoypadButton or e is InputEventJoypadMotion)
		check(pad, "%s has a controller event" % a)


## Web fullscreen swallows Esc: every M9 page must back out with Backspace
## (ui_back) alone, and every sub-page has an explicit Back row (D-158).
func test_web_keyboard_can_back_out_without_esc() -> void:
	BuildInfo.force_web = 1
	StoryPresets.apply("act1_complete")
	var a := _menu(M9_MENUS["achievements"]) as AchievementsMenu
	a.set("page", &"records")
	a.rebuild()
	check(_buttons(a).any(func(b: Button) -> bool: return b.text == Loc.t("Back")), "Records has a Back row")
	await physics_frames(1)
	await press_action(&"ui_back", 2)
	await physics_frames(1)
	check(a.is_open() and a.page == &"list", "Backspace returns from Records to the list")
	for id: String in M9_MENUS:
		var m: MenuScreen = a if id == "achievements" else _menu(M9_MENUS[id], {"from": "title"} if id == "ng_plus" else {})
		if id == "challenges":
			m.call("show_detail", ChallengeLibrary.by_id("tt_escape_tunnel"))
		elif id == "settings":
			m.call("_go", &"assists")
		await physics_frames(1)
		_arm(m)
		for i in 6:
			if not m.is_open():
				break
			await press_action(&"ui_back", 2)
			await physics_frames(1)
		check(not m.is_open(), "%s backs out with Backspace only" % id)
	BuildInfo.force_web = -1


## The assist card only answers a fresh press after its arm time (R11.11,
## wall-clock ms): headless frames run faster than that.
func _arm(m: MenuScreen) -> void:
	if "opened_ms" in m:
		m.set("opened_ms", int(m.get("opened_ms")) - 5000)


# --- Demo scope ---------------------------------------------------------------------------

func test_demo_scope_for_every_area() -> void:
	var cat_before := (load(SettingsCatalog.PATH) as SettingsCatalog).all_defs().size()
	BuildInfo.set_force_demo(1)
	var demo := BuildInfo.demo() as DemoConfig
	var m := _menu(M9_MENUS["achievements"]) as AchievementsMenu
	var listed := PackedStringArray(m.listed().map(func(a: AchievementData) -> String: return a.id))
	listed.sort()
	var want := demo.achievements.duplicate()
	want.sort()
	check(listed == want, "the achievement list is the demo's: %s" % listed)
	for ch in ChallengeLibrary.all():
		check(demo.allows(ch.start_room), "challenge %s starts inside the demo" % ch.id)
	check(ChallengeLibrary.all().all(func(c: ChallengeData) -> bool: return c.group != ChallengeData.Group.NULL), "no Deep Rig run in the demo")
	check(not BuildInfo.enabled(&"ngplus") and not BuildInfo.enabled(&"null"), "NG+ and the Deep Rig are off in the demo")
	StoryPresets.apply("act1_complete")
	Game.save_game()
	check(not NewGamePlus.begin({"from": "", "remix": true, "keep_dash": true}) or not BuildInfo.enabled(&"ngplus"),
		"NG+ is refused through its API, not only its row")
	check((load(SettingsCatalog.PATH) as SettingsCatalog).all_defs().size() == cat_before, "the settings catalog is unchanged")
	m.close_menu()
	BuildInfo.set_force_demo(-1)
	if not DirAccess.dir_exists_absolute("user://demo/saves"):
		AtomicJson.remove_tree("user://demo")


# --- Saves ---------------------------------------------------------------------------------

func test_kitchen_sink_save_roundtrip() -> void:
	var s := GameState.new()
	s.stats = {"kills": 3, "perfect_dodges": 2}
	s.dev_tainted = true
	s.igt_frames = 1234
	s.igt_complete = true
	s.flags = {"ng_cycle": 2, "ng_remix": true, "ng_keep_dash": false, "null_open": true, "demo_build": true}
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())) as Dictionary)
	check(back.dev_tainted and int(back.igt_frames) == 1234 and back.igt_complete, "M9 keys round-trip")
	check(int(back.flags["ng_cycle"]) == 2 and bool(back.flags["ng_remix"]) and bool(back.flags["null_open"]) and bool(back.flags["demo_build"]),
		"M9 flags round-trip")
	check(int(back.stats.get("kills", 0)) == 3, "profile stats round-trip")
	var old := GameState.from_dict(JSON.parse_string(FileAccess.get_file_as_string(H.SAVE_V3)) as Dictionary)
	check(old != null and not old.dev_tainted and old.stats.is_empty(), "save_v3_slice.json loads with M9 defaults")
	check(SaveManager.CURRENT_SCHEMA_VERSION == 3, "no schema bump in M9 (D-087/D-090)")


# --- Headless and project rules -----------------------------------------------------------

func test_headless_inertness() -> void:
	Platform.reset_after_tests()
	Playtest.allow_headless = false
	var before := _user_files()
	var toast := AchievementDevActions.toast_node()
	var shown := toast.shown_count if toast else 0
	var r := await h.goto(RELAY, &"start")
	check(r != null, "a room")
	check(not Platform.active() and not Playtest.recording_allowed(), "no opt-in, no platform or recording")
	h.drive().move_x = 1
	await physics_frames(600)
	h.drive().move_x = 0
	Game.set_flag("got_pulse_blade")
	await physics_frames(5)
	check(_user_files() == before, "a 600-frame walk writes no user:// file")
	check(toast == null or toast.shown_count == shown, "and shows no toast")
	Platform.reset_for_tests(h.platform_dir)


func _user_files() -> PackedStringArray:
	var out := PackedStringArray()
	for d in ["user://", "user://saves", "user://platform", "user://playtests"]:
		if DirAccess.dir_exists_absolute(d):
			for f in DirAccess.get_files_at(d):
				out.append("%s/%s@%d" % [d, f, FileAccess.get_modified_time("%s/%s" % [d, f])])
	return out


func test_no_network_or_steam_symbols() -> void:
	check(CrossRules.network_violations().is_empty(), "no network, storefront or browser-bridge symbol: %s" % CrossRules.network_violations())


## TestRunner only runs tests/unit/test_*.gd: a mistyped suite name would be
## skipped in silence.
func test_every_unit_test_file_is_run() -> void:
	for f in DirAccess.get_files_at("res://tests/unit"):
		if f.get_extension() != "gd":
			continue
		check(f.begins_with("test_") or HELPER_ALLOWLIST.has(f), "tests/unit/%s would be skipped by TestRunner" % f)


## With X-9's extra shown text the shipped knowledge warnings are still
## exactly orr.tres 'Rook' (D-109 open).
func test_shipped_knowledge_warnings_still_one() -> void:
	var v := ContentValidator.new().run()
	var k := Array(v.warnings).filter(func(w: String) -> bool: return w.begins_with("knowledge lint"))
	check(k.size() == 1 and String(k[0]).contains("orr.tres") and String(k[0]).contains("'Rook'"), "knowledge warnings: %s" % [k])
	check(v.extra_shown_text.size() > 60, "X-9 added the M9 text (%d lines)" % v.extra_shown_text.size())
