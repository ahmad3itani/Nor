class_name InputBindings
extends RefCounted
## Runtime owner of the InputMap for rebindable actions (bible §24 full
## rebinding, D4 §4.2). project.godot stays the default source: defaults are
## snapshotted once before any override, so "Reset" is always the shipped
## layout and tests can compare against it.
##
## Overrides (Settings.bindings) only hold what differs from the defaults:
##   {"jump": {"key": ["k32", "k90"], "pad": ["b0"]}, "dodge": {"pad": ["b1", "a5+"]}}
## Events are stored by physical keycode, pad button or trigger axis, never
## by modifier chord (Shift binds as an ordinary key, as dodge ships).
## Every edit is a pure function over that dictionary; apply() writes the
## result into the InputMap. Nothing here can leave an action without a key
## or a pad event (the parity rule of test_input_map), so gameplay and the
## menus stay reachable after any sequence of edits.

const KEY := &"key"
const PAD := &"pad"
## Pad stick axes (0..3) are never slots: move_* keep them as shipped.
const FIRST_TRIGGER_AXIS := 4
const DEV_ACTIONS_PATH := "res://devtools/DevActions.gd"

## action -> Array[InputEvent] (duplicates of the project.godot events).
static var _defaults: Dictionary = {}
## Why the last edit was refused ("" = it was not). Neutral, player-facing.
static var last_refusal: String = ""
## Test seam: -1 = follow BuildInfo.is_web(), 0 = desktop, 1 = web.
static var force_web: int = -1


static func snapshot_defaults() -> void:
	if not _defaults.is_empty():
		return
	for action in InputMap.get_actions():
		var evs: Array[InputEvent] = []
		for ev in InputMap.action_get_events(action):
			evs.append(ev.duplicate() as InputEvent)
		_defaults[action] = evs


## Drops the snapshot and the catalog (Cinematics._exit_tree: static caches
## holding Resources are reported as leaks at exit).
static func clear_cache() -> void:
	_defaults.clear()
	RebindCatalog.clear_cache()


static func catalog() -> RebindCatalog:
	return RebindCatalog.get_catalog()


static func default_events(action: StringName) -> Array[InputEvent]:
	snapshot_defaults()
	var out: Array[InputEvent] = []
	for ev: InputEvent in _defaults.get(action, []):
		out.append(ev.duplicate() as InputEvent)
	return out


# --- Encoding --------------------------------------------------------------

