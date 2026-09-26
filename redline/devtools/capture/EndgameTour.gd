class_name EndgameTour
extends RefCounted
## `--tour=endgame` (M9 D6 §7, T14): the M9 review frames, one section per
## area, in a TourSandbox (no developer file is read or written).
##   a  achievements: toast, collapsed toast, list, locked filter, records,
##      the dev page
##   c  challenges and the Deep Rig: the Relay terminal, the list, a detail
##      board with an assist tag, a run HUD with the developer ghost, pause in
##      a run, a new-best result card, the Pulse Pit HUD, the Deep Rig block,
##      a stratum set piece, the descent's split table
##   n  NG+ and the remix: the NG+ menu (remix on/off, confirm), the title
##      with NG+ rows, the remixed Warden Tower
##   s  settings and accessibility: main, assists, controls (pad, PlayStation
##      names), a rebind conflict, the high-contrast HUD, ScannerBeam in the
##      three palettes, the HUD and Settings at 150 %, the assist card, pause
##      over dialogue, the guided map
##   l  locale: title, pause, settings, dialogue, achievements, challenges,
##      the demo card and the HUD in en_XA, plus en_XA x 150 % settings
##   d  demo: the demo title, the border barriers (debug view), the end card
##      (and at 150 %), the refused Continue of a full-game save
##   v  dev hub: the Endgame & build hub, the Locale and Demo pages
##
## Unlike the older tours this one fails: it prints "endgame tour: N shots"
## and exits 1 when any expected shot of the selected sections is missing
## (six areas feed it; a menu that did not open must not pass silently).
##   ... res://devtools/CaptureTour.tscn -- --out=/abs/dir --tour=endgame [--only=a,d]

const SECTIONS: PackedStringArray = ["a", "c", "n", "s", "l", "d", "v"]
## The contract: every shot each section must produce (eg_<section>_<nn>_<what>).
const SHOTS := {
	"a": ["eg_a_01_toast", "eg_a_02_toast_collapsed", "eg_a_03_list", "eg_a_04_list_locked", "eg_a_05_records",
		"eg_a_06_dev_page"],
	"c": ["eg_c_01_relay_terminal", "eg_c_02_list", "eg_c_03_detail_assist_tag", "eg_c_04_run_hud_dev_ghost",
		"eg_c_05_pause_in_run", "eg_c_06_result_new_best", "eg_c_07_pulse_pit_hud", "eg_c_08_deep_rig_block",
		"eg_c_09_stratum_setpiece", "eg_c_10_descent_splits"],
	"n": ["eg_n_01_ngplus_remix_on", "eg_n_02_ngplus_remix_off", "eg_n_03_ngplus_confirm", "eg_n_04_title_ngplus_rows",
		"eg_n_05_remix_warden_tower"],
	"s": ["eg_s_01_settings_main", "eg_s_02_assists", "eg_s_03_controls_pad_ps", "eg_s_04_rebind_conflict",
		"eg_s_05_high_contrast_hud", "eg_s_06_scanner_default", "eg_s_07_scanner_red_green", "eg_s_08_scanner_blue_yellow",
		"eg_s_09_hud_150", "eg_s_10_settings_150_scrolled", "eg_s_11_assist_card", "eg_s_12_pause_over_dialogue",
		"eg_s_13_map_guided"],
	"l": ["eg_l_01_title_pseudo", "eg_l_02_pause_pseudo", "eg_l_03_settings_pseudo", "eg_l_04_dialogue_pseudo",
		"eg_l_05_achievements_pseudo", "eg_l_06_challenges_pseudo", "eg_l_07_demo_card_pseudo", "eg_l_08_hud_pseudo",
		"eg_l_09_settings_pseudo_150"],
	"d": ["eg_d_01_title_demo", "eg_d_02_border_barriers", "eg_d_03_demo_card", "eg_d_04_demo_card_150",
		"eg_d_05_continue_refused"],
	"v": ["eg_v_01_dev_hub", "eg_v_02_locale_page", "eg_v_03_demo_page"],
}
const RELAY := "res://world/rooms/lowlight/Relay.tscn"
const SECURITY := "res://world/rooms/lowlight/SecurityStation.tscn"
const WARDEN_TOWER := "res://world/rooms/lowlight/WardenTower.tscn"
const FLOODED_ALLEY := "res://world/rooms/lowlight/FloodedAlley.tscn"
const PSEUDO := "en_XA"
## A fixed "now" for record dates (2026-09-26 10:00 UTC): the same frames on
## every run.
const RECORD_NOW := 1790416800.0

