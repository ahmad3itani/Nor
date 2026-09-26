extends RedlineTestCase
## M9 T11 (bible §23, D4 §10, R11.4, R11.7, R11.11, R11.12): the adaptive
## assist advisor and its card. The advisor offers, never applies; its logs
## survive the walk back from an Anchor; the card ignores a held confirm and
## "Not now" has focus.

const MARKET := "res://world/rooms/lowlight/MarketRun.tscn"
const ALLEY := "res://world/rooms/lowlight/FloodedAlley.tscn"
const LAB := "res://world/rooms/CombatLab.tscn"
const BROKEN_LIFT := "res://world/rooms/undercity/BrokenLift.tscn"
const COLLECTOR_BAY := "res://world/rooms/undercity/CollectorBay.tscn"
const TMP_CFG := "user://test_adaptive_assist.cfg"
const SAVE_DIR := "user://test_adaptive_assist_saves"

var root: Node2D
var advisor: AssistAdvisor
var _extras: Array[Node] = []
var _snap: Dictionary = {}
## [menu id, context copy] per menu_requested.
var _requests: Array = []
## [context, cause, deaths] per assist_suggested.
var _suggested: Array = []
## [context, answer, key] per assist_suggestion_answered.
var _answers: Array = []


func before_each() -> void:
	_snap = snapshot_settings()
	Settings.remove_settings_files(TMP_CFG)
	Settings._path = TMP_CFG
	Settings.apply_defaults()
	SaveManager.save_dir = SAVE_DIR
	get_tree().paused = false
	AssistAdvisor.dev_quiet = false
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	Game.new_game()
	_requests.clear()
	_suggested.clear()
	_answers.clear()
	EventBus.menu_requested.connect(_on_menu_requested)
	EventBus.assist_suggested.connect(_on_suggested)
	EventBus.assist_suggestion_answered.connect(_on_answered)
	advisor = null


func after_each() -> void:
	EventBus.menu_requested.disconnect(_on_menu_requested)
	EventBus.assist_suggested.disconnect(_on_suggested)
	EventBus.assist_suggestion_answered.disconnect(_on_answered)
	for a: StringName in [&"jump", &"ui_accept", &"attack_light"]:
		Input.action_release(a)
	for n in _extras:
		if is_instance_valid(n):
			n.queue_free()
	_extras.clear()
	await get_tree().process_frame
	get_tree().paused = false
	CinematicMode.theatre = false
	AssistAdvisor.dev_quiet = false
	MenuHost.context = {}
	SceneRouter.current_room = null
	SceneRouter.current_room_path = ""
	SceneRouter.world_root = null
	SceneRouter._fade = null
	if is_instance_valid(root):
		root.queue_free()
	SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR
	AtomicJson.remove_tree(SAVE_DIR)
	Settings.remove_settings_files(TMP_CFG)
	restore_settings(_snap)
	Game.new_game()
	await physics_frames(2)


func _on_menu_requested(id: StringName) -> void:
	_requests.append([id, MenuHost.context.duplicate(true)])


func _on_suggested(ctx: String, cause: String, deaths: int) -> void:
	_suggested.append([ctx, cause, deaths])


func _on_answered(ctx: String, answer: StringName, key: String) -> void:
	_answers.append([ctx, answer, key])


func _advisor() -> AssistAdvisor:
	advisor = AssistAdvisor.new()
	add_child(advisor)
	_extras.append(advisor)
	return advisor


func _room(path: String) -> Room:
	SceneRouter.goto_room(path)
	await physics_frames(2)
	return SceneRouter.current_room as Room


func cfg() -> AccessibilityConfig:
	return Settings.config()


## One death as the advisor sees it (without the Room's own death handling),
## then the respawn and a few frames for the card to be offered.
func _die(cause: String, respawn := true) -> void:
	var room := SceneRouter.current_room as Room
	room.player.combat.last_damage_source = cause
	advisor._on_player_died()
	if respawn:
		advisor._on_player_respawned(room.player, &"start")
		for i in 3:
			await get_tree().process_frame