## "k<physical>" | "b<button>" | "a<axis>+" / "a<axis>-"; "" for anything else.
static func encode(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		return "k%d" % code if code != KEY_NONE else ""
	if ev is InputEventJoypadButton:
		return "b%d" % (ev as InputEventJoypadButton).button_index
	if ev is InputEventJoypadMotion:
		var m := ev as InputEventJoypadMotion
		return "a%d%s" % [m.axis, "+" if m.axis_value >= 0.0 else "-"]
	return ""


## The event an encoded string names, or null on garbage (dropped by apply).
static func decode(s: String) -> InputEvent:
	if s.length() < 2:
		return null
	var body := s.substr(1)
	match s[0]:
		"k":
			if not body.is_valid_int() or body.to_int() <= 0:
				return null
			var k := InputEventKey.new()
			k.physical_keycode = body.to_int() as Key
			return k
		"b":
			if not body.is_valid_int() or body.to_int() < 0 or body.to_int() >= JOY_BUTTON_SDL_MAX:
				return null
			var b := InputEventJoypadButton.new()
			b.button_index = body.to_int() as JoyButton
			return b
		"a":
			var dir_sign := body.right(1)
			var axis := body.left(body.length() - 1)
			if (dir_sign != "+" and dir_sign != "-") or not axis.is_valid_int():
				return null
			if axis.to_int() < 0 or axis.to_int() >= JOY_AXIS_SDL_MAX:
				return null
			var m := InputEventJoypadMotion.new()
			m.axis = axis.to_int() as JoyAxis
			m.axis_value = 1.0 if dir_sign == "+" else -1.0
			return m
	return null


static func device_of(ev: InputEvent) -> StringName:
	if ev is InputEventKey:
		return KEY
	if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
		return PAD
	return &""


## A stick direction (axes 0..3): shown, never a slot.
static func is_stick(ev: InputEvent) -> bool:
	return ev is InputEventJoypadMotion and (ev as InputEventJoypadMotion).axis < FIRST_TRIGGER_AXIS


## Physical keycode / button index / axis + direction.
static func events_equal(x: InputEvent, y: InputEvent) -> bool:
	if x == null or y == null:
		return false
	var ex := encode(x)
	return ex != "" and ex == encode(y)


# --- Reading the live map ----------------------------------------------------

## The action's slot events on `device` in order (sticks excluded), padded
## with null up to the catalog's slot count.
static func slots(action: StringName, device: StringName) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	for ev in InputMap.action_get_events(action):
		if device_of(ev) == device and not is_stick(ev):
			out.append(ev)
	var entry := catalog().entry(action)
	var n := entry.slot_count(device) if entry else out.size()
	while out.size() < n:
		out.append(null)
	return out


## Encoded slot events on `device` for `overrides` (the override list when it
## has one, else the shipped events).
static func current(overrides: Dictionary, action: StringName, device: StringName) -> PackedStringArray:
	var o: Variant = overrides.get(String(action), {})
	if o is Dictionary and (o as Dictionary).has(String(device)):
		var clean := _clean_list((o as Dictionary)[String(device)], device, action)
		if not clean.is_empty():
			return clean
	return _default_list(action, device)


# --- Edits (pure: each returns new overrides; refusals keep the old ones) ---

## Puts `ev` in slot `index` (appends past the end). An event already in
## another slot of the same action moves here instead of doubling up.
static func set_slot(overrides: Dictionary, action: StringName, device: StringName, index: int, ev: InputEvent) -> Dictionary:
	last_refusal = ""
	var enc := encode(ev)
	if enc == "" or device_of(ev) != device:
		last_refusal = Loc.t("That input cannot be used here.")
		return overrides.duplicate(true)
	var list := current(overrides, action, device)
	if index < list.size() and is_locked(action, list[index]):
		last_refusal = locked_text(action, list[index])
		return overrides.duplicate(true)
	var at := list.find(enc)
	if at >= 0:
		list.remove_at(at)
		if at < index:
			index -= 1
	if index < list.size():
		list[index] = enc
	else:
		list.append(enc)
	var entry := catalog().entry(action)
	if entry and list.size() > entry.slot_count(device):
		list = list.slice(0, entry.slot_count(device))
	return _with(overrides, action, device, list)


## Removes slot `index`. Refused when it would leave the device without an
## event (parity), when the event is locked, or when Pause would lose its
## last key other than Esc (R03.6).
static func clear_slot(overrides: Dictionary, action: StringName, device: StringName, index: int) -> Dictionary:
	last_refusal = ""
	var list := current(overrides, action, device)
	if index < 0 or index >= list.size():
		return overrides.duplicate(true)
	var why := _removal_refusal(action, device, list, list[index])
	if why != "":
		last_refusal = why
		return overrides.duplicate(true)
	list.remove_at(index)
	return _with(overrides, action, device, list)


## `a` takes `ev` (into the slot that held `a_prev`, or a new slot), and `b`
## gets `a_prev` where it had `ev`. Without an `a_prev` it is a move.
static func swap(overrides: Dictionary, a: StringName, b: StringName, ev: InputEvent, a_prev: InputEvent) -> Dictionary:
	last_refusal = ""
	if a_prev == null:
		return move(overrides, a, b, ev, -1)
	var device := device_of(ev)
	var enc := encode(ev)
	var prev := encode(a_prev)
	var la := current(overrides, a, device)
	var lb := current(overrides, b, device)
	if is_locked(b, enc):
		last_refusal = locked_text(b, enc)
		return overrides.duplicate(true)
	if is_locked(a, prev):
		last_refusal = locked_text(a, prev)
		return overrides.duplicate(true)
	var ia := la.find(prev)
	var ib := lb.find(enc)
	if ia < 0 or ib < 0:
		return move(overrides, a, b, ev, ia)
	if lb.has(prev):
		lb.remove_at(ib)
	else:
		lb[ib] = prev
	if la.has(enc):
		la.remove_at(ia)
	else:
		la[ia] = enc
	var out := _with(overrides, a, device, la)
	return _with(out, b, device, lb)


## `b` gives up `ev` and `a` takes it (slot `index`, or appended when -1).
## Refused when `b` would be left without an event on that device.
static func move(overrides: Dictionary, a: StringName, b: StringName, ev: InputEvent, index: int) -> Dictionary:
	last_refusal = ""
	var device := device_of(ev)
	var enc := encode(ev)
	var lb := current(overrides, b, device)
	var why := _removal_refusal(b, device, lb, enc) if lb.has(enc) else ""
	if why != "":
		last_refusal = why
		return overrides.duplicate(true)
	if lb.has(enc):
		lb.remove_at(lb.find(enc))
	var out := _with(overrides, b, device, lb)
	var la := current(out, a, device)
	return set_slot(out, a, device, index if index >= 0 else la.size(), ev)


## One action on one device, one action, or everything (&"" / &"").
static func reset(overrides: Dictionary, action: StringName = &"", device: StringName = &"") -> Dictionary:
	last_refusal = ""
	var out := {}
	for k: Variant in overrides:
		var d: Dictionary = (overrides[k] as Dictionary).duplicate(true) if overrides[k] is Dictionary else {}
		if action == &"" or str(k) == String(action):
			if device == &"":
				d = {}
			else:
				d.erase(String(device))
		if not d.is_empty():
			out[str(k)] = d
	return out


# --- Checks ----------------------------------------------------------------

## Blocking conflicts for giving `ev` to `action`: the other catalog actions
## live at the same time (contexts intersect) that already hold an equal
## event, minus the whitelisted overlaps; plus &"reserved" when no action may
## take `ev`. Soft notices (keys that also work menus) are soft_notice().
static func conflicts(action: StringName, ev: InputEvent) -> Array[StringName]:
	var out: Array[StringName] = []
	if is_reserved(ev):
		out.append(&"reserved")
	var cat := catalog()
	var mine := cat.entry(action)
	var ctx := mine.contexts if mine else PackedStringArray(["gameplay"])
	var enc := encode(ev)
	var device := device_of(ev)
	for other in cat.actions:
		if other == null or other.action == action or not _intersects(ctx, other.contexts):
			continue
		if not InputMap.has_action(other.action):
			continue
		for e in InputMap.action_get_events(other.action):
			if events_equal(e, ev) and not cat.overlap_allowed(action, other.action, device, enc):
				out.append(other.action)
				break
	return out


## No action may take it: Esc and Backspace (menus, capture cancel), pad
## Start, and, in builds with dev tools, every debug key and pad button.
static func is_reserved(ev: InputEvent) -> bool:
	var cat := catalog()
	if ev is InputEventKey:
		var code := int((ev as InputEventKey).physical_keycode)
		if cat.reserved_keys.has(code):
			return true
	elif cat.reserved_pad.has(encode(ev)):
		return true
	if _dev_available():
		for action: StringName in _debug_actions():
			for d: InputEvent in _defaults.get(action, []):
				if events_equal(d, ev):
					return true
	return false


## Neutral line shown next to a reserved refusal.
static func reserved_text(ev: InputEvent) -> String:
	var key_name := event_label(ev)
	var enc := encode(ev)
	if enc == "k%d" % KEY_ESCAPE or enc == "b%d" % JOY_BUTTON_START:
		return Loc.f("{key} is kept for Pause.", {"key": key_name})
	if enc == "k%d" % KEY_BACKSPACE:
		return Loc.f("{key} is kept for backing out of menus.", {"key": key_name})
	return Loc.f("{key} is kept for dev tools.", {"key": key_name})


## "" or a neutral notice when `ev` also works a fixed menu or scene action
## (R03.14). The bind still happens.
static func soft_notice(ev: InputEvent) -> String:
	match catalog().soft_kind(encode(ev)):
		"confirm":
			return Loc.f("{key} also confirms menus and dialogue.", {"key": event_label(ev)})
		"cancel":
			return Loc.f("{key} also backs out of menus.", {"key": event_label(ev)})
		"skip":
			return Loc.f("{key} also skips scenes.", {"key": event_label(ev)})
	return ""


## Short label of one event on the active glyph family.
static func event_label(ev: InputEvent) -> String:
	var glyphs := _glyphs()
	if glyphs != null:
		return str(glyphs.call("event_label", ev))
	if ev is InputEventKey:
		return OS.get_keycode_string((ev as InputEventKey).physical_keycode)
	return encode(ev)


## Every catalog action keeps a key and a pad event (tests and SE-4).
static func parity_ok() -> bool:
	for a in catalog().actions:
		if a == null or not InputMap.has_action(a.action):
			continue
		var has_key := false
		var has_pad := false
		for ev in InputMap.action_get_events(a.action):
			has_key = has_key or ev is InputEventKey
			has_pad = has_pad or device_of(ev) == PAD
		if not (has_key and has_pad):
			return false
	return true


# --- Applying ----------------------------------------------------------------

## Writes `overrides` into the InputMap and returns them cleaned (unknown
## actions and undecodable entries dropped with a warning, lists equal to the
## defaults removed). Actions without an override get their shipped events
## back; move_* keep their stick axes; deadzones are untouched. Then the
## debug pad events are stripped when dev tools are unavailable (D-158) and
## every mirror target (cinematic_skip) is rebuilt from its sources.
static func apply(overrides: Dictionary) -> Dictionary:
	snapshot_defaults()
	var cat := catalog()
	var clean := sanitize(overrides)
	for entry in cat.actions:
		if entry == null or not InputMap.has_action(entry.action):
			continue
		var action := entry.action
		var o: Dictionary = clean.get(String(action), {})
		if o.is_empty():
			_set_events(action, default_events(action))
			continue
		var events: Array[InputEvent] = []
		for ev in _events_for(o, action, KEY):
			events.append(ev)
		for ev in default_events(action):
			if is_stick(ev):
				events.append(ev)
		for ev in _events_for(o, action, PAD):
			events.append(ev)
		_set_events(action, events)
	var dev_ok := _dev_available()
	for action: StringName in _debug_actions():
		var evs: Array[InputEvent] = []
		for ev in default_events(action):
			if dev_ok or device_of(ev) != PAD:
				evs.append(ev)
		_set_events(action, evs)
	for m in cat.mirrors:
		_apply_mirror(m, clean)
	return clean


## Overrides with every invalid part dropped and every default-equal list
## removed (what Settings stores).
static func sanitize(overrides: Dictionary) -> Dictionary:
	snapshot_defaults()
	var cat := catalog()
	var out := {}
	for k: Variant in overrides:
		var action := StringName(str(k))
		if not cat.has_action(action) or not InputMap.has_action(action):
			push_warning("InputBindings: dropped saved bindings for unknown action '%s'" % str(k))
			continue
		var o: Variant = overrides[k]
		if not (o is Dictionary):
			push_warning("InputBindings: dropped malformed bindings for '%s'" % action)
			continue
		for device: StringName in [KEY, PAD]:
			if not (o as Dictionary).has(String(device)):
				continue
			var list := _clean_list((o as Dictionary)[String(device)], device, action)
			if list.is_empty() or list == _default_list(action, device):
				continue
			if not out.has(String(action)):
				out[String(action)] = {}
			(out[String(action)] as Dictionary)[String(device)] = Array(list)
	return out


# --- Internals ----------------------------------------------------------------

static func _set_events(action: StringName, events: Array[InputEvent]) -> void:
	InputMap.action_erase_events(action)
	for ev in events:
		InputMap.action_add_event(action, ev)


static func _events_for(o: Dictionary, action: StringName, device: StringName) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if o.has(String(device)):
		for s: String in _clean_list(o[String(device)], device, action):
			out.append(decode(s))
	if out.is_empty():
		for ev in default_events(action):
			if device_of(ev) == device and not is_stick(ev):
				out.append(ev)
	return out


## The shipped slot events of `action` on `device`, encoded (sticks excluded).
static func _default_list(action: StringName, device: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	for ev in default_events(action):
		if device_of(ev) == device and not is_stick(ev):
			out.append(encode(ev))
	return out


## Decodable, unique, right-device, non-stick entries, at most the slot count.
static func _clean_list(raw: Variant, device: StringName, action: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	if not (raw is Array or raw is PackedStringArray):
		push_warning("InputBindings: dropped malformed %s list for '%s'" % [device, action])
		return out
	for item: Variant in raw:
		var ev := decode(str(item))
		if ev == null or device_of(ev) != device or is_stick(ev):
			push_warning("InputBindings: dropped bad saved event '%s' for '%s'" % [str(item), action])
			continue
		var enc := encode(ev)
		if not out.has(enc):
			out.append(enc)
	var entry := RebindCatalog.get_catalog().entry(action)
	if entry and out.size() > entry.slot_count(device):
		out = out.slice(0, entry.slot_count(device))
	return out


## New overrides with `list` stored for (action, device), or the entry
## removed when the list equals the shipped one.
static func _with(overrides: Dictionary, action: StringName, device: StringName, list: PackedStringArray) -> Dictionary:
	var out := overrides.duplicate(true)
	var old: Variant = out.get(String(action), {})
	var d: Dictionary = (old as Dictionary).duplicate(true) if old is Dictionary else {}
	if list == _default_list(action, device):
		d.erase(String(device))
	else:
		d[String(device)] = Array(list)
	if d.is_empty():
		out.erase(String(action))
	else:
		out[String(action)] = d
	return out


## Why removing `enc` from `list` (action's events on device) is refused, or "".
static func _removal_refusal(action: StringName, device: StringName, list: PackedStringArray, enc: String) -> String:
	var label := _action_label(action)
	if is_locked(action, enc):
		return locked_text(action, enc)
	if list.size() <= 1:
		if device == KEY:
			return Loc.f("Keep at least one key for {action}.", {"action": label})
		return Loc.f("Keep at least one button for {action}.", {"action": label})
	if action == &"pause" and device == KEY:
		# Esc belongs to the browser in web fullscreen, and every platform
		# keeps a second pause key (R03.6).
		var others := 0
		for s in list:
			if s != enc and s != "k%d" % KEY_ESCAPE:
				others += 1
		if others == 0:
			return Loc.t("Pause needs one more key.")
	return ""


static func is_locked(action: StringName, enc: String) -> bool:
	var entry := catalog().entry(action)
	if entry == null or enc == "":
		return false
	if enc.begins_with("k") and locked_keys(action).has(enc.substr(1).to_int()):
		return true
	return entry.locked_pad.has(enc)


## Physical keycodes `action` can never lose on this platform.
static func locked_keys(action: StringName) -> PackedInt32Array:
	var entry := catalog().entry(action)
	var out := PackedInt32Array()
	if entry == null:
		return out
	out.append_array(entry.locked_keys)
	if _is_web():
		for w in catalog().web_locked_keys:
			if StringName(str(w.get("action", ""))) == action:
				for k: Variant in w.get("keys", []):
					if not out.has(int(k)):
						out.append(int(k))
	return out


static func locked_text(action: StringName, enc: String) -> String:
	return Loc.f("{key} stays on {action}.", {"key": event_label(decode(enc)), "action": _action_label(action)})


static func _action_label(action: StringName) -> String:
	var entry := catalog().entry(action)
	return Loc.t(entry.label) if entry else String(action)


static func _intersects(a: PackedStringArray, b: PackedStringArray) -> bool:
	for x in a:
		if b.has(x):
			return true
	return false


static func _debug_actions() -> Array[StringName]:
	var out: Array[StringName] = []
	for action: StringName in _defaults:
		if String(action).begins_with("debug_"):
			out.append(action)
	return out


## Rebuilds a mirror target from its sources when any source is overridden;
## otherwise the target keeps its shipped events (and order) exactly.
static func _apply_mirror(m: Dictionary, clean: Dictionary) -> void:
	var target := StringName(str(m.get("target", "")))
	if not InputMap.has_action(target):
		return
	var sources: Array = m.get("sources", [])
	var touched := false
	for s: Variant in sources:
		touched = touched or clean.has(str(s))
	if not touched:
		_set_events(target, default_events(target))
		return
	var keys := PackedStringArray()
	var pads := PackedStringArray()
	for s: Variant in sources:
		for ev in InputMap.action_get_events(StringName(str(s))):
			if is_stick(ev):
				continue
			var enc := encode(ev)
			if device_of(ev) == KEY and not keys.has(enc):
				keys.append(enc)
			elif device_of(ev) == PAD and not pads.has(enc):
				pads.append(enc)
	for k: Variant in m.get("fixed_keys", []):
		var enc := "k%d" % int(k)
		if not keys.has(enc):
			keys.append(enc)
	for p: Variant in m.get("fixed_pad", []):
		if not pads.has(str(p)):
			pads.append(str(p))
	var events: Array[InputEvent] = []
	for s in keys + pads:
		events.append(decode(s))
	_set_events(target, events)


static func _is_web() -> bool:
	return force_web == 1 if force_web >= 0 else BuildInfo.is_web()


## DevActions is loaded by path: Settings (the second autoload) compiles this
## file, and naming DevActions here would compile the dev tools (and Game)
## mid-cycle.
static func _dev_available() -> bool:
	var script := load(DEV_ACTIONS_PATH) as GDScript
	return script != null and bool(script.call("available"))


## InputGlyphs (autoload), read through the tree for the same reason.
static func _glyphs() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("InputGlyphs") if tree else null