var tour: Node
var taken: PackedStringArray = []
var _only: PackedStringArray = []


func _init(capture_tour: Node) -> void:
	tour = capture_tour


## The sections an --only= argument selects (every section without one;
## unknown letters are ignored).
static func parse_only(args: PackedStringArray) -> PackedStringArray:
	for a in args:
		if a.begins_with("--only="):
			var out := PackedStringArray()
			for s in a.trim_prefix("--only=").split(",", false):
				var k := s.strip_edges()
				if SECTIONS.has(k) and not out.has(k):
					out.append(k)
			return out
	return SECTIONS.duplicate()


## Expected shots for `sections`, in order.
static func expected(sections: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for s in sections:
		for n: String in SHOTS.get(s, []):
			out.append(n)
	return out


func run() -> void:
	_only = parse_only(OS.get_cmdline_user_args())
	var snap := TourSandbox.begin()
	var now_before: float = Challenges.records.now_override
	Challenges.records.now_override = RECORD_NOW
	await _frames(30)
	for s in SECTIONS:
		if not _only.has(s):
			continue
		await _reset_world()
		await Callable(self, "_section_" + s).call()
		await _reset_world()
	Challenges.records.now_override = now_before
	TourSandbox.end(snap)
	var missing := PackedStringArray()
	for n in expected(_only):
		if not taken.has(n):
			missing.append(n)
	print("endgame tour: %d shots" % taken.size())
	if not missing.is_empty():
		printerr("endgame tour: missing shots: %s" % ", ".join(missing))
	tour.call("_quit", 1 if not missing.is_empty() else 0)


# --- Helpers ----------------------------------------------------------------------------

func _frames(n: int) -> void:
	await tour.call("_frames", n)


func _shot(name: String) -> void:
	await tour.call("_shot", name)
	taken.append(name)


func _tree() -> SceneTree:
	return tour.get_tree()


func _host() -> MenuHost:
	return _tree().root.find_child("Menus", true, false) as MenuHost


func _screen(id: StringName) -> MenuScreen:
	var h := _host()
	return h.screen(id) if h and h.has_screen(id) else null


func _title() -> MenuScreen:
	return _host().get_node("TitleMenu") as MenuScreen


func _console() -> DevConsole:
	return _host().get_node("DevConsole") as DevConsole


## Every menu closed, the tree running, no run, English, 100 % UI.
func _close_menus() -> void:
	var h := _host()
	if h:
		h.drop_queued()
		for c in h.get_children():
			if c is MenuScreen and (c as MenuScreen).is_open():
				(c as MenuScreen).close_menu()
	var box := _tree().root.find_child("DialogueBox", true, false)
	if box and box.has_method("is_open") and box.call("is_open"):
		_close_dialogue(box)
	_tree().paused = false


func _close_dialogue(box: Node) -> void:
	var guard := 0
	while box.call("is_open") and guard < 64:
		box.set("shown_chars", 9999.0)
		box.call("advance")
		guard += 1


## A clean slate between sections: no run, no menu, a fresh profile, default
## look, English.
func _reset_world() -> void:
	if Challenges.active():
		Challenges.quit()
		for i in 240:
			await _frames(1)
			if not Challenges.active() and not SceneRouter.transitioning:
				break
	_close_menus()
	if Loc.locale() != Loc.SOURCE_LOCALE:
		LocaleDevActions.set_locale(Loc.SOURCE_LOCALE)
	Settings.ui_scale = 0
	Settings.high_contrast = false
	Settings.colorblind_mode = 0
	Settings.pad_glyphs = 0
	Settings.map_hints = 1
	Settings.achievement_toasts = false
	Settings.assist_suggestions = false
	InputGlyphs.using_pad = false
	EventBus.settings_changed.emit()
	var toast := AchievementDevActions.toast_node()
	if toast:
		toast.clear()
	Game.new_game()
	Game.profile_id = 1
	await _frames(5)


## Loads `path` at `entry` and waits until the room is live and settled.
func _goto(path: String, entry: StringName, settle: int = 40) -> Room:
	_close_menus()
	SceneRouter.goto_room(path, entry)
	for i in 240:
		await _frames(1)
		if SceneRouter.current_room_path == path and not SceneRouter.transitioning:
			break
	var room := SceneRouter.current_room as Room
	if room and is_instance_valid(room.player):
		room.player.input_source = tour.get("_input")
	await _frames(settle)
	return room


func _open(id: StringName, ctx: Dictionary = {}) -> MenuScreen:
	var h := _host()
	if not ctx.is_empty():
		h.open_with(id, ctx)
	else:
		h.open(id)
	await _frames(6)
	return _screen(id)


## Waits for `cond` (checked each physics frame); false on timeout.
func _until(cond: Callable, max_frames: int = 240) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await _frames(1)
	return bool(cond.call())


## Starts a challenge from the Relay's training rig and waits for the run.
func _start_run(id: String) -> bool:
	var ch := ChallengeLibrary.by_id(id)
	if ch == null:
		return false
	if not ChallengeDevActions.start(id):
		return false
	var ok := await _until(func() -> bool: return Challenges.phase() == Challenges.Phase.RUNNING and not SceneRouter.transitioning, 300)
	var room := SceneRouter.current_room as Room
	if ok and room and is_instance_valid(room.player):
		room.player.input_source = tour.get("_input")
	return ok


func _drive(move_x: int, frames: int) -> void:
	var input: ScriptedInputSource = tour.get("_input")
	input.move_x = move_x
	await _frames(frames)
	input.move_x = 0


# --- a: achievements ----------------------------------------------------------------------

func _section_a() -> void:
	# Long enough for the area banner to fade.
	await _goto(RELAY, &"start", 240)
	Settings.achievement_toasts = true
	AchievementDevActions.test_toast("first_blade")
	await _frames(40)
	await _shot("eg_a_01_toast")
	var toast := AchievementDevActions.toast_node()
	if toast:
		toast.clear()
	for id in ["collector_down", "first_secret", "reach_relay", "perfect_reads"]:
		toast.enqueue(id)
	await _frames(40)
	await _shot("eg_a_02_toast_collapsed")
	toast.clear()
	Settings.achievement_toasts = false
	for id in ["first_blade", "collector_down", "first_secret", "reach_relay", "perfect_reads", "intake_log"]:
		Platform.dev_unlock(id)
	var m := await _open(&"achievements")
	if m and m.is_open():
		await _shot("eg_a_03_list")
		m.set("filter", AchievementsMenu.Filter.LOCKED)
		m.set("list_page", 0)
		m.rebuild()
		m.focus_index(0)
		await _frames(4)
		await _shot("eg_a_04_list_locked")
		m.set("page", &"records")
		m.rebuild()
		m.focus_index(0)
		await _frames(4)
		await _shot("eg_a_05_records")
		m.close_menu()
	var c := await _open(&"dev") as DevConsole
	if c and c.is_open():
		c.go(&"endgame")
		c.go(&"ach")
		await _frames(4)
		await _shot("eg_a_06_dev_page")
		c.close_menu()


# --- c: challenges and the Deep Rig ---------------------------------------------------------

func _seed_records() -> void:
	var ch := ChallengeLibrary.by_id("tt_neon_roofs")
	if ch == null:
		return
	var gold := ChallengeDevActions.value_for_tier(ch, 3)
	var silver := ChallengeDevActions.value_for_tier(ch, 2)
	Challenges.records.submit(ch, 1, gold + 30, ChallengeData.Outcome.FINISHED, PackedInt32Array(), {"assists": ["aim assist"]})
	Challenges.records.submit(ch, 1, silver, ChallengeData.Outcome.FINISHED)


func _section_c() -> void:
	StoryPresets.apply("act1_complete")
	Game.set_flag("chase_rainline_done")
	Game.save_game()
	await _goto(RELAY, &"challenges", 60)
	await _shot("eg_c_01_relay_terminal")
	_seed_records()
	var m := await _open(&"challenges", {"return_to": {"room": RELAY, "entry": &"challenges"}})
	if m and m.is_open():
		await _shot("eg_c_02_list")
		var ch := ChallengeLibrary.by_id("tt_neon_roofs")
		if ch:
			m.call("show_detail", ch)
			await _frames(4)
			await _shot("eg_c_03_detail_assist_tag")
		m.close_menu()
	await _frames(5)
	if await _start_run("tt_neon_roofs"):
		await _drive(1, 90)
		await _shot("eg_c_04_run_hud_dev_ghost")
		var p := await _open(&"pause")
		if p and p.is_open():
			await _shot("eg_c_05_pause_in_run")
			p.close_menu()
		await _frames(4)
		ChallengeDevActions.finish_as(3)
		if await _until(func() -> bool: return _screen(&"challenge_result") != null and _screen(&"challenge_result").is_open(), 300):
			await _frames(10)
			await _shot("eg_c_06_result_new_best")
			_screen(&"challenge_result").close_menu()
		await _reset_run()
	if await _start_run("pit_endurance"):
		await _drive(1, 30)
		await _frames(150)
		await _shot("eg_c_07_pulse_pit_hud")
		await _reset_run()
	NullDevActions.grant_open()
	NullDevActions.set_depth(true)
	var list := await _open(&"challenges")
	var descent := ChallengeLibrary.by_id("null_descent")
	if list and list.is_open() and descent:
		list.call("show_detail", descent)
		await _frames(4)
		await _shot("eg_c_08_deep_rig_block")
		list.close_menu()
	await _goto(RELAY, &"challenges", 10)
	if await _start_run("null_breaker_run"):
		await _drive(1, 70)
		await _frames(30)
		await _shot("eg_c_09_stratum_setpiece")
		await _reset_run()
	if await _start_run("null_descent"):
		await _frames(20)
		ChallengeDevActions.finish_as(3)
		if await _until(func() -> bool: return _screen(&"challenge_result") != null and _screen(&"challenge_result").is_open(), 300):
			await _frames(10)
			await _shot("eg_c_10_descent_splits")
			_screen(&"challenge_result").close_menu()
		await _reset_run()


func _focus_last(m: MenuScreen) -> void:
	var n := 0
	for c in m._body.get_children():
		if c is Button:
			n += 1
	m.focus_index(maxi(0, n - 1))


## Leaves a run (the result card, if any, is gone) and waits for the world.
func _reset_run() -> void:
	_close_menus()
	if Challenges.active():
		Challenges.quit()
	await _until(func() -> bool: return not Challenges.active() and not SceneRouter.transitioning, 300)
	_close_menus()
	await _frames(10)


# --- n: NG+ and the remix ---------------------------------------------------------------

func _section_n() -> void:
	StoryPresets.apply("act1_complete")
	Game.save_game()
	var title := _title()
	title.open_menu()
	await _frames(8)
	await _shot("eg_n_04_title_ngplus_rows")
	title.close_menu()
	var m := await _open(&"ng_plus", {"from": "title"})
	if m and m.is_open():
		await _shot("eg_n_01_ngplus_remix_on")
		m.call("_toggle_remix")
		await _frames(4)
		await _shot("eg_n_02_ngplus_remix_off")
		m.call("_toggle_remix")
		m.set("_confirm", true)
		m.rebuild()
		m.focus_index(0)
		await _frames(4)
		await _shot("eg_n_03_ngplus_confirm")
		m.close_menu()
	await _frames(4)
	if NgPlusDevActions.start_now(true):
		await _goto(WARDEN_TOWER, &"", 60)
		await _shot("eg_n_05_remix_warden_tower")


# --- s: settings and accessibility ---------------------------------------------------------

func _settings_page(page: StringName) -> MenuScreen:
	var m := await _open(&"settings")
	if m and m.is_open() and page != &"":
		m.call("_go", page)
		await _frames(4)
	return m


func _first_key(action: StringName) -> InputEvent:
	for e: InputEvent in InputBindings.default_events(action):
		if e is InputEventKey:
			return e
	return null


func _section_s() -> void:
	var room := await _goto(FLOODED_ALLEY, &"", 40)
	var m := await _settings_page(&"")
	if m and m.is_open():
		await _shot("eg_s_01_settings_main")
		m.call("_go", &"assists")
		await _frames(4)
		await _shot("eg_s_02_assists")
		m.close_menu()
	Settings.pad_glyphs = 2
	InputGlyphs.using_pad = true
	EventBus.settings_changed.emit()
	m = await _settings_page(&"controls")
	if m and m.is_open():
		await _shot("eg_s_03_controls_pad_ps")
		m.close_menu()
	InputGlyphs.using_pad = false
	Settings.pad_glyphs = 0
	m = await _settings_page(&"controls")
	if m and m.is_open():
		# Jump's first key slot captures the key another action ships with.
		var key_jump := _first_key(&"jump")
		var key_other: InputEvent = null
		for a: StringName in [&"dodge", &"interact", &"attack", &"heal"]:
			key_other = _first_key(a)
			if key_other != null:
				break
		m.call("_open_action", &"jump")
		m.set("_capture_slot", {"action": &"jump", "device": &"key", "index": 0, "prev": key_jump})
		m.call("_on_captured", key_other)
		await _frames(4)
		await _shot("eg_s_04_rebind_conflict")
		m.close_menu()
	Settings.bindings = {}
	InputBindings.apply({})
	Settings.high_contrast = true
	EventBus.settings_changed.emit()
	await _frames(10)
	await _shot("eg_s_05_high_contrast_hud")
	Settings.high_contrast = false
	EventBus.settings_changed.emit()
	await _goto(SECURITY, &"from_power", 60)
	var palettes := ["eg_s_06_scanner_default", "eg_s_07_scanner_red_green", "eg_s_08_scanner_blue_yellow"]
	for i in 3:
		Settings.colorblind_mode = i
		EventBus.settings_changed.emit()
		await _frames(20)
		await _shot(palettes[i])
	Settings.colorblind_mode = 0
	EventBus.settings_changed.emit()
	await _goto(FLOODED_ALLEY, &"", 30)
	Settings.ui_scale = 2
	EventBus.settings_changed.emit()
	await _frames(10)
	await _shot("eg_s_09_hud_150")
	m = await _settings_page(&"visual")
	if m and m.is_open():
		_focus_last(m)
		await _frames(6)
		await _shot("eg_s_10_settings_150_scrolled")
		m.close_menu()
	Settings.ui_scale = 0
	EventBus.settings_changed.emit()
	Settings.assist_suggestions = true
	if AccessibilityDevActions.trigger_suggestion_here():
		await _frames(10)
		await _shot("eg_s_11_assist_card")
	_close_menus()
	Settings.assist_suggestions = false
	await _frames(4)
	var orr: NpcProfile = load("res://data/npcs/orr.tres")
	EventBus.dialogue_requested.emit(orr.pick_dialogue(), "Orr")
	await _frames(40)
	var p := await _open(&"pause")
	if p and p.is_open():
		await _shot("eg_s_12_pause_over_dialogue")
	_close_menus()
	await _frames(4)
	Settings.map_hints = 2
	for id in ["Relay", "FloodedAlley"]:
		var r := Game.world_map.room(id)
		if r and not Game.state.visited_rooms.has(r.room_path):
			Game.state.visited_rooms.append(r.room_path)
	var map := await _open(&"map")
	if map and map.is_open():
		await _shot("eg_s_13_map_guided")
		map.close_menu()
	Settings.map_hints = 1
	if room == null:
		return


# --- l: locale (en_XA) ------------------------------------------------------------------------

func _section_l() -> void:
	LocaleDevActions.set_locale(PSEUDO)
	await _frames(4)
	var title := _title()
	title.open_menu()
	await _frames(8)
	await _shot("eg_l_01_title_pseudo")
	title.close_menu()
	await _goto(FLOODED_ALLEY, &"", 40)
	await _shot("eg_l_08_hud_pseudo")
	var p := await _open(&"pause")
	if p and p.is_open():
		await _shot("eg_l_02_pause_pseudo")
		p.close_menu()
	var s := await _settings_page(&"")
	if s and s.is_open():
		await _shot("eg_l_03_settings_pseudo")
		s.close_menu()
	var orr: NpcProfile = load("res://data/npcs/orr.tres")
	EventBus.dialogue_requested.emit(orr.pick_dialogue(), "Orr")
	await _frames(60)
	await _shot("eg_l_04_dialogue_pseudo")
	_close_menus()
	await _frames(4)
	var a := await _open(&"achievements")
	if a and a.is_open():
		await _shot("eg_l_05_achievements_pseudo")
		a.close_menu()
	StoryPresets.apply("act1_complete")
	var c := await _open(&"challenges")
	if c and c.is_open():
		await _shot("eg_l_06_challenges_pseudo")
		c.close_menu()
	var d := await _open(&"demo_end")
	if d and d.is_open():
		await _shot("eg_l_07_demo_card_pseudo")
		d.close_menu()
	Settings.ui_scale = 2
	EventBus.settings_changed.emit()
	s = await _settings_page(&"visual")
	if s and s.is_open():
		await _shot("eg_l_09_settings_pseudo_150")
		s.close_menu()
	Settings.ui_scale = 0
	LocaleDevActions.set_locale(Loc.SOURCE_LOCALE)
	EventBus.settings_changed.emit()


# --- d: demo ------------------------------------------------------------------------------------

func _section_d() -> void:
	DemoDevActions.set_demo_session(true)
	await _frames(4)
	var title := _title()
	title.open_menu()
	await _frames(8)
	await _shot("eg_d_01_title_demo")
	title.close_menu()
	DemoBarrier.set_debug_draw(true)
	var target := DemoDevActions.demo_border_target()
	await _goto(String(target[0]), StringName(target[1]), 60)
	await _shot("eg_d_02_border_barriers")
	DemoBarrier.set_debug_draw(false)
	var card := await _open(&"demo_end")
	if card and card.is_open():
		await _shot("eg_d_03_demo_card")
		card.close_menu()
	Settings.ui_scale = 2
	EventBus.settings_changed.emit()
	card = await _open(&"demo_end")
	if card and card.is_open():
		await _shot("eg_d_04_demo_card_150")
		card.close_menu()
	Settings.ui_scale = 0
	EventBus.settings_changed.emit()
	# A full-game save: the demo lists its Continue but refuses it.
	DemoDevActions.set_demo_session(false)
	Game.new_game()
	StoryPresets.apply("act1_complete")
	Game.state.last_anchor_room = RELAY
	Game.state.last_anchor_id = "relay"
	Game.save_game()
	DemoDevActions.set_demo_session(true)
	_close_menus()
	title.open_menu()
	await _frames(8)
	await _shot("eg_d_05_continue_refused")
	title.close_menu()
	DemoDevActions.set_demo_session(false)
	await _frames(4)


# --- v: dev hub -------------------------------------------------------------------------------

func _section_v() -> void:
	await _goto(RELAY, &"start", 20)
	var c := await _open(&"dev") as DevConsole
	if c == null or not c.is_open():
		return
	c.go(&"endgame")
	await _frames(4)
	await _shot("eg_v_01_dev_hub")
	c.go(&"locale")
	await _frames(4)
	await _shot("eg_v_02_locale_page")
	c.go(&"endgame")
	c.go(&"demo")
	await _frames(4)
	await _shot("eg_v_03_demo_page")
	c.close_menu()