func _card_requests() -> Array:
	return _requests.filter(func(r: Array) -> bool: return r[0] == &"assist_suggest")


func _card(ctx: Dictionary) -> MenuScreen:
	var m: MenuScreen = load("res://ui/menus/AssistSuggestMenu.gd").new()
	add_child(m)
	_extras.append(m)
	m.ctx = ctx.duplicate(true)
	m.open_menu()
	return m


## Arms a card: the arm time has passed and every confirm was seen released.
func _arm(m: MenuScreen) -> void:
	m.set("opened_ms", Time.get_ticks_msec() - 5000)
	await get_tree().process_frame
	await get_tree().process_frame


func _buttons(m: MenuScreen) -> Array[Button]:
	var out: Array[Button] = []
	for c in m._body.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c as Button)
	return out


func _focused_text(m: MenuScreen) -> String:
	for b in _buttons(m):
		if b.has_focus():
			return b.text
	return ""


# --- Thresholds and logs ------------------------------------------------------------

func test_threshold_room() -> void:
	_advisor()
	await _room(MARKET)
	for i in cfg().room_deaths - 1:
		await _die("needle/needle_stab")
	check(_card_requests().is_empty(), "no card before the room threshold (%d deaths)" % (cfg().room_deaths - 1))
	await _die("needle/needle_stab")
	check(_card_requests().size() == 1, "the card is offered after the %dth death" % cfg().room_deaths)
	check(_suggested.size() == 1 and _suggested[0][0] == "room:%s" % MARKET and int(_suggested[0][2]) == cfg().room_deaths,
		"assist_suggested(room context, cause, deaths): %s" % [_suggested])
	if not _card_requests().is_empty():
		var ctx: Dictionary = _card_requests()[0][1]
		check(str(ctx.get("title", "")) == (SceneRouter.current_room as Room).room_name, "the card is titled with the room name")


func test_threshold_boss_context() -> void:
	_advisor()
	await _room(MARKET)
	for i in cfg().boss_deaths:
		advisor._on_boss_started(null, "WARDEN KRAIL")
		await _die("warden_krail/slam")
		advisor._on_room_loaded(null)
	check(_card_requests().size() == 1, "the boss threshold (%d) offers the card" % cfg().boss_deaths)
	check(not _suggested.is_empty() and _suggested[0][0] == "boss:warden_krail", "boss context: %s" % [_suggested])
	if not _card_requests().is_empty():
		var ctx: Dictionary = _card_requests()[0][1]
		check(str(ctx.get("title", "")) == "WARDEN KRAIL", "the card is titled with the boss title")
		check(str(ctx.get("text", "")) == "Learning a fight takes a few tries.", "the boss rule's line")
		check(Array(ctx["keys"]) == ["damage_assist", "generous_checkpoints"], "boss rule offers %s" % [ctx["keys"]])


func test_window_expiry() -> void:
	_advisor()
	await _room(MARKET)
	for i in cfg().room_deaths - 1:
		await _die("hazard")
	advisor.time_offset_ms += int(cfg().window_seconds * 1000.0) + 1000
	await _die("hazard")
	check(advisor.deaths("room:%s" % MARKET) == 1, "old deaths expire (%d left)" % advisor.deaths("room:%s" % MARKET))
	check(_card_requests().is_empty(), "no card from expired deaths")


