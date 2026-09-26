extends RedlineTestCase
## The Challenges UI (M9 T08, D2 §6, R08.1-R08.12): the list (locked rows
## focusable, masked until revealed, the Deep Rig block only once null_open
## holds), the detail page (board pages, neutral tags, the ghost cycler,
## Start's return point from ctx), the "How ranks work" page, the result
## card (Retry focused, reset retries, cancel goes back to the list, armed
## confirm, never a frozen exit), the Relay training rig terminal and the
## run's pause rows; medal names always come from RankLadder.

const H := preload("res://tests/fixtures/challenges/ChallengeHarness.gd")
const RELAY := "res://world/rooms/lowlight/Relay.tscn"
const LIST_SCRIPT := "res://ui/menus/ChallengesMenu.gd"
const CARD_SCRIPT := "res://ui/menus/ChallengeResultMenu.gd"
const STYLE_LETTERS: PackedStringArray = ["D", "C", "B", "A", "S", "SS", "SSS"]

var h: H
var _menus: Array[Node] = []
var _requests: Array = []


func before_each() -> void:
	h = H.new(self, "challenges_menu")
	h.setup()
	ChallengeLibrary.data_dir = ChallengeLibrary.DEFAULT_DIR
	ChallengeLibrary.clear_cache()
	_menus.clear()
	_requests.clear()


func after_each() -> void:
	for m in _menus:
		if is_instance_valid(m):
			if m is MenuScreen and (m as MenuScreen).is_open():
				(m as MenuScreen).close_menu()
			m.queue_free()
	_menus.clear()
	_arm(400)
	MenuHost.context = {}
	await h.teardown()


static func _arm(ms: int) -> void:
	ChallengeResultMenu.arm_ms = ms


func _list(ctx: Dictionary = {}, parent: Node = null) -> MenuScreen:
	var m: MenuScreen = (load(LIST_SCRIPT) as GDScript).new()
	(parent if parent else self).add_child(m)
	_menus.append(m)
	m.ctx = ctx
	m.open_menu()
	return m


func _card(result: Dictionary, parent: Node = null) -> MenuScreen:
	var m: MenuScreen = (load(CARD_SCRIPT) as GDScript).new()
	(parent if parent else self).add_child(m)
	_menus.append(m)
	m.ctx = {"result": result}
	m.open_menu()
	return m


static func _texts(m: MenuScreen) -> PackedStringArray:
	var out := PackedStringArray()
	for c in m._body.get_children():
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


func _focused(m: MenuScreen) -> Button:
	var f := m.get_viewport().gui_get_focus_owner()
	return f as Button


func _unlock_all() -> void:
	StoryPresets.apply("act1_complete")
	Game.set_flag("chase_rainline_done")


func _finished(ch: ChallengeData, value: int, medal: int, extra: Dictionary = {}) -> Dictionary:
	var r := {"challenge": ch.id, "profile": 1, "outcome": ChallengeData.Outcome.FINISHED, "value": value, "medal": medal,
		"new_best": false, "prev_best": -1, "rank": 1, "attempt": 1, "tags": {}, "date": "2026-09-26T10:00:00",
		"cause": "", "stages": [], "score_kind": ch.score_kind, "title": ch.title, "frames": value, "splits": []}
	r.merge(extra, true)
	return r


## Starts `ch` as the Relay terminal would (ctx return point) and waits for
## the run room.
func _run_from_relay(ch: ChallengeData) -> bool:
	await h.goto(RELAY, &"challenges")
	return await h.start(ch, {"room": RELAY, "entry": &"challenges"})


# --- List --------------------------------------------------------------------------

