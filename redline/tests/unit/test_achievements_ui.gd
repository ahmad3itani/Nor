extends RedlineTestCase
## M9 T07 achievement UI: the toast (held while the world is paused, a scene
## locks input, a memory plays or a transition runs; fade-only under flash
## reduction; silent when the setting is off; its rect clear of every HUD
## block at every UI size; shown after a run's result card), the
## Achievements menu (pages fit or scroll, focusable entries, ui_cancel backs
## out, no spoilers on a fresh profile, the demo filter, Records from the
## title reading the saved profile, no hidden stats), the Journal's
## "Achievements…" row and its round trip, and the dev page.

const H := preload("res://tests/fixtures/challenges/ChallengeHarness.gd")
const MENU_SCRIPT := "res://ui/menus/AchievementsMenu.gd"
const JOURNAL_SCRIPT := "res://ui/menus/JournalMenu.gd"
const VIEWPORT := Vector2(480, 270)
const NPCS := ["mara", "vell", "nix", "orr", "iko"]
## Names no fresh-profile row may show (bosses, NPCs, quests, set pieces).
const SPOILERS: PackedStringArray = ["Collector", "Krail", "Warden", "\\bOrr\\b", "Rainline", "Dead Air", "Way Up",
	"Relay", "Grid Clamp", "Lowlight", "New Game\\+"]

var h: H
var _extras: Array[Node] = []


func before_each() -> void:
	h = H.new(self, "achievements_ui")
	h.setup()
	Settings.achievement_toasts = true
	Settings.flash_reduction = false
	Settings.ui_scale = 0
	Settings.first_run = false
	UiTheme.invalidate()
	AchievementLibrary.clear_cache()
	_toast().clear()
	_extras.clear()
	await get_tree().process_frame


func after_each() -> void:
	for n in _extras:
		if is_instance_valid(n):
			if n is MenuScreen and (n as MenuScreen).is_open():
				(n as MenuScreen).close_menu()
			n.queue_free()
	_extras.clear()
	MenuHost.context = {}
	_toast().clear()
	SceneRouter.transitioning = false
	await h.teardown()
	Platform.reset_after_tests()
	UiTheme.invalidate()


func _toast() -> AchievementToast:
	return Platform.get_node("AchievementToast") as AchievementToast


func _menu(ctx: Dictionary = {}) -> AchievementsMenu:
	var m: AchievementsMenu = (load(MENU_SCRIPT) as GDScript).new()
	add_child(m)
	_extras.append(m)
	m.ctx = ctx
	m.open_menu()
	return m


func _journal() -> MenuScreen:
	var j: MenuScreen = (load(JOURNAL_SCRIPT) as GDScript).new()
	add_child(j)
	_extras.append(j)
	j.open_menu()
	return j


static func _texts(m: MenuScreen) -> PackedStringArray:
	var out := PackedStringArray()
	for c in m._body.find_children("*", "", true, false):
		if c is Label:
			out.append((c as Label).text)
		elif c is Button:
			out.append((c as Button).text)
	return out


static func _buttons(m: MenuScreen) -> Array[Button]:
	var out: Array[Button] = []
	for c in m._body.get_children():
		if c is Button:
			out.append(c as Button)
	return out


static func _button(m: MenuScreen, prefix: String) -> Button:
	for b in _buttons(m):
		if b.text.begins_with(prefix):
			return b
	return null


static func _has(texts: PackedStringArray, needle: String) -> bool:
	return Array(texts).any(func(t: String) -> bool: return t.contains(needle))


## Every list page's texts (the "More…" row pages through) and every
## entry's detail line (the footer shows it on focus).
func _all_list_texts(m: AchievementsMenu) -> PackedStringArray:
	var out := PackedStringArray()
	for p in m.page_count():
		m.list_page = p
		m.rebuild()
		out.append_array(_texts(m))
	m.list_page = 0
	m.rebuild()
	for a in m.filtered():
		out.append_array(m.entry_text(a))
	return out


func _save(flags: Dictionary, stats: Dictionary = {}) -> void:
	var d := GameState.new().to_dict()
	d["flags"] = flags
	d["stats"] = stats
	SaveManager.save_profile(1, d)


# --- Toast ----------------------------------------------------------------------------