func test_cooldown_and_session_cap() -> void:
	_advisor()
	await _room(MARKET)
	var ctx := "room:%s" % MARKET
	for i in cfg().room_deaths:
		await _die("hazard")
	check(_card_requests().size() == 1, "first card")
	EventBus.assist_suggestion_answered.emit(ctx, &"later", "")
	check(advisor.deaths(ctx) == 0, "an answer forgets the context's deaths")
	for i in cfg().room_deaths:
		await _die("hazard")
	check(_card_requests().size() == 1 and advisor.suppressed_reason() == "cooldown", "Not now holds the card back (%s)" % advisor.suppressed_reason())
	advisor.time_offset_ms += int(cfg().cooldown_seconds * 1000.0) + 1000
	# Keep the log inside the window after the jump in time.
	for i in cfg().room_deaths:
		await _die("hazard")
	check(_card_requests().size() == 2, "after the cooldown the card comes back")
	EventBus.assist_suggestion_answered.emit(ctx, &"applied", "aim_assist")
	for i in cfg().room_deaths:
		await _die("hazard")
	check(_card_requests().size() == cfg().max_per_session and advisor.suppressed_reason() == "session_cap",
		"at most %d cards per session (%s)" % [cfg().max_per_session, advisor.suppressed_reason()])


func test_suppressed_when_off_challenge_theatre_lab() -> void:
	_advisor()
	await _room(MARKET)
	check(advisor.suppressed_reason() == "", "a world room in plain play allows it")
	Settings.assist_suggestions = false
	check(advisor.suppressed_reason() == "off", "the player turned suggestions off")
	Settings.assist_suggestions = true
	Challenges.force_active = true
	check(advisor.suppressed_reason() == "challenge", "a challenge run")
	Challenges.force_active = false
	CinematicMode.theatre = true
	check(advisor.suppressed_reason() == "theatre", "a dev theatre")
	CinematicMode.theatre = false
	await _room(LAB)
	check(advisor.suppressed_reason() == "not_world_room", "a lab room")
	advisor._on_player_died()
	check(advisor.deaths("room:%s" % LAB) == 0, "lab deaths are not logged")
	await _room(MARKET)
	Settings.assist_suggestions = false
	for i in cfg().room_deaths:
		await _die("hazard")
	check(_card_requests().is_empty(), "off: no card, whatever the deaths")


# --- Rules ------------------------------------------------------------------------------

func test_rule_burnout() -> void:
	var picked := AssistAdvisor.pick_rule(cfg(), false, "burnout")
	check(not picked.is_empty() and cfg().rules[int(picked["rule"])].cause_prefix == "burnout", "burnout deaths match the burnout rule")
	check(Array(picked.get("keys", [])) == ["burnout_hurts", "reactor_mode"], "offers %s" % [picked.get("keys")])
	var scanner := AssistAdvisor.pick_rule(cfg(), false, "scanner")
	check(Array(scanner.get("keys", [])) == ["damage_assist", "generous_checkpoints"] and scanner["values"][0] == 2, "scanner rule")


func test_rule_skips_already_on() -> void:
	Settings.damage_assist = 2
	Settings.generous_checkpoints = true
	var picked := AssistAdvisor.pick_rule(cfg(), true, "warden_krail/slam")
	check(Array(picked.get("keys", [])) == ["aim_assist"], "assisted keys are skipped; the next rule with anything left wins (%s)" % [picked.get("keys")])
	Settings.aim_assist = 1
	check(AssistAdvisor.pick_rule(cfg(), true, "warden_krail/slam").is_empty(), "everything on: nothing is offered")
	Settings.damage_assist = 1
	var room_rule := AssistAdvisor.pick_rule(cfg(), false, "needle/stab")
	check(Array(room_rule.get("keys", [])) == ["damage_assist"], "Bosses-only does not count as assisted for a room's 'All reduced' (%s)" % [room_rule.get("keys")])


func test_redline_core_player_not_offered_core_downgrade() -> void:
	Settings.reactor_mode = 2
	var picked := AssistAdvisor.pick_rule(cfg(), false, "burnout")
	check(Array(picked.get("keys", [])) == ["burnout_hurts"], "a Redline Challenge Core is offered only burnout_hurts = false (%s)" % [picked.get("keys")])
	var m := _card({"context": "room:x", "title": "X", "text": "The Core ran dry a few times.",
		"keys": picked.get("keys", PackedStringArray()), "values": picked.get("values", [])})
	await _arm(m)
	for b in _buttons(m):
		if b.text.begins_with(Loc.t("Core burnout costs health")):
			b.pressed.emit()
	check(not Settings.burnout_hurts, "the offered key applies")
	check(Settings.reactor_mode == 2, "the chosen Core mode is never touched")