func test_list_locked_rows_focusable_with_hint() -> void:
	Game.set_flag("collector_drone_intro_seen")
	var m := _list()
	var row := _button(m, "Locked — ")
	check(row != null, "a revealed locked row reads 'Locked — <hint>': %s" % [_texts(m)])
	if row == null:
		return
	check(row.text == "Locked — Defeat the Collector Drone.", "the hint is the neutral locked_hint (%s)" % row.text)
	check(row.disabled, "a locked row is disabled")
	check(row.focus_mode == Control.FOCUS_ALL, "a locked row keeps focus mode ALL")
	row.grab_focus()
	await get_tree().process_frame
	check(row.has_focus(), "a pad user can focus the locked row to read it")
	check(_has(_texts(m), "Profile 1 · medals 0 / 40"), "header counts 10 challenges × 4 medals: %s" % [_texts(m)])


func test_locked_rows_masked_until_revealed() -> void:
	var m := _list()
	var texts := _texts(m)
	check(not _has(texts, "Collector") and not _has(texts, "Krail") and not _has(texts, "Rainline"),
		"no boss or set piece is named before its reveal: %s" % [texts])
	check(Array(texts).count("???") == 10, "every locked, unrevealed row reads ??? (%s)" % [texts])
	check(_has(texts, "Boss Rematch") and _has(texts, "Time Trial") and _has(texts, "Nerve"), "the group names still show")
	Game.set_flag("collector_drone_intro_seen")
	m.rebuild()
	texts = _texts(m)
	check(Array(texts).count("Locked — Defeat the Collector Drone.") == 2, "both Collector rows reveal their hint (%s)" % [texts])
	check(not _has(texts, "Krail"), "Krail stays masked")


func test_null_group_hidden_until_null_open() -> void:
	ChallengeLibrary.data_dir = H.FIXTURES
	ChallengeLibrary.clear_cache()
	var m := _list()
	check(not _has(_texts(m), "Deep Rig"), "no Deep Rig block before null_open: %s" % [_texts(m)])
	Game.set_flag("act1_complete")
	check(Game.has_flag("null_open"), "act1_complete derives null_open")
	m.rebuild()
	check(_has(_texts(m), "Deep Rig"), "the Deep Rig block shows once null_open holds: %s" % [_texts(m)])
	check(not _has(_texts(m), "Depth reached"), "no depth line yet")
	Game.set_flag("null_depth_reached")
	m.rebuild()
	check(_has(_texts(m), "Depth reached"), "the header adds 'Depth reached'")
	var labels := Array(_texts(m))
	check(labels.find("Deep Rig") < labels.find("Boss Rematch"), "the Deep Rig block comes first (group order)")


# --- Detail ------------------------------------------------------------------------

func test_detail_board_paginates() -> void:
	_unlock_all()
	var ch := ChallengeLibrary.by_id("tt_neon_roofs")
	for i in 8:
		Challenges.records.submit(ch, 1, 1500 + i * 30, ChallengeData.Outcome.FINISHED)
	var m := _list()
	m.call("show_detail", ch)
	var texts := _texts(m)
	for i in range(1, 6):
		check(_has(texts, "%d. P1" % i), "page 1 shows row %d: %s" % [i, texts])
	check(not _has(texts, "6. P1"), "page 1 stops at 5 rows")
	check(_has(texts, "Bronze 0:46 · Silver 0:32.50 · Gold 0:26"), "medal targets read Bronze/Silver/Gold: %s" % [texts])
	check(_has(texts, "Redline 0:19") and _has(texts, "Beat the rig ghost's time"), "the Redline line names the rig ghost")
	check(_focused(m) != null and _focused(m).text == "Start", "Start has focus on the detail page")
	var more := _button(m, "More…")
	check(more != null, "a More… row pages the board")
	if more:
		more.pressed.emit()
		texts = _texts(m)
		check(_has(texts, "6. P1") and _has(texts, "8. P1") and not _has(texts, "1. P1"), "page 2 shows rows 6-8: %s" % [texts])