func test_toast_held_while_locked_or_paused_then_shown() -> void:
	var toast := _toast()
	# Paused (a menu, the Act I card).
	get_tree().paused = true
	EventBus.achievement_unlocked.emit("krail_down", false)
	await physics_frames(3)
	check(not toast.showing() and not toast.visible and toast.queue.size() == 1, "held while paused")
	get_tree().paused = false
	await get_tree().process_frame
	await get_tree().process_frame
	check(toast.showing() and toast.lines()[1] == "Warden Down", "shown once unpaused (%s)" % [toast.lines()])
	toast.clear()
	# A locking scene.
	var fake := SequencePlayer.new()
	fake.locking = true
	var before: SequencePlayer = Cinematics.current
	Cinematics.current = fake
	EventBus.achievement_unlocked.emit("first_blade", false)
	await physics_frames(3)
	check(Cinematics.locks_input() and not toast.showing(), "held while a scene locks input")
	Cinematics.current = before
	fake.free()
	await physics_frames(2)
	check(toast.showing(), "shown after the scene")
	toast.clear()
	# A room transition.
	SceneRouter.transitioning = true
	EventBus.achievement_unlocked.emit("first_secret", false)
	await physics_frames(3)
	check(not toast.showing(), "held during a transition")
	SceneRouter.transitioning = false
	await physics_frames(2)
	check(toast.showing(), "shown after it")
	toast.clear()
	# A memory vignette.
	var mem := MemoryScenePlayer.new()
	var mem_before := MemoryScenePlayer.active_instance
	mem._phase = 1
	MemoryScenePlayer.active_instance = mem
	EventBus.achievement_unlocked.emit("intake_log", false)
	await physics_frames(3)
	check(mem.is_playing() and not toast.showing(), "held while a memory plays")
	MemoryScenePlayer.active_instance = mem_before
	mem.free()
	await physics_frames(2)
	check(toast.showing(), "shown after the memory")


func test_toast_flash_reduction_no_slide() -> void:
	var toast := _toast()
	EventBus.achievement_unlocked.emit("krail_down", false)
	await get_tree().process_frame
	await get_tree().process_frame
	check(toast.showing() and toast.slide_offset() < 0.0, "the toast slides in by default (%.1f)" % toast.slide_offset())
	toast.clear()
	Settings.flash_reduction = true
	EventBus.achievement_unlocked.emit("krail_down", false)
	await get_tree().process_frame
	await get_tree().process_frame
	check(toast.showing() and toast.slide_offset() == 0.0, "flash reduction: no slide")
	check(toast.alpha() < 1.0, "it fades in instead (%.2f)" % toast.alpha())


func test_toast_setting_off_silent_but_unlocked() -> void:
	var toast := _toast()
	Settings.achievement_toasts = false
	var before := toast.shown_count
	Game.set_flag("got_pulse_blade")
	await physics_frames(4)
	check(Platform.is_unlocked("first_blade"), "still unlocked")
	check(toast.queue.is_empty() and not toast.showing() and toast.shown_count == before, "nothing shown")
	var m := _menu()
	check(_has(_texts(m), "✓ Armed and Awake"), "and listed in the menu")


func _hud_rects(index: int) -> Dictionary:
	var f := Settings.config().ui_scale_factor(index)
	var hud := load("res://ui/hud/CombatHud.gd") as GDScript
	var content := {"max_health": 8, "injectors": 4, "core_label": "CORE 100  FLOW", "weapon": "Heavy Revolver",
		"ammo_max": 6, "scrap": "SCRAP 9999 +999", "boss_title": "WARDEN KRAIL", "staggered": true, "rank": "REDLINE"}
	var out := {}
	var layout: Dictionary = hud.call("element_rects", VIEWPORT / f, ThemeDB.fallback_font, content)
	for k: String in layout:
		var r: Rect2 = layout[k]
		out[k] = Rect2(r.position * f, r.size * f)
	return out


func test_toast_rect_clear_of_hud_bars() -> void:
	var screen := Rect2(Vector2.ZERO, VIEWPORT)
	for index in 3:
		var f := Settings.config().ui_scale_factor(index)
		var toast := AchievementToast.rect_for(VIEWPORT, f)
		check(screen.encloses(toast), "the toast is on screen at %.0f %% (%s)" % [f * 100.0, toast])
		var rects := _hud_rects(index)
		for k in ["health", "core", "weapon", "scrap", "boss"]:
			check(rects.has(k) and not toast.intersects(rects[k]), "clear of %s at %.0f %% (%s vs %s)" % [k, f * 100.0, toast, rects.get(k)])
	var native := AchievementToast.rect_for(VIEWPORT, 1.0)
	check(native == Rect2((VIEWPORT.x - 168.0) / 2.0, 6, 168, 30), "top centre 168 x 30 at native size (%s)" % native)