# --- The card ---------------------------------------------------------------------------

func _boss_card() -> MenuScreen:
	return _card({"context": "boss:warden_krail", "title": "WARDEN KRAIL", "cause": "warden_krail/slam", "deaths": 4,
		"text": "Learning a fight takes a few tries.", "keys": PackedStringArray(["damage_assist", "generous_checkpoints"]),
		"values": [1, true]})


func test_default_focus_is_not_now() -> void:
	var m := _boss_card()
	await get_tree().process_frame
	check(_focused_text(m) == Loc.t("Not now"), "Not now has focus (got '%s')" % _focused_text(m))
	var texts := _buttons(m).map(func(b: Button) -> String: return b.text)
	check(texts.size() == 5, "two offers, Open all assists, Not now, Don't suggest again: %s" % [texts])


func test_never_changes_settings_without_answer() -> void:
	var before := Settings.snapshot()
	var m := _boss_card()
	await _arm(m)
	m.call("not_now")
	check(not m.is_open(), "Not now closes the card")
	check(Settings.snapshot() == before, "opening and closing the card changes no setting")
	check(_answers.size() == 1 and _answers[0][1] == &"later", "the answer is 'later'")


func test_dont_suggest_again_sets_setting() -> void:
	var m := _boss_card()
	await _arm(m)
	m.call("dont_suggest_again")
	check(not Settings.assist_suggestions, "Don't suggest again turns suggestions off (reversible in Settings)")
	check(not m.is_open(), "the card closes")
	check(_answers.size() == 1 and _answers[0][1] == &"never" and _answers[0][2] == "assist_suggestions", "answer: %s" % [_answers])


func test_answer_signals_emitted() -> void:
	var m := _boss_card()
	await _arm(m)
	_buttons(m)[0].pressed.emit()
	check(Settings.damage_assist == 1 and not Settings.generous_checkpoints, "only the picked key applies")
	check(_answers.size() == 1 and _answers[0] == ["boss:warden_krail", &"applied", "damage_assist"], "applied: %s" % [_answers])
	check(m.is_open() and _buttons(m)[0].text.ends_with("On"), "the row reads On and the card stays open")
	m.call("_open_settings")
	check(_answers.size() == 2 and _answers[1][1] == &"opened_settings", "opened_settings: %s" % [_answers])
	var settings_req := _requests.filter(func(r: Array) -> bool: return r[0] == &"settings")
	check(settings_req.size() == 1 and settings_req[0][1].get("page") == &"assists", "Settings opens at the Assists page")
	var m2 := _boss_card()
	await _arm(m2)
	m2.call("not_now")
	var m3 := _boss_card()
	await _arm(m3)
	m3.call("dont_suggest_again")
	var kinds := _answers.map(func(a: Array) -> StringName: return a[1])
	check(kinds == [&"applied", &"opened_settings", &"later", &"never"], "every answer emits: %s" % [kinds])


## R11.11: a jump held through the respawn never answers the card.
func test_suggest_card_ignores_held_confirm() -> void:
	_advisor()
	await _room(MARKET)
	Input.action_press(&"jump")
	Input.action_press(&"ui_accept")
	var m := _boss_card()
	m.set("opened_ms", Time.get_ticks_msec() - 5000)
	for i in 3:
		await get_tree().process_frame
	m.call("not_now")
	check(m.is_open(), "an unarmed Not now does nothing (confirm still held)")
	check(advisor._cooldown_until < 0, "an unarmed press starts no cooldown")
	Input.action_release(&"jump")
	Input.action_release(&"ui_accept")
	m.set("opened_ms", Time.get_ticks_msec())
	await get_tree().process_frame
	m.call("not_now")
	check(m.is_open(), "released but before the arm time: still open")
	await _arm(m)
	m.call("not_now")
	check(not m.is_open(), "an armed Not now closes")
	check(advisor._cooldown_until > 0, "an armed Not now starts the cooldown")