func test_board_tags_neutral() -> void:
	_unlock_all()
	var ch := ChallengeLibrary.by_id("tt_neon_roofs")
	Challenges.records.submit(ch, 1, 1500, ChallengeData.Outcome.FINISHED, PackedInt32Array(), {"assists": ["damage_assist"], "timing": []})
	Challenges.records.submit(ch, 1, 1600, ChallengeData.Outcome.FINISHED, PackedInt32Array(), {"assists": [], "timing": [Challenges.TAG_HITSTOP]})
	Challenges.records.submit(ch, 1, 1700, ChallengeData.Outcome.FINISHED)
	var m := _list()
	m.call("show_detail", ch)
	var texts := _texts(m)
	check(_has(texts, "1. P1") and _has(texts, "◇ assist"), "an assisted run carries the neutral glyph and word: %s" % [texts])
	check(_has(texts, "◇ reduced hitstop"), "the hitstop tag has its own word")
	check(not Array(texts).any(func(t: String) -> bool: return t.to_lower().contains("easy")), "never 'easy'")
	for row in texts:
		if row.begins_with("3. P1"):
			check(not row.contains("◇"), "an untagged run has no tag")
	for e: Dictionary in Challenges.records.board(ch.id):
		for w in ChallengesMenu.tag_words(e):
			check(w in ["assist", "reduced hitstop"], "tag words come from the neutral list (%s)" % w)
	check(Challenges.records.board(ch.id).size() == 3, "assisted runs stay on the same board (no filter)")


func test_rank_page_text() -> void:
	ChallengeLibrary.data_dir = H.FIXTURES
	ChallengeLibrary.clear_cache()
	var ch := ChallengeLibrary.by_id("fx_staged")
	var m := _list()
	m.call("show_detail", ch)
	var texts := _texts(m)
	check(_has(texts, "Core mode never changes your rank"), "the RANK detail page carries the Core note")
	check(not _has(texts, "Ghost:"), "no ghost cycler for a RANK run without ghosts")
	var how := _button(m, "How ranks work")
	check(how != null, "a 'How ranks work' row")
	if how == null:
		return
	how.pressed.emit()
	texts = _texts(m)
	var lines := ChallengesMenu.rank_lines()
	check(lines.size() == 4, "four rank rules (time, damage, style, top tier)")
	for line in lines:
		check(Array(texts).has(line), "the page shows '%s'" % line)
	check(_has(texts, "Core mode never changes your rank"), "the page ends with the Core note")
	check(lines[3].begins_with("Redline:"), "the top-tier rule is named from RankLadder (%s)" % lines[3])


func test_challenges_menu_start_uses_title_return_to() -> void:
	_unlock_all()
	var m := _list({"from": "title"})
	m.rebuild()
	var ch := ChallengeLibrary.by_id("tt_neon_roofs")
	m.call("show_detail", ch)
	m.rebuild()
	var start := _button(m, "Start")
	check(start != null and not start.disabled, "an unlocked detail page has Start")
	start.pressed.emit()
	check(Challenges.active(), "Start begins the run")
	check(Challenges.session != null and Challenges.session.return_to == {"title": true}, "a title start returns to the title (%s)" % [Challenges.session.return_to if Challenges.session else null])
	check(not m.is_open(), "the list closed first")
	await h.until(func() -> bool: return Challenges.phase() == Challenges.Phase.RUNNING and not SceneRouter.transitioning)
	Challenges.reset_for_tests()
	ChallengeLibrary.data_dir = ChallengeLibrary.DEFAULT_DIR
	ChallengeLibrary.clear_cache()
	# The rig's context gives its room and spawn.
	_unlock_all()
	var r := _list({"room": RELAY, "entry": &"challenges"})
	check(r.call("return_to") == {"room": RELAY, "entry": &"challenges"}, "a rig start returns to the rig spawn (%s)" % [r.call("return_to")])


