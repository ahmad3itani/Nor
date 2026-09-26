extends MenuScreen
## Settings (bible §24, D4 §3-§4): a category list, one level of pages built
## from data (data/settings/catalog.tres), and the special pages Controls,
## action detail, conflict, confirm-reset and the first-run quick page.
##
## Controller-first: every value row cycles on confirm (one button reaches
## everything), left/right adjust without moving focus, and Cancel (or
## Backspace) steps back exactly one level; every page also ends with an
## explicit Back row (R03.17). The focused row's description is pinned under
## the list. Saved on close. Never shames the player: rows say what an
## option does, never who it is for (D4 §3.4, SE-3).
## M8's "Subtitles & scenes…" page keeps its rows, labels and order
## (test_m8_foundation_ui); text auto-advance is appended after them.

const QUICK := &"quick"
const MAIN := &"main"
const CONTROLS := &"controls"
const ACTION := &"action"
const CONFLICT := &"conflict"
const CONFIRM := &"confirm"
## Focus decoration of STEPS rows: a suffix only, never between label and
## value (R03.18: "Label: Value" stays the row's prefix).
const STEP_HINT := "  ◂ ▸"
## Lines reserved for the pinned description, so the panel does not jump as
## focus moves between rows with short and long descriptions.
const DESCRIPTION_LINES := 2

## The page shown: MAIN, a catalog page id, or a special page.
var page: StringName = MAIN
## Which bindings Controls shows and edits: &"key" or &"pad".
var _device: StringName = &"key"
## Action detail page: the action and "Remove mode".
var _detail_action: StringName = &""
var _remove_mode: bool = false
## One-line neutral notice on the action page (refusals, soft notices).
var _notice: String = ""
## Conflict page: {action, device, index, ev, prev, others}.
var _conflict: Dictionary = {}
## Confirm page: {text, yes: Callable}.
var _confirm: Dictionary = {}
## Pages to return to: [{page, focus}], innermost last.
var _stack: Array[Dictionary] = []
## The slot a running capture fills: {action, device, index, prev}.
var _capture_slot: Dictionary = {}
var _capture: RebindCapture


func _ready() -> void:
	super._ready()
	_capture = RebindCapture.new()
	_capture.name = "RebindCapture"
	add_child(_capture)
	_capture.captured.connect(_on_captured)
	_capture.cancelled.connect(func(_reason: StringName) -> void:
		_notice = ""
		if visible:
			rebuild())
	_capture.message_changed.connect(func(_t: String) -> void:
		if visible and page == ACTION:
			rebuild())


func open_menu() -> void:
	_stack.clear()
	_notice = ""
	_conflict = {}
	_confirm = {}
	_remove_mode = false
	_device = &"pad" if InputGlyphs.using_pad else &"key"
	# The title's first-run row opens the quick page directly (ctx, R03.10);
	# Back/Done there closes Settings.
	var wanted := StringName(str(ctx.get("page", "")))
	page = wanted if wanted != &"" and (_catalog().page(wanted) != null) else MAIN
	super.open_menu()


func close_menu() -> void:
	if not visible:
		return
	_capture.cancel(&"closed")
	Settings.save_settings()
	AudioManager.apply_volume()
	EventBus.settings_changed.emit()
	super.close_menu()


func rebuild() -> void:
	var keep := focused_index()
	clear_body()
	set_footer("")
	match page:
		MAIN:
			_build_main()
		ACTION:
			_build_action()
		CONFLICT:
			_build_conflict()
		CONFIRM:
			_build_confirm()
		_:
			var p := _catalog().page(page)
			if p == null:
				page = MAIN
				_build_main()
			else:
				_build_page(p)
	focus_index(keep)


# --- Navigation ------------------------------------------------------------

## Opens a page one level deeper; Back returns to the row that opened it
## (`from_row`, else the focused row). MAIN goes all the way back to the
## category list.
func _go(p: StringName, from_row: int = -1) -> void:
	if p == MAIN:
		var focus := 0
		if not _stack.is_empty():
			focus = int(_stack[0]["focus"])
		_stack.clear()
		page = MAIN
		rebuild()
		focus_index(focus)
		return
	_stack.append({"page": page, "focus": from_row if from_row >= 0 else focused_index()})
	page = p
	rebuild()
	focus_index(0)


