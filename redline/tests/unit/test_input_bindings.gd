extends RedlineTestCase
## M9 T03 (D4 §4): InputBindings owns the rebindable part of the InputMap.
## Every test starts from the shipped map and puts it back afterwards.

const SettingsRules := preload("res://devtools/content/rules/SettingsRules.gd")

var _snap: Dictionary = {}


func before_each() -> void:
	_snap = snapshot_settings()
	InputBindings.force_web = -1
	InputBindings.apply({})


func after_each() -> void:
	InputBindings.force_web = -1
	DevActions.force_unavailable = false
	restore_settings(_snap)


func _key(code: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code as Key
	return k


func _button(i: int) -> InputEventJoypadButton:
	var b := InputEventJoypadButton.new()
	b.button_index = i as JoyButton
	return b


func _axis(axis: int, value: float) -> InputEventJoypadMotion:
	var m := InputEventJoypadMotion.new()
	m.axis = axis as JoyAxis
	m.axis_value = value
	return m


func _encoded(action: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	for ev in InputMap.action_get_events(action):
		out.append(InputBindings.encode(ev))
	return out


## test_input_map's cinematic_skip invariant: every jump key, Enter and pad A.
func _skip_invariant_ok() -> bool:
	var skip := _encoded(&"cinematic_skip")
	for ev in InputMap.action_get_events(&"jump"):
		if ev is InputEventKey and not skip.has(InputBindings.encode(ev)):
			return false
	return skip.has("k%d" % KEY_ENTER) and skip.has("b0")


func test_snapshot_equals_project_defaults() -> void:
	for action in InputMap.get_actions():
		var setting: Variant = ProjectSettings.get_setting("input/%s" % action)
		if not (setting is Dictionary):
			continue
		var want := PackedStringArray()
		for ev: InputEvent in (setting as Dictionary)["events"]:
			want.append(InputBindings.encode(ev))
		var snap := PackedStringArray()
		for ev in InputBindings.default_events(action):
			snap.append(InputBindings.encode(ev))
		check(snap == want, "%s snapshot %s == project %s" % [action, snap, want])
		if not String(action).begins_with("debug_"):
			check(_encoded(action) == want, "%s live map is the shipped one after apply({})" % action)


func test_encode_decode_roundtrip() -> void:
	for ev: InputEvent in [_key(KEY_SPACE), _key(KEY_SHIFT), _button(3), _axis(5, 1.0), _axis(4, 1.0), _axis(0, -1.0)]:
		var s := InputBindings.encode(ev)
		check(s != "" and InputBindings.events_equal(InputBindings.decode(s), ev), "round trip %s" % s)
	check(InputBindings.encode(_axis(5, 0.8)) == "a5+" and InputBindings.encode(_axis(1, -0.3)) == "a1-", "axis signs")
	for bad in ["", "k", "kabc", "k-3", "b", "b99", "a9+", "a4*", "a+", "x12", "k0"]:
		check(InputBindings.decode(bad) == null, "garbage '%s' decodes to null" % bad)


func test_apply_override_and_reset() -> void:
	var o := {"jump": {"key": ["k%d" % KEY_J]}}
	InputBindings.apply(o)
	check(_encoded(&"jump") == PackedStringArray(["k%d" % KEY_J, "b0"]), "jump keys replaced, pad kept (%s)" % _encoded(&"jump"))
	o = InputBindings.reset(o, &"jump", &"key")
	check(o.is_empty(), "reset removes the entry")
	InputBindings.apply(o)
	check(_encoded(&"jump") == PackedStringArray(["k32", "k75", "k90", "b0"]), "shipped jump back")
	var two := {"jump": {"key": ["k74"], "pad": ["b2"]}, "heal": {"key": ["k89"]}}
	check(InputBindings.reset(two, &"", &"pad") == {"jump": {"key": ["k74"]}, "heal": {"key": ["k89"]}}, "reset one device everywhere")
	check(InputBindings.reset(two).is_empty(), "reset everything")


func test_stick_axes_survive_pad_override() -> void:
	InputBindings.apply({"move_left": {"pad": ["b2"]}})
	var evs := _encoded(&"move_left")
	check(evs.has("a0-"), "the stick stays (%s)" % evs)
	check(evs.has("b2") and not evs.has("b13"), "the D-pad slot was replaced")
	check_near(InputMap.action_get_deadzone(&"move_left"), 0.2, 0.0001, "deadzone untouched")
	var slots := InputBindings.slots(&"move_left", &"pad")
	check(slots.size() == 1 and InputBindings.encode(slots[0]) == "b2", "sticks are never slots")


func test_conflict_same_context() -> void:
	var c := InputBindings.conflicts(&"jump", _key(KEY_L))
	check(c.size() == 1 and c[0] == &"dodge", "L belongs to dodge (%s)" % str(c))
	check(InputBindings.conflicts(&"jump", _key(KEY_Y)).is_empty(), "Y is free")
	check(InputBindings.conflicts(&"attack_light", _button(JOY_BUTTON_A)).has(&"jump"), "pad A belongs to jump")


func test_allowed_overlap_interact_moveup_pad() -> void:
	check(not InputBindings.conflicts(&"interact", _button(JOY_BUTTON_DPAD_UP)).has(&"move_up"), "D-pad Up: interact + move_up is whitelisted")
	check(not InputBindings.conflicts(&"move_up", _button(JOY_BUTTON_DPAD_UP)).has(&"interact"), "both directions")
	check(InputBindings.conflicts(&"interact", _key(KEY_W)).has(&"move_up"), "the whitelist is pad D-pad Up only")


func test_allowed_overlap_map_reset() -> void:
	check(not InputBindings.conflicts(&"map", _button(JOY_BUTTON_BACK)).has(&"reset"), "View: map + reset")
	check(not InputBindings.conflicts(&"reset", _button(JOY_BUTTON_BACK)).has(&"map"), "both directions")
	check(not InputBindings.conflicts(&"reset", _key(KEY_M)).has(&"map"), "any device")


func test_map_reset_whitelisted() -> void:
	check(InputBindings.conflicts(&"map", _button(JOY_BUTTON_BACK)).is_empty(), "no conflict for the shipped View overlap")
	check(InputBindings.catalog().overlap_allowed(&"reset", &"map", &"key", "k77"), "catalog pair")


func test_reserved_esc_start() -> void:
	check(InputBindings.conflicts(&"jump", _key(KEY_ESCAPE)).has(&"reserved"), "Esc reserved")
	check(InputBindings.conflicts(&"jump", _key(KEY_BACKSPACE)).has(&"reserved"), "Backspace reserved")
	check(InputBindings.conflicts(&"jump", _button(JOY_BUTTON_START)).has(&"reserved"), "Start reserved")
	check(not InputBindings.conflicts(&"heal", _key(KEY_ENTER)).has(&"reserved"), "Enter is a soft notice, not reserved")
	check(InputBindings.reserved_text(_key(KEY_ESCAPE)).contains("Pause"), "neutral reason")


func test_reset_conflicts_with_jump() -> void:
	check(InputBindings.conflicts(&"reset", _key(KEY_SPACE)).has(&"jump"), "reset is live in gameplay too (R03.5)")
	check(InputBindings.conflicts(&"jump", _key(KEY_R)).has(&"reset"), "and the other way")


func test_swap() -> void:
	var o := InputBindings.swap({}, &"jump", &"dodge", _key(KEY_L), _key(KEY_Z))
	check(InputBindings.last_refusal == "", "swap allowed")
	InputBindings.apply(o)
	var jump := _encoded(&"jump")
	var dodge := _encoded(&"dodge")
	check(jump.has("k%d" % KEY_L) and not jump.has("k%d" % KEY_Z), "jump took L (%s)" % jump)
	check(dodge.has("k%d" % KEY_Z) and not dodge.has("k%d" % KEY_L), "dodge got Z (%s)" % dodge)
	check(_skip_invariant_ok(), "cinematic_skip follows jump")


func test_move_refused_when_other_would_be_empty() -> void:
	var o := InputBindings.move({}, &"attack_light", &"attack_heavy", _key(KEY_I), 1)
	check(InputBindings.last_refusal != "", "heavy attack would lose its only key")
	check(o.is_empty(), "overrides unchanged")
	o = InputBindings.move({}, &"attack_light", &"dodge", _key(KEY_L), 1)
	check(InputBindings.last_refusal == "", "dodge keeps Shift and C")
	InputBindings.apply(o)
	check(_encoded(&"attack_light").has("k%d" % KEY_L) and not _encoded(&"dodge").has("k%d" % KEY_L), "moved")


func test_clear_refused_last_binding() -> void:
	var o := InputBindings.clear_slot({}, &"attack_light", &"key", 0)
	check(InputBindings.last_refusal.contains("Keep at least one key"), "parity guard: %s" % InputBindings.last_refusal)
	check(o.is_empty(), "unchanged")
	o = InputBindings.clear_slot({}, &"heal", &"pad", 0)
	check(InputBindings.last_refusal.contains("button"), "pad wording")
	o = InputBindings.clear_slot({}, &"dodge", &"pad", 1)
	check(InputBindings.last_refusal == "" and o == {"dodge": {"pad": ["b1"]}}, "a second pad event may go (%s)" % o)


func test_cinematic_skip_mirrors_jump() -> void:
	InputBindings.apply({"jump": {"key": ["k%d" % KEY_J], "pad": ["b2"]}})
	check(_skip_invariant_ok(), "jump J + Enter + pad A (%s)" % _encoded(&"cinematic_skip"))
	check(not _encoded(&"cinematic_skip").has("k32"), "Space left with jump")
	check(_encoded(&"cinematic_skip").has("b2"), "the jump button skips too")
	InputBindings.apply({})
	check(_encoded(&"cinematic_skip") == PackedStringArray(["k32", "k%d" % KEY_ENTER, "k75", "k90", "b0"]), "shipped order back")


func test_bad_saved_entries_dropped() -> void:
	var raw := {"jump": {"key": ["k74", "zz", "k", 5, "b3"]}, "nope": {"key": ["k1"]}, "dodge": "bad",
		"heal": {"pad": ["k32"]}, "debug_toggle": {"key": ["k74"]}, "ui_accept": {"key": ["k74"]}}
	var clean := InputBindings.apply(raw)
	check(clean == {"jump": {"key": ["k74"]}}, "only the valid part survives (%s)" % clean)
	check(_encoded(&"heal").has("a4+"), "heal keeps its shipped pad trigger")
	check(_encoded(&"dodge").has("k%d" % KEY_SHIFT), "dodge untouched")
	check(_encoded(&"ui_accept") == PackedStringArray(["k%d" % KEY_ENTER, "k%d" % KEY_KP_ENTER, "k32", "b0"]), "menu keys are never rebound")


func test_input_map_parity_after_random_rebinds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9031
	var cat := InputBindings.catalog()
	var actions := cat.action_names()
	var keys: Array[int] = [KEY_A, KEY_B, KEY_F, KEY_G, KEY_J, KEY_K, KEY_L, KEY_N, KEY_Q, KEY_T, KEY_V, KEY_X, KEY_Y, KEY_SPACE, KEY_1, KEY_2]
	var buttons: Array[int] = [0, 1, 2, 3, 4, 9, 10, 11, 12, 13, 14]
	var o := {}
	for step in 50:
		var a := actions[rng.randi_range(0, actions.size() - 1)]
		var b := actions[rng.randi_range(0, actions.size() - 1)]
		var pad := rng.randf() < 0.5
		var dev := &"pad" if pad else &"key"
		var ev: InputEvent = _button(buttons[rng.randi_range(0, buttons.size() - 1)]) if pad else _key(keys[rng.randi_range(0, keys.size() - 1)])
		match rng.randi_range(0, 4):
			0:
				o = InputBindings.set_slot(o, a, dev, rng.randi_range(0, 2), ev)
			1:
				o = InputBindings.clear_slot(o, a, dev, rng.randi_range(0, 2))
			2:
				var slots := InputBindings.slots(a, dev)
				o = InputBindings.swap(o, a, b, ev, slots[0])
			3:
				o = InputBindings.move(o, a, b, ev, rng.randi_range(0, 2))
			4:
				o = InputBindings.reset(o, a, dev)
		o = InputBindings.apply(o)
		check(InputBindings.parity_ok(), "step %d: every action keeps a key and a pad event" % step)
		check(_skip_invariant_ok(), "step %d: cinematic_skip invariant" % step)
		var pause := _encoded(&"pause")
		check(pause.has("k%d" % KEY_ESCAPE) and pause.has("b6"), "step %d: pause keeps Esc and Start" % step)
		var non_esc := 0
		for s in pause:
			if s.begins_with("k") and s != "k%d" % KEY_ESCAPE:
				non_esc += 1
		check(non_esc >= 1, "step %d: pause keeps a key besides Esc" % step)
	# The same checks test_input_map runs on the shipped map.
	for action in InputMap.get_actions():
		var s := String(action)
		if s.begins_with("ui_") or s.begins_with("debug_"):
			continue
		var has_key := false
		var has_pad := false
		for ev in InputMap.action_get_events(action):
			has_key = has_key or ev is InputEventKey
			has_pad = has_pad or ev is InputEventJoypadButton or ev is InputEventJoypadMotion
		check(has_key and has_pad, "%s keeps keyboard and controller" % s)


## D-158: the debug pad buttons (L3, R3) are live only where dev tools are.
func test_debug_pad_events_stripped_when_dev_unavailable() -> void:
	check(_encoded(&"debug_toggle").has("b7"), "debug build: L3 toggles the overlay")
	DevActions.force_unavailable = true
	InputBindings.apply({})
	check(not _encoded(&"debug_toggle").has("b7") and not _encoded(&"debug_next_spawn").has("b8"), "no debug pad events")
	check(_encoded(&"debug_toggle").has("k%d" % KEY_F1), "debug keys stay")
	check(not InputBindings.is_reserved(_button(7)), "L3 is free for players")
	DevActions.force_unavailable = false
	InputBindings.apply({})
	check(_encoded(&"debug_toggle").has("b7"), "restored")
	check(InputBindings.is_reserved(_button(7)), "and reserved again with dev tools")


func test_web_pause_keeps_p() -> void:
	InputBindings.force_web = 1
	check(InputBindings.locked_keys(&"pause").has(KEY_P), "web locks P")
	var o := InputBindings.set_slot({}, &"pause", &"key", 1, _key(KEY_O))
	check(InputBindings.last_refusal != "" and o.is_empty(), "P cannot be replaced on web")
	InputBindings.force_web = 0
	check(not InputBindings.locked_keys(&"pause").has(KEY_P), "desktop does not lock P")
	o = InputBindings.set_slot({}, &"pause", &"key", 1, _key(KEY_O))
	check(InputBindings.last_refusal == "" and o == {"pause": {"key": ["k%d" % KEY_ESCAPE, "k%d" % KEY_O]}}, "P replaceable on desktop (%s)" % o)


func test_pause_keeps_one_non_esc_key() -> void:
	InputBindings.force_web = 0
	var o := InputBindings.clear_slot({}, &"pause", &"key", 1)
	check(InputBindings.last_refusal == "Pause needs one more key.", "clearing P refused: %s" % InputBindings.last_refusal)
	check(o.is_empty(), "unchanged")
	o = InputBindings.move({}, &"heal", &"pause", _key(KEY_P), 1)
	check(InputBindings.last_refusal == "Pause needs one more key.", "moving P away refused")
	o = InputBindings.clear_slot({}, &"pause", &"key", 0)
	check(InputBindings.last_refusal.contains("stays on"), "Esc is locked: %s" % InputBindings.last_refusal)


func test_space_for_heal_shows_soft_notice_and_binds() -> void:
	var o := InputBindings.set_slot({}, &"jump", &"key", 0, _key(KEY_J))
	o = InputBindings.apply(o)
	check(InputBindings.conflicts(&"heal", _key(KEY_SPACE)).is_empty(), "Space is free once jump moved off it")
	var note := InputBindings.soft_notice(_key(KEY_SPACE))
	check(note.contains("also confirms menus and dialogue"), "soft notice: %s" % note)
	o = InputBindings.set_slot(o, &"heal", &"key", 1, _key(KEY_SPACE))
	check(InputBindings.last_refusal == "", "the bind still happens")
	InputBindings.apply(o)
	check(_encoded(&"heal").has("k32"), "heal has Space")
	check(InputBindings.soft_notice(_button(JOY_BUTTON_B)).contains("backs out"), "pad B notice")
	check(InputBindings.soft_notice(_key(KEY_Y)) == "", "no notice for a plain key")


func test_default_map_passes_se4() -> void:
	var errs := SettingsRules.rebind_errors(InputBindings.catalog())
	check(errs.is_empty(), "SE-4 clean: %s" % "; ".join(errs))
	var glyphs := SettingsRules.glyph_errors()
	check(glyphs.is_empty(), "SE-5 clean: %s" % "; ".join(glyphs))
	# A non-whitelisted shared default is caught.
	var cat := InputBindings.catalog().duplicate(true) as RebindCatalog
	cat.allowed_overlaps = []
	var found := SettingsRules.overlap_errors(cat)
	check(found.size() == 2, "without the whitelist both shipped overlaps are errors (%s)" % "; ".join(found))