func test_toast_clear_of_style_block_and_run_timer_all_scales() -> void:
	var run_timer := Rect2(RunTimerHud.ORIGIN - Vector2(2, 1), RunTimerHud.BLOCK)
	for index in 3:
		var f := Settings.config().ui_scale_factor(index)
		var toast := AchievementToast.rect_for(VIEWPORT, f)
		var lv := VIEWPORT / f
		var style := Rect2(Vector2(lv.x - 70, 6) * f, Vector2(62, 34) * f)
		check(not toast.intersects(style), "clear of the style rank/meter at %.0f %% (%s vs %s)" % [f * 100.0, toast, style])
		check(not toast.intersects(_hud_rects(index)["rank"]), "clear of the drawn rank at %.0f %%" % (f * 100.0))
		check(not toast.intersects(run_timer), "clear of the run timer (IGT and in-run) at %.0f %%" % (f * 100.0))
	# The live toast uses the current UI size.
	Settings.ui_scale = 2
	UiTheme.invalidate()
	check(_toast().rect() == AchievementToast.rect_for(VIEWPORT, Settings.config().ui_scale_factor(2)), "rect() follows the UI size")


func test_run_unlock_toast_after_result_card() -> void:
	var toast := _toast()
	CinematicMode.theatre = true
	Challenges.force_active = true
	EventBus.challenge_started.emit("tt_market_run", 1)
	EventBus.challenge_finished.emit("tt_market_run", 0, 3000, 2, true)
	await physics_frames(3)
	check(Platform.is_unlocked("top_marks"), "a lifetime-only achievement unlocks in the run")
	check(not toast.showing() and toast.queue.is_empty(), "no toast over the run")
	Challenges.force_active = false
	Challenges.force_finishing = true
	await physics_frames(3)
	check(not toast.showing(), "none over the pending result card")
	Challenges.force_finishing = false
	CinematicMode.theatre = false
	await physics_frames(2)
	check(toast.showing() and toast.lines()[1] == "Top Marks", "shown once the card is gone (%s)" % [toast.lines()])


# --- Menu --------------------------------------------------------------------------------

func test_menu_pages_fit_270_or_scroll() -> void:
	Game.set_flag("null_open")
	for s in [0, 2]:
		Settings.ui_scale = s
		UiTheme.invalidate()
		var m := _menu()
		check(m.page_count() >= 2, "thirty rows need more than one page")
		for p in m.page_count():
			m.list_page = p
			m.rebuild()
			check(await panel_height(m) <= 270.0, "list page %d fits or scrolls at UI size %d" % [p + 1, s])
		m.show_hidden = true
		m.rebuild()
		check(await panel_height(m) <= 270.0, "hidden details fit at UI size %d" % s)
		m.show_records()
		check(await panel_height(m) <= 270.0, "records fit at UI size %d" % s)
		if s == 0:
			m.show_list()
			var full: float = await content_height(m)
			check(m._scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER,
				"at 100 %% the list page (with its detail footer) needs no scrolling (rows %.0f px)" % full)
		m.close_menu()


func test_entries_focusable_and_cancel_backs_out() -> void:
	var m := _menu()
	var buttons := _buttons(m)
	check(buttons.size() >= m.rows_per_page() + 3, "filter, entries, More, Records, Back")
	for b in buttons:
		check(b.focus_mode == Control.FOCUS_ALL, "'%s' is focusable" % b.text)
	var f := m.get_viewport().gui_get_focus_owner() as Button
	check(f != null and f == buttons[m.first_entry_index()], "focus starts on the first entry")
	var first := m.filtered()[0]
	check(m._footer.visible and m._footer.text == m.entry_text(first)[1], "its detail shows under the list (%s)" % m._footer.text)
	var rec := _button(m, "Records")
	rec.grab_focus()
	rec.pressed.emit()
	check(m.page == &"records", "Records opens")
	await press_action(&"ui_cancel", 1)
	check(m.is_open() and m.page == &"list", "ui_cancel on Records returns to the list")
	var back_focus := m.get_viewport().gui_get_focus_owner() as Button
	check(back_focus != null and back_focus.text == "Records…", "on the Records row")
	await press_action(&"ui_cancel", 1)
	check(not m.is_open(), "ui_cancel on the list closes")
	# The filter row cycles with confirm and left/right.
	m.open_menu()
	var filter := _buttons(m)[0]
	filter.pressed.emit()
	check(m.filter == AchievementsMenu.Filter.UNLOCKED, "confirm cycles the filter")
	check(_has(_texts(m), "Nothing here yet."), "an empty filter says so, neutrally")