## One level back; from the first page, close.
func _back() -> void:
	if _capture.is_active():
		_capture.cancel(&"cancelled")
		return
	if _stack.is_empty():
		close_menu()
		return
	var top: Dictionary = _stack.pop_back()
	page = top["page"]
	if page != ACTION:
		_notice = ""
	rebuild()
	focus_index(int(top["focus"]))


## Cancel steps back one level (never out of Settings from a sub-page), and
## is ignored while a capture listens and on the frame it ends, so the Esc
## that cancels a capture never also leaves the page.
func _process(_delta: float) -> void:
	if not visible or _capture.is_active():
		return
	if _capture.end_frame >= 0 and Engine.get_process_frames() <= _capture.end_frame + 1:
		return
	if Engine.get_process_frames() != _opened_frame and cancel_pressed():
		_back()


# --- Pages -------------------------------------------------------------------

func _build_main() -> void:
	add_label(Loc.t("SETTINGS"), UiTheme.ACCENT, UiTheme.FONT_SIZE + 2)
	for p in _catalog().pages:
		if p == null or p.link_label == "" or (p.dev_only and not DevActions.available()):
			continue
		add_button(Loc.t(p.link_label), _go.bind(p.id, _button_count()), _describe.bind(""))
	add_button(Loc.t("Reset all settings…"), func() -> void:
		_ask(Loc.t(_catalog().reset_all_prompt), _reset_all), _describe.bind(""))
	add_button(Loc.t("Back"), _back, _describe.bind(""))


func _build_page(p: SettingsPageData) -> void:
	add_label(Loc.t(p.title), UiTheme.ACCENT, UiTheme.FONT_SIZE + 2)
	if p.show_assist_header:
		add_label(Loc.t(_catalog().assist_header), UiTheme.MUTED)
	for d in _catalog().rows_of(p):
		if d.dev_only and not DevActions.available():
			continue
		_add_def_row(d)
	if p.special == CONTROLS:
		_add_action_rows()
	if p.reset_row:
		add_button(Loc.t("Reset this page…"), func() -> void:
			_ask(Loc.f("Reset every option on {page}?", {"page": Loc.t(p.title)}), func() -> void:
				Settings.reset_keys(_catalog().page_keys(p))
				_restyle()), _describe.bind(""))
	add_button(Loc.t("Done") if p.special == QUICK else Loc.t("Back"), _back, _describe.bind(""))


func _add_def_row(d: SettingDef) -> void:
	var text := _row_text(d)
	var on_focus := _describe.bind(d.description)
	if d.kind == SettingDef.Kind.ACTION:
		match d.action:
			&"device":
				add_option_row(text, _toggle_device, _toggle_device, _toggle_device, on_focus)
			&"variant":
				add_option_row(text, _cycle_variant.bind(1), _cycle_variant.bind(-1), _cycle_variant.bind(1), on_focus)
			&"language":
				add_option_row(text, _cycle_language.bind(1), _cycle_language.bind(-1), _cycle_language.bind(1), on_focus)
			_:
				add_button(text, func() -> void: pass, on_focus, false)
		return
	if d.key == &"reactor_mode" and _core_forced():
		# A challenge sets the Core for its run (R03.8): shown, never changed
		# here, and the live ReactorCore keeps the forced mode.
		add_button(Loc.f("{row} (set by this challenge)", {"row": text}), func() -> void: pass,
			_describe.bind(d.description), false)
		return
	var b := add_option_row(text, _step.bind(d, 1, true), _step.bind(d, -1, false), _step.bind(d, 1, false), on_focus)
	if d.kind == SettingDef.Kind.STEPS:
		b.set_meta(&"plain_text", text)
		b.focus_entered.connect(func() -> void: b.text = str(b.get_meta(&"plain_text")) + STEP_HINT)
		b.focus_exited.connect(func() -> void: b.text = str(b.get_meta(&"plain_text")))


## "Label: Value" in the current language.
func _row_text(d: SettingDef) -> String:
	var label := Loc.t(d.label)
	match d.action:
		&"device":
			return "%s: %s" % [label, Loc.t(d.choices[1] if _device == &"pad" else d.choices[0])]
		&"variant":
			return "%s: %s" % [label, _variant_label()]
		&"language":
			return "%s: %s" % [label, _locale_name(Settings.effective_locale())]
	if d.kind == SettingDef.Kind.STEPS:
		return "%s: %s" % [label, d.value_text(Settings.get(d.key))]
	return "%s: %s" % [label, Loc.t(d.value_text(Settings.get(d.key)))]