func test_title_start_loads_profile_without_playtest_session() -> void:
	var host := h.make_host()
	var d := GameState.new().to_dict()
	d["flags"] = {"act1_complete": true, "chase_rainline_done": true, "collector_drone_defeated": true}
	SaveManager.save_profile(1, d)
	Playtest.end_session("test")
	Challenges.open_from_title()
	check(Game.has_flag("chase_rainline_done"), "the title row loads the profile")
	check(Playtest.session == null, "no playtest session begins")
	var opened: Array = host.get("opened")
	check(opened.size() == 1 and opened[0][0] == &"challenges", "the list opens (%s)" % [opened])
	if opened.size() != 1:
		return
	var m := _list(opened[0][1])
	m.call("show_detail", ChallengeLibrary.by_id("tt_neon_roofs"))
	_button(m, "Start").pressed.emit()
	check(Challenges.active() and Challenges.session.return_to == {"title": true}, "the run returns to the title")
	check(Playtest.session == null, "still no playtest session in the run")


# --- Terminal ---------------------------------------------------------------------

func _terminal() -> ChallengeTerminal:
	return h.room().find_child("ChallengeTerminal", true, false) as ChallengeTerminal


func test_terminal_dark_until_unlocked() -> void:
	Game.set_flag("act1_complete")
	var room := await h.goto(RELAY, &"challenges")
	var t := _terminal()
	check(t != null, "the Relay has the training rig")
	if t == null:
		return
	check_near(t.position.x, 740.0, 0.1, "the rig stands at x 740")
	check(t.visible and not t.is_lit(), "rig open, nothing unlocked: drawn dark")
	check(not t.can_interact(room.player), "no prompt while dark")
	Game.set_flag("collector_drone_defeated")
	check(t.is_lit() and t.can_interact(room.player), "an unlock lights it")
	check(t.prompt_text() == "Training rig", "a lore-free prompt (%s)" % t.prompt_text())
	h.listen(EventBus.menu_requested, func(id: StringName) -> void: _requests.append([id, MenuHost.context.duplicate()]))
	t.interact(room.player)
	check(_requests.size() == 1 and _requests[0][0] == &"challenges", "interact opens the Challenges list (%s)" % [_requests])
	if _requests.size() == 1:
		check(_requests[0][1] == {"room": RELAY, "entry": &"challenges"}, "with the Relay's rig spawn as the return point (%s)" % [_requests[0][1]])


func test_terminal_hidden_before_act1_close() -> void:
	Game.set_flag("collector_drone_defeated")
	Game.set_flag("met_orr")
	var room := await h.goto(RELAY, &"challenges")
	var t := _terminal()
	check(t != null and not t.visible, "before the Act I close the rig is not drawn")
	check(t != null and not t.can_interact(room.player), "and has no prompt")
	await physics_frames(2)
	check(t != null and not t.monitorable, "and is not interactable")
	# The title row follows the same rule.
	var d := Game.state.to_dict()
	SaveManager.save_profile(1, d)
	check(not _title_has_challenges(), "the title has no Challenges row before the Act I close")
	Game.set_flag("act1_complete")
	check(t.visible and t.is_lit(), "the Act I close shows the rig, lit (a rematch is unlocked)")
	SaveManager.save_profile(1, Game.state.to_dict())
	check(_title_has_challenges(), "and the title row appears")


## A TitleMenu under a host that has every screen.
func _title_has_challenges() -> bool:
	var src := GDScript.new()
	src.source_code = "extends Node\nfunc has_screen(_id: StringName) -> bool:\n\treturn true\nfunc open_with(_id: StringName, _ctx: Dictionary) -> void:\n\tpass\n"
	src.reload()
	var host: Node = src.new()
	add_child(host)
	var title: MenuScreen = (load("res://ui/menus/TitleMenu.gd") as GDScript).new()
	host.add_child(title)
	title.open_menu()
	var has := _has(_texts(title), "Challenges")
	host.queue_free()
	return has


# --- Pause ---------------------------------------------------------------------------