func test_fresh_profile_menus_have_no_spoilers() -> void:
	var m := _menu()
	var texts := _all_list_texts(m)
	for pattern in SPOILERS:
		var re := RegEx.create_from_string(pattern)
		for t in texts:
			check(re.search(t) == null, "a fresh profile's list shows no '%s': %s" % [pattern, t])
	check(_has(texts, "???"), "guarded rows read ???")
	# Once the Collector's intro is seen, its rows are revealed.
	Game.set_flag("collector_drone_intro_seen")
	check(_has(_all_list_texts(m), "Defeat the Collector Drone."), "revealed after the meeting")


func test_demo_filter_lists_only_demo_ids() -> void:
	BuildInfo.set_force_demo(1)
	var demo := BuildInfo.demo()
	check(demo != null, "a demo config")
	if demo == null:
		return
	var old: PackedStringArray = demo.get("achievements")
	demo.set("achievements", PackedStringArray(["first_blade", "first_secret"]))
	Platform.dev_unlock("krail_down")
	var m := _menu()
	var ids := m.listed().map(func(a: AchievementData) -> String: return a.id)
	check(ids == ["first_blade", "krail_down", "first_secret"], "the demo's own plus the unlocked ones (%s)" % [ids])
	check(_has(_texts(m), "ACHIEVEMENTS  1 / 3"), "the header counts the demo list: %s" % [_texts(m)])
	demo.set("achievements", old)
	BuildInfo.set_force_demo(-1)


func test_records_hides_unshown_stats() -> void:
	Game.state.deaths = 12
	var m := _menu()
	m.show_records()
	var ids := m.record_stats().map(func(d: StatDef) -> StringName: return d.id)
	check(not ids.has(&"deaths"), "deaths is never listed (R07.9)")
	check(not _has(_texts(m), "Deaths") and not _has(_texts(m), "deaths"), "no death line on Records")
	check(ids.has(&"kills") and ids.has(&"play_time"), "the shown stats are")
	check(not ids.has(&"boss_time_warden_krail"), "boss rows wait for the meeting")


func test_title_records_read_saved_profile_stats() -> void:
	_save({"act1_complete": true}, {"kills": 7.0})
	Game.state.stats["kills"] = 99.0
	var m := _menu({"from": "title"})
	m.show_records()
	var kills := StatCatalog.shipped().stat(&"kills")
	check(m.value_text(kills, false) == "7", "This save reads the saved profile (%s)" % m.value_text(kills, false))
	check(m.value_text(kills, true) == "0", "All time reads the platform store")
	var fresh := _menu()
	fresh.show_records()
	check(fresh.value_text(kills, false) == "99", "in play it reads the live profile")


func test_records_from_title_reads_peeked_save_after_rebuild() -> void:
	_save({}, {"kills": 5.0})
	var m := _menu({"from": "title"})
	m.show_records()
	m.rebuild()
	var kills := StatCatalog.shipped().stat(&"kills")
	check(m.value_text(kills, false) == "5", "still the saved profile after a rebuild")
	m.show_list()
	m.show_records()
	check(m.value_text(kills, false) == "5", "and after list -> records")
	check(_has(_texts(m), "RECORDS"), "the Records page")


func test_achievements_back_from_title_focuses_title() -> void:
	var host := await h.boot_main("")
	var title: MenuScreen = host.title
	check(title.is_open(), "the title is up")
	var row := _button(title, "Achievements")
	check(row != null, "the title lists Achievements")
	if row == null:
		return
	row.grab_focus()
	row.pressed.emit()
	var m := host.screen(&"achievements") as AchievementsMenu
	check(m != null and m.is_open() and m.from_title(), "the menu opens with the title context (%s)" % [m.ctx if m else null])
	m.rebuild()
	check(m.from_title(), "ctx survives a rebuild")
	# ui_cancel is ignored on the frame a menu opens.
	await get_tree().process_frame
	await press_action(&"ui_cancel", 1)
	await get_tree().process_frame
	check(not m.is_open(), "Back closes it")
	var f := title.get_viewport().gui_get_focus_owner() as Button
	check(f != null and f.text == "Achievements", "the title row has focus again (%s)" % [f.text if f else null])