func _add_action_rows() -> void:
	var cat := InputBindings.catalog()
	if _device == &"pad" and InputGlyphs.using_pad:
		var joy := Input.get_joy_name(InputGlyphs.last_pad_device)
		if joy != "":
			add_label(Loc.f("Controller: {name}", {"name": joy}), UiTheme.MUTED)
	for group in cat.groups():
		add_label(Loc.t(group), UiTheme.MUTED)
		for a in cat.actions:
			if a == null or a.group != group:
				continue
			var shown := InputGlyphs.labels(a.action, _device)
			add_button("%s: %s" % [Loc.t(a.label), shown], _open_action.bind(a.action, _button_count()),
				_describe.bind("Confirm to change this action's bindings."))
	var reset_text := Loc.t("Reset keyboard controls…") if _device == &"key" else Loc.t("Reset controller controls…")
	add_button(reset_text, func() -> void:
		var prompt := Loc.t("Put every keyboard control back?") if _device == &"key" else Loc.t("Put every controller control back?")
		_ask(prompt, _reset_device.bind(_device)), _describe.bind(""))


func _build_action() -> void:
	var entry := InputBindings.catalog().entry(_detail_action)
	var label := Loc.t(entry.label) if entry else String(_detail_action)
	var dev_name := Loc.t("Keyboard") if _device == &"key" else Loc.t("Controller")
	add_label(Loc.f("{action} ({device})", {"action": Loc.upper(label), "device": dev_name}), UiTheme.ACCENT, UiTheme.FONT_SIZE + 2)
	var slots := InputBindings.slots(_detail_action, _device)
	for i in slots.size():
		var ev := slots[i]
		var shown := InputGlyphs.event_label(ev) if ev != null else Loc.t("(empty)")
		var enc := InputBindings.encode(ev) if ev != null else ""
		if enc != "" and InputBindings.is_locked(_detail_action, enc):
			shown = Loc.f("{key} (fixed)", {"key": shown})
		var row := Loc.f("Key {n}: {key}", {"n": i + 1, "key": shown}) if _device == &"key" \
			else Loc.f("Button {n}: {key}", {"n": i + 1, "key": shown})
		add_button(row, _slot_pressed.bind(i), _describe.bind(""))
	if _device == &"pad" and entry and entry.pad_stick_fixed:
		add_label(Loc.t("Left stick (fixed)"), UiTheme.MUTED)
	add_option_row(Loc.f("Remove mode: {v}", {"v": Loc.t("On") if _remove_mode else Loc.t("Off")}),
		_toggle_remove, _toggle_remove, _toggle_remove,
		_describe.bind("On: confirming a slot clears it. Every action keeps at least one."))
	add_button(Loc.f("Reset {action}", {"action": label}), func() -> void:
		_notice = ""
		_commit(InputBindings.reset(Settings.bindings, _detail_action, _device), _detail_action), _describe.bind(""))
	if _capture.is_active():
		add_label(_capture.message if _capture.message != "" else _capture.prompt_text(), UiTheme.TEXT)
	elif _notice != "":
		add_label(_notice, UiTheme.MUTED)
	add_button(Loc.t("Back"), _back, _describe.bind(""))


func _build_conflict() -> void:
	var ev: InputEvent = _conflict.get("ev")
	var others: Array = _conflict.get("others", [])
	var key := InputGlyphs.event_label(ev)
	var names := PackedStringArray()
	for o: Variant in others:
		names.append(_action_label(StringName(str(o))))
	add_label(Loc.f("{key} is already {action}.", {"key": key, "action": ", ".join(names)}), UiTheme.TEXT)
	if others.size() == 1:
		var other := StringName(str(others[0]))
		var prev: InputEvent = _conflict.get("prev")
		if prev != null:
			add_button(Loc.f("Swap ({other} gets {key})", {"other": names[0], "key": InputGlyphs.event_label(prev)}), _swap, _describe.bind(""))
		# Move only when the other action keeps an event on this device.
		InputBindings.move(Settings.bindings, StringName(str(_conflict["action"])), other, ev, int(_conflict["index"]))
		if InputBindings.last_refusal == "":
			add_button(Loc.t("Move it here"), _move, _describe.bind(""))
		else:
			add_label(InputBindings.last_refusal, UiTheme.MUTED)
	add_button(Loc.t("Cancel"), _back, _describe.bind(""))