func test_pause_rows_in_challenge() -> void:
	_unlock_all()
	check(await _run_from_relay(ChallengeLibrary.by_id("tt_neon_roofs")), "the run starts")
	var p: MenuScreen = (load("res://ui/menus/PauseMenu.gd") as GDScript).new()
	add_child(p)
	_menus.append(p)
	p.open_menu()
	var texts := _texts(p)
	for want in ["Resume", "Restart", "Ghost: ", "Settings", "Quit challenge"]:
		check(_has(texts, want), "run pause has '%s': %s" % [want, texts])
	for never in ["Map", "Journal", "Save & Quit to Title"]:
		check(not Array(texts).has(never), "run pause never shows '%s'" % never)
	p.close_menu()


# --- Result card -----------------------------------------------------------------

func test_result_card_retry_focused_and_reset_works() -> void:
	_unlock_all()
	var ch := ChallengeLibrary.by_id("tt_neon_roofs")
	check(await _run_from_relay(ch), "the run starts")
	Challenges.finish(ChallengeData.Outcome.FINISHED)
	var card := _card(Challenges.last_result.duplicate(true))
	check(_focused(card) != null and _focused(card).text == "Retry", "Retry has focus")
	_arm(0)
	await get_tree().process_frame
	await get_tree().process_frame
	var attempt := Challenges.attempt()
	await press_action(&"reset", 1)
	await physics_frames(3)
	check(not card.is_open(), "reset closes the card")
	check(Challenges.active() and Challenges.phase() == Challenges.Phase.RUNNING, "reset retries at once")
	check(Challenges.attempt() == attempt + 1, "a new attempt (%d -> %d)" % [attempt, Challenges.attempt()])


func test_result_confirm_armed() -> void:
	_unlock_all()
	var ch := ChallengeLibrary.by_id("tt_neon_roofs")
	check(await _run_from_relay(ch), "the run starts")
	Challenges.finish(ChallengeData.Outcome.FINISHED)
	# A jump held through the finish line.
	Input.action_press(&"jump")
	var card := _card(Challenges.last_result.duplicate(true))
	_arm(0)
	for i in 3:
		await get_tree().process_frame
	check(not card.call("confirm_armed"), "a held jump keeps the card unarmed")
	_button(card, "Retry").pressed.emit()
	check(card.is_open() and Challenges.phase() != Challenges.Phase.RUNNING, "a press before the jump is released never retries")
	Input.action_release(&"jump")
	_arm(60000)
	await get_tree().process_frame
	check(not card.call("confirm_armed"), "the real-time arm delay also holds it")
	_arm(0)
	check(card.call("confirm_armed"), "released and past the delay: armed")
	_button(card, "Retry").pressed.emit()
	await physics_frames(3)
	check(not card.is_open() and Challenges.phase() == Challenges.Phase.RUNNING, "now Retry retries")


func test_result_cancel_returns_to_list() -> void:
	_unlock_all()
	Game.save_game()
	var host := await h.boot_main(RELAY)
	await physics_frames(5)
	_arm(0)
	var ch := ChallengeLibrary.by_id("tt_neon_roofs")
	check(await h.start(ch, {"room": RELAY, "entry": &"challenges"}), "the run starts from the rig")
	Challenges.finish(ChallengeData.Outcome.FINISHED)
	var card := host.screen(&"challenge_result")
	check(await h.until(func() -> bool: return card.is_open(), 200), "the result card opens")
	await get_tree().process_frame
	await get_tree().process_frame
	await press_action(&"ui_cancel", 1)
	var list := host.screen(&"challenges")
	check(await h.until(func() -> bool: return list.is_open(), 400), "ui_cancel leads back to the Challenges list")
	check(not Challenges.active(), "the run is over")
	check(SceneRouter.current_room_path == RELAY, "Rook is back at the Relay (%s)" % SceneRouter.current_room_path)
	var p := h.player()
	if p:
		check(p.global_position.distance_to(Vector2(700, 0)) < 2.0, "at the rig spawn (%s)" % p.global_position)
	check(list.call("return_to") == {"room": RELAY, "entry": &"challenges"}, "the list keeps the rig return point")
	list.close_menu()