# --- Logs that survive the walk back (R11.4, R11.7) ----------------------------------------

func test_room_log_survives_walk_back() -> void:
	_advisor()
	var ctx := "room:%s" % MARKET
	for i in cfg().room_deaths - 1:
		await _room(MARKET)
		await _die("needle/needle_stab", false)
		# Respawn elsewhere (no Anchor in the room), then walk back.
		await _room(ALLEY)
		advisor._on_player_respawned((SceneRouter.current_room as Room).player, &"from_relay")
		await get_tree().process_frame
	check(advisor.deaths(ctx) == cfg().room_deaths - 1, "room deaths survive leaving the room (%d)" % advisor.deaths(ctx))
	check(_card_requests().is_empty(), "not yet")
	await _room(MARKET)
	await _die("needle/needle_stab", false)
	await _room(ALLEY)
	advisor._on_player_respawned((SceneRouter.current_room as Room).player, &"from_relay")
	for i in 3:
		await get_tree().process_frame
	check(_card_requests().size() == 1, "the %dth death offers the card after the respawn elsewhere" % cfg().room_deaths)
	# A rest at an Anchor in that room clears it.
	await _room(MARKET)
	await _die("needle/needle_stab", false)
	advisor._on_anchor_rested(null)
	check(advisor.deaths(ctx) == 0, "a rest in the room clears its log")


func test_boss_log_cleared_only_by_defeat_expiry_or_answer() -> void:
	_advisor()
	await _room(MARKET)
	var ctx := "boss:collector_drone"
	var fight := func() -> void:
		advisor._boss_id = "collector_drone"
		advisor._boss_title = "COLLECTOR DRONE"
	fight.call()
	await _die("collector_drone/dive", false)
	advisor._on_room_loaded(null)
	advisor._on_anchor_rested(null)
	await _room(ALLEY)
	check(advisor.deaths(ctx) == 1, "room changes and rests keep the boss log")
	advisor._on_boss_defeated("collector_drone")
	check(advisor.deaths(ctx) == 0, "boss_defeated clears it")
	fight.call()
	await _die("collector_drone/dive", false)
	advisor.time_offset_ms += int(cfg().window_seconds * 1000.0) + 1000
	check(advisor.deaths(ctx) == 0, "window expiry clears it")
	fight.call()
	await _die("collector_drone/dive", false)
	EventBus.assist_suggestion_answered.emit(ctx, &"opened_settings", "")
	check(advisor.deaths(ctx) == 0, "an answer clears it")