func _build_confirm() -> void:
	add_label(str(_confirm.get("text", "")), UiTheme.TEXT)
	add_button(Loc.t("Yes"), func() -> void:
		var yes: Callable = _confirm.get("yes", Callable())
		_back()
		if yes.is_valid():
			yes.call(), _describe.bind(""))
	add_button(Loc.t("No"), _back, _describe.bind(""))


# --- Rows --------------------------------------------------------------------

## Cycles (confirm: wraps) or steps (left/right: clamps) a value row.
func _step(d: SettingDef, dir: int, wrap: bool) -> void:
	if d.key == &"reactor_mode" and _core_forced():
		return
	var n := d.value_count()
	if n <= 0:
		return
	var i := _value_index(d)
	i = posmod(i + dir, n) if wrap else clampi(i + dir, 0, n - 1)
	match d.kind:
		SettingDef.Kind.TOGGLE:
			Settings.set(d.key, i == 1)
		SettingDef.Kind.CHOICE:
			Settings.set(d.key, i)
		SettingDef.Kind.STEPS:
			Settings.set(d.key, d.steps[i])
	_after_change(d)


func _value_index(d: SettingDef) -> int:
	var v: Variant = Settings.get(d.key)
	match d.kind:
		SettingDef.Kind.TOGGLE:
			return 1 if bool(v) else 0
		SettingDef.Kind.STEPS:
			return d.step_index(float(v))
	return int(v)


## Side effects of a changed row, then restyle open UI and redraw in place.
func _after_change(d: SettingDef) -> void:
	match d.key:
		&"subtitle_size":
			# Editing the stored size drops a --subtitle-size capture override.
			Settings._subtitle_size_override = -1
		&"reactor_mode":
			var room := SceneRouter.current_room as Room
			if room and is_instance_valid(room.player):
				room.player.reactor.apply_mode(Settings.reactor_mode)
		&"playtest_recording":
			if not Settings.playtest_recording:
				Playtest.end_session("recording_disabled")
	match d.preview:
		&"shake":
			EventBus.camera_shake_requested.emit(0.4)
		&"sfx":
			AudioManager.apply_volume()
			AudioManager.play_sfx(&"ui_tick")
	if d.key == &"ui_scale" or d.key == &"high_contrast":
		_restyle()
		return
	if d.emits_settings_changed:
		EventBus.settings_changed.emit()
	_redraw()


## Theme or size changed: new look now, focus kept.
func _restyle() -> void:
	UiTheme.invalidate()
	EventBus.settings_changed.emit()
	_apply_look()
	_redraw()


func _redraw() -> void:
	var keep := focused_index()
	rebuild()
	focus_index(keep)


func _core_forced() -> bool:
	return Challenges.forced_reactor_mode() >= 0


func _toggle_device() -> void:
	_device = &"key" if _device == &"pad" else &"pad"
	_redraw()


func _toggle_remove() -> void:
	_remove_mode = not _remove_mode
	_redraw()


## Pages of option rows keep room for a description; the category list and
## the confirm/conflict pages have none, so they show no empty footer.
func _describe(text: String) -> void:
	var reserve := DESCRIPTION_LINES if page != MAIN and page != CONFIRM and page != CONFLICT else 0
	set_footer(Loc.t(text) if text != "" else "", reserve)


## Facilitators can pin an experiment arm; "Auto" rotates per session.
## Takes effect from the next New Game / Continue.
func _variant_label() -> String:
	var v := Playtest.config.variant(Settings.playtest_variant)
	return v.label if v else Loc.t("Auto (rotates)")


func _cycle_variant(dir: int) -> void:
	var ids: Array[String] = [""]
	for v in Playtest.config.variants:
		ids.append(v.id)
	var i := ids.find(Settings.playtest_variant)
	Settings.playtest_variant = ids[posmod(i + dir, ids.size())]
	EventBus.settings_changed.emit()
	_redraw()


## Language: cycles the offered locales (the change is immediate; pressing
## again cycles back, so no one is stuck in a language they cannot read).
func _cycle_language(dir: int) -> void:
	var codes := Loc.available_locales()
	if codes.size() <= 1:
		return
	var i := codes.find(Settings.effective_locale())
	if i < 0:
		i = codes.find(Loc.locale())
	Settings.set_locale_setting(codes[posmod(i + dir, codes.size())])
	UiTheme.invalidate()
	_redraw()