func test_no_frozen_exit_from_result() -> void:
	_unlock_all()
	var ch := ChallengeLibrary.by_id("tt_neon_roofs")
	var host := h.make_host()
	for way in ["retry", "back", "quit", "cancel"]:
		check(await _run_from_relay(ch), "%s: the run starts" % way)
		Challenges.finish(ChallengeData.Outcome.FINISHED)
		var card := _card(Challenges.last_result.duplicate(true), host)
		_arm(0)
		await get_tree().process_frame
		await get_tree().process_frame
		match way:
			"retry":
				_button(card, "Retry").pressed.emit()
			"back":
				_button(card, "Back to Challenges").pressed.emit()
			"quit":
				_button(card, "Quit challenge").pressed.emit()
			"cancel":
				await press_action(&"ui_cancel", 1)
		await physics_frames(10)
		check(not card.is_open(), "%s: the card closed" % way)
		var p := h.player()
		if Challenges.active():
			check(Challenges.phase() == Challenges.Phase.RUNNING, "%s: an active run is live again" % way)
			check(p != null and not p.cinematic_lock and p.input_override == null, "%s: the retried player is not frozen" % way)
		else:
			check(p != null and not p.cinematic_lock, "%s: back in the world, Rook is free (%s)" % [way, SceneRouter.current_room_path])
		if way == "back" or way == "cancel":
			var opened: Array = host.get("opened")
			check(not opened.is_empty() and opened.back()[0] == &"challenges", "%s: the list reopens (%s)" % [way, opened])
		if Challenges.active():
			Challenges.reset_for_tests()
			Challenges.records.reload()
		card.queue_free()
		await physics_frames(2)


func test_result_card_keeps_result_after_ghost_cycle() -> void:
	var ch := ChallengeLibrary.by_id("tt_neon_roofs")
	var card := _card(_finished(ch, 1234, 2))
	_arm(0)
	await get_tree().process_frame
	await get_tree().process_frame
	var t := RunClock.format(1234)
	check(_has(_texts(card), t) and _has(_texts(card), "Silver"), "the card shows the time and tier: %s" % [_texts(card)])
	var mode := Settings.challenge_ghost
	_button(card, "Ghost: ").pressed.emit()
	check(Settings.challenge_ghost != mode, "the ghost row cycles the mode")
	check(_has(_texts(card), t) and _has(_texts(card), "Silver"), "the rebuilt card still shows the result: %s" % [_texts(card)])
	check(int((card.ctx["result"] as Dictionary)["value"]) == 1234, "ctx.result is untouched")


func test_no_style_letters_in_challenge_ui() -> void:
	_unlock_all()
	var texts := PackedStringArray()
	var ch := ChallengeLibrary.by_id("tt_neon_roofs")
	for medal in range(0, 5):
		Challenges.records.submit(ch, 1, ch.medal_thresholds[3] + (4 - medal) * 600, ChallengeData.Outcome.FINISHED)
		var card := _card(_finished(ch, 900 + medal * 10, medal, {"new_best": true, "prev_best": 1200}))
		texts.append_array(_texts(card))
		card.close_menu()
	var failed := _finished(ch, -1, -1, {"outcome": ChallengeData.Outcome.FAILED_HIT, "cause": RuleWatch.cause_line("")})
	var fcard := _card(failed)
	var ftexts := _texts(fcard)
	check(_has(ftexts, "Run over: hit taken"), "a failure names its cause neutrally: %s" % [ftexts])
	var cause_label: Label = null
	for c in fcard._body.get_children():
		if c is Label and (c as Label).text.begins_with("Run over"):
			cause_label = c
	check(cause_label != null and cause_label.get_theme_color("font_color") == UiTheme.label_color(UiTheme.MUTED), "the cause is muted, never red")
	texts.append_array(ftexts)
	fcard.close_menu()
	var m := _list()
	texts.append_array(_texts(m))
	for c in ChallengeLibrary.all():
		m.call("show_detail", c)
		texts.append_array(_texts(m))
	check(_has(texts, "Clear"), "tier 0 reads 'Clear'")
	for t in texts:
		check(not t.contains("— C") and not t.contains(" S medal") and not t.contains("Cleared — "), "no style-letter medal text: '%s'" % t)
		for tok in t.split(" ", false):
			check(not STYLE_LETTERS.has(tok), "no bare style letter used as a medal: '%s'" % t)
	for path in DataDir.list("res://data/challenges"):
		var src := FileAccess.get_file_as_string(path)
		check(not src.contains("— C") and not src.contains(" S medal") and not src.contains("Cleared — "), "%s has no style-letter medal text" % path.get_file())