## Integration through the real runback (R11.4): four deaths in the
## Collector fight, each respawning at the BrokenLift Anchor and walking back
## through the door, with generous checkpoints off: the card is offered
## after the 4th respawn.
func test_collector_four_deaths_suggest_after_respawn() -> void:
	Settings.generous_checkpoints = false
	Game.rest_at_anchor(BROKEN_LIFT, "uc_lift")
	var main: Node = (load("res://Main.tscn") as PackedScene).instantiate()
	main.set("start_room", COLLECTOR_BAY)
	add_child(main)
	_extras.append(main)
	await physics_frames(5)
	var host := main.get_node("Menus") as MenuHost
	var started := [0]
	var on_start := func(_b: Node2D, _t: String) -> void: started[0] += 1
	EventBus.boss_started.connect(on_start)
	var deaths := cfg().boss_deaths
	for i in deaths:
		check(SceneRouter.current_room_path == COLLECTOR_BAY, "death %d happens in the bay (in %s)" % [i + 1, SceneRouter.current_room_path])
		var bot := RouteBot.new(get_tree(), (SceneRouter.current_room as Room).player)
		var before: int = started[0]
		await bot.run([["run", 140]])
		for f in 60:
			if started[0] > before:
				break
			await physics_frames(1)
		check(started[0] > before, "the fight started (death %d)" % (i + 1))
		var room := SceneRouter.current_room
		(room as Room).player.combat.take_damage(99, Vector2.ZERO, 0.0, true, "collector_drone/dive")
		await _wait_room_change(room)
		check(SceneRouter.current_room_path == BROKEN_LIFT, "respawn at the BrokenLift Anchor (in %s)" % SceneRouter.current_room_path)
		for f in 5:
			await get_tree().process_frame
		if i < deaths - 1:
			check(_suggested.is_empty(), "no card after death %d" % (i + 1))
			bot = RouteBot.new(get_tree(), (SceneRouter.current_room as Room).player)
			var ok: bool = await bot.run([["run", 600], ["exit", 1]])
			check(ok, "walk back through the BrokenLift -> CollectorBay door: %s" % bot.failure)
			await _wait_room_change(null)
	EventBus.boss_started.disconnect(on_start)
	check(_suggested.size() == 1 and _suggested[0][0] == "boss:collector_drone", "the card is offered after the %dth respawn: %s" % [deaths, _suggested])
	check(host.screen(&"assist_suggest") != null and host.screen(&"assist_suggest").is_open(), "the card is open")
	if host.screen(&"assist_suggest") and host.screen(&"assist_suggest").is_open():
		var card := host.screen(&"assist_suggest")
		await get_tree().process_frame
		check(_focused_text(card) == Loc.t("Not now"), "Not now has focus on the live card")


func _wait_room_change(from: Node, max_frames := 360) -> void:
	for i in max_frames:
		await physics_frames(1)
		if SceneRouter.current_room != from and is_instance_valid(SceneRouter.current_room) and not SceneRouter.transitioning:
			break
	await physics_frames(3)


# --- Dev page (D4 §12) ---------------------------------------------------------------

func test_dev_accessibility_actions() -> void:
	_advisor()
	await _room(MARKET)
	check(AccessibilityDevActions.advisor() == advisor, "the dev actions find the advisor by group")
	advisor._shown_this_session = cfg().max_per_session
	check(AccessibilityDevActions.trigger_suggestion_here(), "the dev trigger offers the card here, cap ignored")
	check(_card_requests().size() == 1, "one card request")
	check(AccessibilityDevActions.toggle_advisor_quiet() and advisor.suppressed_reason(true) == "dev_quiet", "quiet silences the advisor")
	AccessibilityDevActions.toggle_advisor_quiet()
	AccessibilityDevActions.apply_all_assists()
	check(Settings.damage_assist > 0 and Settings.aim_assist > 0 and Settings.generous_checkpoints and not Settings.burnout_hurts \
		and Settings.jump_hold_mode == 1, "All assists on")
	check(Settings.reactor_mode == 1, "the preset never picks the Redline Core")
	AccessibilityDevActions.apply_readable_preset()
	check(Settings.high_contrast and Settings.ui_scale == 2 and Settings.background_dim == 2, "High contrast + 150 % + strong dim")
	var cb := Settings.colorblind_mode
	check(AccessibilityDevActions.cycle_colorblind() == (cb + 1) % 3, "colour-blind mode cycles")
	AccessibilityDevActions.restore_defaults()
	check(Settings.damage_assist == 0 and not Settings.high_contrast and Settings.ui_scale == 0, "defaults restored")
	check(AccessibilityDevActions.print_bindings().begins_with("BINDINGS"), "bindings print")
	AccessibilityDevActions.reset_controls()
	check(Settings.bindings.is_empty(), "controls back to defaults")
	var console: DevConsole = load("res://ui/menus/DevConsole.gd").new()
	add_child(console)
	_extras.append(console)
	console.open_menu()
	console.go(&"access")
	var rows := _buttons(console).map(func(b: Button) -> String: return b.text)
	check(rows.has("Trigger assist suggestion here") and rows.has("Print bindings"), "the Accessibility page builds: %s" % [rows])
	console.close_menu()