## Endonym of a locale ("" = automatic, shown as the language in use).
func _locale_name(code: String) -> String:
	var shown := code if code != "" else Loc.locale()
	var info := Loc.info()
	var endonym := ""
	if info != null and shown == Loc.locale() and "endonym" in info:
		endonym = str(info.get("endonym"))
	if endonym == "":
		endonym = "English" if shown.begins_with("en") else shown
	return endonym if code != "" else Loc.f("Automatic ({language})", {"language": endonym})


# --- Rebinding -----------------------------------------------------------------

func _open_action(action: StringName, from_row: int = -1) -> void:
	_detail_action = action
	_remove_mode = false
	_notice = ""
	_go(ACTION, from_row)


func _slot_pressed(index: int) -> void:
	if _capture.is_active():
		return
	var slots := InputBindings.slots(_detail_action, _device)
	var prev: InputEvent = slots[index] if index < slots.size() else null
	if _remove_mode:
		if prev == null:
			return
		_notice = ""
		_commit(InputBindings.clear_slot(Settings.bindings, _detail_action, _device, index), _detail_action)
		return
	if prev != null and InputBindings.is_locked(_detail_action, InputBindings.encode(prev)):
		_notice = InputBindings.locked_text(_detail_action, InputBindings.encode(prev))
		_redraw()
		return
	var entry := InputBindings.catalog().entry(_detail_action)
	_notice = ""
	_capture_slot = {"action": _detail_action, "device": _device, "index": index, "prev": prev}
	_capture.start(entry.label if entry else String(_detail_action), _device)
	_redraw()


func _on_captured(ev: InputEvent) -> void:
	var action := StringName(str(_capture_slot.get("action", "")))
	var device := StringName(str(_capture_slot.get("device", "key")))
	var index := int(_capture_slot.get("index", 0))
	var conf := InputBindings.conflicts(action, ev)
	if conf.has(&"reserved"):
		_notice = InputBindings.reserved_text(ev)
		_redraw()
		return
	if conf.is_empty():
		_commit(InputBindings.set_slot(Settings.bindings, action, device, index, ev), action)
		if InputBindings.last_refusal == "" and not _ships_with(action, ev):
			_notice = InputBindings.soft_notice(ev)
			_redraw()
		return
	var others: Array = []
	for c in conf:
		others.append(c)
	_conflict = {"action": action, "device": device, "index": index, "ev": ev, "prev": _capture_slot.get("prev"), "others": others}
	_go(CONFLICT)


func _swap() -> void:
	var other := StringName(str(_conflict["others"][0]))
	var action := StringName(str(_conflict["action"]))
	var result := InputBindings.swap(Settings.bindings, action, other, _conflict["ev"], _conflict["prev"])
	_back()
	_commit(result, action)


func _move() -> void:
	var other := StringName(str(_conflict["others"][0]))
	var action := StringName(str(_conflict["action"]))
	var result := InputBindings.move(Settings.bindings, action, other, _conflict["ev"], int(_conflict["index"]))
	_back()
	_commit(result, action)


## Applies new overrides (or shows the refusal), then tells prompts.
func _commit(overrides: Dictionary, action: StringName) -> void:
	if InputBindings.last_refusal != "":
		_notice = InputBindings.last_refusal
		_redraw()
		return
	Settings.bindings = InputBindings.apply(overrides)
	EventBus.input_bindings_changed.emit(action)
	_redraw()


func _reset_device(device: StringName) -> void:
	Settings.bindings = InputBindings.apply(InputBindings.reset(Settings.bindings, &"", device))
	EventBus.input_bindings_changed.emit(&"")
	_redraw()


func _ships_with(action: StringName, ev: InputEvent) -> bool:
	for d in InputBindings.default_events(action):
		if InputBindings.events_equal(d, ev):
			return true
	return false


func _action_label(action: StringName) -> String:
	var entry := InputBindings.catalog().entry(action)
	return Loc.t(entry.label) if entry else String(action)


# --- Resets --------------------------------------------------------------------

## Opens the confirm page; `yes` runs after it steps back.
func _ask(text: String, yes: Callable) -> void:
	_confirm = {"text": text, "yes": yes}
	_go(CONFIRM)


func _reset_all() -> void:
	Settings.reset_keys(Settings.reset_all_keys())
	AudioManager.apply_volume()
	_restyle()


func _button_count() -> int:
	return _body.get_children().filter(func(n: Node) -> bool: return n is Button and not n.is_queued_for_deletion()).size()


func _catalog() -> SettingsCatalog:
	return Settings.settings_catalog()