func test_menus_fit_270_or_scroll_at_ui_scales() -> void:
	_unlock_all()
	var ch := ChallengeLibrary.by_id("tt_neon_roofs")
	for i in 10:
		Challenges.records.submit(ch, 1, 1500 + i * 30, ChallengeData.Outcome.FINISHED, PackedInt32Array(), {"assists": ["damage_assist"], "timing": [Challenges.TAG_HITSTOP]})
	for s in 3:
		Settings.ui_scale = s
		UiTheme.invalidate()
		var m := _list()
		check(await panel_height(m) <= 270.0, "list fits or scrolls at UI scale %d" % s)
		m.call("show_detail", ch)
		check(await panel_height(m) <= 270.0, "detail fits or scrolls at UI scale %d" % s)
		m.close_menu()
		var card := _card(_finished(ch, 1500, 3, {"new_best": true, "prev_best": 1600}))
		check(await panel_height(card) <= 270.0, "the result card fits or scrolls at UI scale %d" % s)
		card.close_menu()


# --- Dev page ----------------------------------------------------------------------

func test_dev_page_starts_finishes_and_fails() -> void:
	var ch := ChallengeLibrary.by_id("tt_neon_roofs")
	check(ChallengeDevActions.value_for_tier(ch, 0) > ch.medal_thresholds[0], "the Clear value is slower than Bronze")
	for tier in range(1, 5):
		check(ch.medal_for(ChallengeDevActions.value_for_tier(ch, tier)) == tier, "value_for_tier(%d) earns tier %d" % [tier, tier])
	await h.goto(RELAY, &"challenges")
	check(ChallengeDevActions.start("tt_neon_roofs"), "a dev start ignores unlocks (nothing is unlocked here)")
	check(await h.until(func() -> bool: return Challenges.phase() == Challenges.Phase.RUNNING and not SceneRouter.transitioning), "the run goes live")
	check(Challenges.session.return_to.get("room", "") == RELAY, "a dev start from a world room returns there")
	var console: DevConsole = (load("res://ui/menus/DevConsole.gd") as GDScript).new()
	add_child(console)
	_menus.append(console)
	console.open_menu()
	console.go(&"chal")
	check(_has(_texts(console), "Finish now: Gold") and _has(_texts(console), "Fail now: hit"), "the run rows show: %s" % [_texts(console)])
	console.close_menu()
	check(ChallengeDevActions.finish_as(3), "finish now as Gold")
	check(int(Challenges.last_result.get("medal", -1)) == 3, "the result is a Gold finish (%s)" % [Challenges.last_result])
	Challenges.restart(&"menu")
	check(await h.until(func() -> bool: return Challenges.phase() == Challenges.Phase.RUNNING and not SceneRouter.transitioning), "retried")
	check(ChallengeDevActions.fail_now(&"hit"), "fail now")
	check(int(Challenges.last_result.get("outcome", -1)) == ChallengeData.Outcome.FAILED_HIT, "a hit failure")
	check(str(Challenges.last_result.get("cause", "")) == "Run over: hit taken", "with the neutral cause")