# --- Journal ------------------------------------------------------------------------------

func test_journal_achievements_button_opens() -> void:
	var requests: Array = []
	var spy := func(id: StringName) -> void: requests.append([id, MenuHost.context.duplicate()])
	EventBus.menu_requested.connect(spy)
	var j := _journal()
	var b := _button(j, "Achievements")
	check(b != null, "the Journal has an Achievements… row")
	if b != null:
		b.grab_focus()
		var row := j.focused_index()
		b.pressed.emit()
		check(not j.is_open(), "the Journal closes first")
		check(requests.size() == 1 and requests[0][0] == &"achievements", "then asks for the menu (%s)" % [requests])
		if requests.size() == 1:
			var ctx: Dictionary = requests[0][1]
			check(ctx.get("return_to") == &"journal" and int(ctx.get("row", -1)) == row, "with the return point (%s)" % [ctx])
	EventBus.menu_requested.disconnect(spy)
	MenuHost.context = {}


func test_journal_button_roundtrip_keeps_row() -> void:
	var host := await h.boot_main(H.WORLD_A)
	EventBus.menu_requested.emit(&"journal")
	var j := host.screen(&"journal")
	check(j.is_open(), "the Journal opens")
	var b := _button(j, "Achievements")
	check(b != null, "with its Achievements… row")
	if b == null:
		return
	b.grab_focus()
	var row := j.focused_index()
	b.pressed.emit()
	var m := host.screen(&"achievements") as AchievementsMenu
	check(m.is_open() and m.returns_to_journal(), "Achievements opens from the Journal")
	check(get_tree().paused, "the world stays paused")
	await get_tree().process_frame
	await press_action(&"ui_cancel", 1)
	check(not m.is_open() and j.is_open(), "Back reopens the Journal")
	check(j.focused_index() == row, "on the same row (%d vs %d)" % [j.focused_index(), row])
	j.close_menu()
	check(not get_tree().paused, "closing the Journal resumes play")


func test_journal_main_fits_270() -> void:
	for q in Game.quests.quests:
		Game.set_flag(q.start_flag)
	Game.set_flag("dead_air_complete")
	MemoryLibrary.dev_grant_all_fragments()
	for npc: String in NPCS:
		Game.set_flag("met_%s" % npc)
	Game.set_flag("warden_krail_defeated")
	Game.set_flag("arcbeat_iko_met")
	Game.set_flag("act1_complete")
	var j := _journal()
	check(_button(j, "People…") != null and _button(j, "Achievements…") != null, "every optional row is there")
	var height: float = await menu_height(j)
	check(height <= 270.0, "the fullest Journal still fits (%.0f px)" % height)


# --- Dev ------------------------------------------------------------------------------------

func test_dev_page_fits_and_paginates() -> void:
	var console: DevConsole = (load("res://ui/menus/DevConsole.gd") as GDScript).new()
	add_child(console)
	_extras.append(console)
	console.open_menu()
	console.go(&"ach")
	var texts := _texts(console)
	check(_has(texts, "Unlock all achievements") and _has(texts, "Evaluate now") and _has(texts, "Test toast"), "the tool rows: %s" % [texts])
	check(_has(texts, "More…"), "thirty achievement rows paginate")
	check(await panel_height(console) <= 270.0, "the page fits")
	_button(console, "More…").pressed.emit()
	check(_has(_texts(console), "] The Way Up") and not _has(_texts(console), "] Armed and Awake"), "the next page lists the next achievements: %s" % [_texts(console)])
	console.list_page = 0
	console._refresh()
	# Toggle one row, then reset with two presses.
	_button(console, "Unlock all").pressed.emit()
	check(Platform.unlocked_ids().size() == 30, "unlock all")
	_button(console, "Reset achievements").pressed.emit()
	check(Platform.unlocked_ids().size() == 30 and AchievementDevActions.reset_armed, "the first reset press only arms")
	_button(console, "Reset achievements").pressed.emit()
	check(Platform.unlocked_ids().is_empty() and not AchievementDevActions.reset_armed, "the second clears everything")
	check(AchievementDevActions.test_toast("krail_down") and _toast().queue.has("krail_down"), "the test toast queues without unlocking")
	check(not Platform.is_unlocked("krail_down"), "and writes nothing")
