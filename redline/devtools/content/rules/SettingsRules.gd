extends RefCounted
## Settings, rebinding and accessibility data rules (M9 T03, D4 §11), run by
## ContentValidator.validate_m9 (RULE_MODULES):
## SE-1 catalog <-> Settings properties (every stored property except the
##      hand-written bindings/locale has exactly one row; every row names one)
## SE-2 choice counts and steps fit the property clamps
## SE-3 labels and descriptions: present, short, and free of shaming words (§24)
## SE-4 rebind catalog: actions exist with a key and a pad event; no two
##      actions live at the same time share an event unless whitelisted;
##      locked events and mirror sources exist
## SE-5 every glyph family names every pad button and axis a non-debug
##      action uses
## SE-6 AccessibilityConfig.validate()

const LABEL_MAX := 40
const DESCRIPTION_MAX := 90


static func run(v: ContentValidator) -> void:
	var cat := load(SettingsCatalog.PATH) as SettingsCatalog
	if cat == null:
		v.errors.append("[SE-1] %s does not load" % SettingsCatalog.PATH)
		return
	var settings := _settings()
	v.errors.append_array(catalog_errors(cat, settings))
	v.errors.append_array(clamp_errors(cat, settings))
	v.errors.append_array(wording_errors(cat))
	v.errors.append_array(rebind_errors(InputBindings.catalog()))
	v.errors.append_array(glyph_errors())
	var cfg := load(AccessibilityConfig.PATH) as AccessibilityConfig
	if cfg == null:
		v.errors.append("[SE-6] %s does not load" % AccessibilityConfig.PATH)
	else:
		for e in cfg.validate():
			v.errors.append("[SE-6] accessibility_config: %s" % e)


## SE-1.
static func catalog_errors(cat: SettingsCatalog, settings: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if settings == null:
		return out
	var props: PackedStringArray = settings.call("setting_properties")
	var counts := {}
	var cfg_keys := {}
	for d in cat.stored_defs():
		counts[String(d.key)] = int(counts.get(String(d.key), 0)) + 1
		var where := "%s/%s" % [d.section, d.cfg_name()]
		if cfg_keys.has(where):
			out.append("[SE-1] settings.cfg key %s is written by two rows" % where)
		cfg_keys[where] = true
		if not props.has(String(d.key)):
			out.append("[SE-1] row '%s' names no Settings property" % d.key)
	for d in cat.all_defs():
		if not d.is_stored() and d.key != &"" and not props.has(String(d.key)):
			out.append("[SE-1] row '%s' names no Settings property" % d.key)
	var hand: Array = (settings.get_script() as GDScript).get_script_constant_map().get("HAND_WRITTEN", [])
	for p in props:
		if hand.has(p):
			continue
		var n := int(counts.get(p, 0))
		if n != 1:
			out.append("[SE-1] Settings.%s has %d catalog rows (want exactly 1)" % [p, n])
	for p in cat.pages:
		if p == null:
			out.append("[SE-1] empty page in the settings catalog")
			continue
		for k in p.row_keys:
			if cat.def(StringName(k)) == null:
				out.append("[SE-1] page %s borrows unknown row '%s'" % [p.id, k])
	return out


## SE-2: a fresh Settings instance shows each property's clamp.
static func clamp_errors(cat: SettingsCatalog, settings: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if settings == null:
		return out
	var probe: Node = (settings.get_script() as GDScript).new()
	for d in cat.stored_defs():
		var current: Variant = probe.get(d.key)
		match d.kind:
			SettingDef.Kind.TOGGLE:
				if typeof(current) != TYPE_BOOL:
					out.append("[SE-2] toggle row '%s' is not a bool setting" % d.key)
				if d.choices.size() != 0 and d.choices.size() != 2:
					out.append("[SE-2] toggle row '%s' needs 0 or 2 labels" % d.key)
			SettingDef.Kind.CHOICE:
				if typeof(current) != TYPE_INT:
					out.append("[SE-2] choice row '%s' is not an int setting" % d.key)
					continue
				probe.set(d.key, 9999)
				var hi := int(probe.get(d.key))
				probe.set(d.key, -9999)
				var lo := int(probe.get(d.key))
				if lo != 0 or hi != d.choices.size() - 1:
					out.append("[SE-2] '%s' has %d choices but clamps to %d..%d" % [d.key, d.choices.size(), lo, hi])
				if int(current) < 0 or int(current) >= d.choices.size():
					out.append("[SE-2] '%s' default %d is not a choice" % [d.key, int(current)])
			SettingDef.Kind.STEPS:
				if typeof(current) != TYPE_FLOAT:
					out.append("[SE-2] steps row '%s' is not a float setting" % d.key)
					continue
				if d.steps.size() < 2:
					out.append("[SE-2] steps row '%s' has fewer than 2 steps" % d.key)
					continue
				for s in d.steps:
					probe.set(d.key, s)
					if absf(float(probe.get(d.key)) - s) > 0.0001:
						out.append("[SE-2] '%s' step %.2f is outside its clamp" % [d.key, s])
				if absf(d.steps[d.step_index(float(current))] - float(current)) > 0.0001:
					out.append("[SE-2] '%s' default %.2f is not a step" % [d.key, float(current)])
		probe.set(d.key, current)
	probe.free()
	return out


## SE-3.
static func wording_errors(cat: SettingsCatalog) -> PackedStringArray:
	var out := PackedStringArray()
	var texts: Array = []
	for d in cat.all_defs():
		var who := "row '%s'" % (d.key if d.key != &"" else d.action)
		if d.label.strip_edges() == "":
			out.append("[SE-3] %s has no label" % who)
		if d.label.length() > LABEL_MAX:
			out.append("[SE-3] %s label is %d characters (max %d)" % [who, d.label.length(), LABEL_MAX])
		if d.description.length() > DESCRIPTION_MAX:
			out.append("[SE-3] %s description is %d characters (max %d)" % [who, d.description.length(), DESCRIPTION_MAX])
		texts.append([who, d.label])
		texts.append([who, d.description])
		for c in d.choices:
			texts.append([who, c])
	for p in cat.pages:
		if p != null:
			texts.append(["page %s" % p.id, p.title])
			texts.append(["page %s" % p.id, p.link_label])
	texts.append(["assist header", cat.assist_header])
	texts.append(["reset prompt", cat.reset_all_prompt])
	var cfg := load(AccessibilityConfig.PATH) as AccessibilityConfig
	if cfg:
		for r in cfg.rules:
			if r != null:
				texts.append(["assist rule '%s'" % r.cause_prefix, r.text])
	for a in InputBindings.catalog().actions:
		if a != null:
			texts.append(["rebind %s" % a.action, a.label])
	for t: Array in texts:
		for w in cat.forbidden_in(str(t[1])):
			out.append("[SE-3] %s uses '%s' (§24: options never shame the player)" % [t[0], w])
	return out


## SE-4.
static func rebind_errors(rc: RebindCatalog) -> PackedStringArray:
	var out := PackedStringArray()
	if rc == null:
		out.append("[SE-4] %s does not load" % RebindCatalog.PATH)
		return out
	for e in rc.validate():
		out.append("[SE-4] %s" % e)
	for a in rc.actions:
		if a == null:
			continue
		if not InputMap.has_action(a.action):
			out.append("[SE-4] rebind action %s is not in the InputMap" % a.action)
			continue
		var evs := InputBindings.default_events(a.action)
		var has_key := false
		var has_pad := false
		var encoded := PackedStringArray()
		for ev in evs:
			has_key = has_key or ev is InputEventKey
			has_pad = has_pad or InputBindings.device_of(ev) == InputBindings.PAD
			encoded.append(InputBindings.encode(ev))
		if not (has_key and has_pad):
			out.append("[SE-4] %s ships without a key and a pad event" % a.action)
		for k in a.locked_keys:
			if not encoded.has("k%d" % k):
				out.append("[SE-4] %s locks key %d it does not ship with" % [a.action, k])
		for p in a.locked_pad:
			if not encoded.has(p):
				out.append("[SE-4] %s locks pad event %s it does not ship with" % [a.action, p])
	out.append_array(overlap_errors(rc))
	for m in rc.mirrors:
		if not InputMap.has_action(StringName(str(m.get("target", "")))):
			out.append("[SE-4] mirror target %s is not an action" % m.get("target", ""))
		for s: Variant in m.get("sources", []):
			if not rc.has_action(StringName(str(s))):
				out.append("[SE-4] mirror source %s is not a rebindable action" % s)
	return out


## No two actions live at the same time share a shipped event unless the
## pair (and event) is on the allowed_overlaps whitelist.
static func overlap_errors(rc: RebindCatalog) -> PackedStringArray:
	var out := PackedStringArray()
	var acts := rc.actions.filter(func(a: RebindActionData) -> bool: return a != null and InputMap.has_action(a.action))
	for i in acts.size():
		for j in range(i + 1, acts.size()):
			var a := acts[i] as RebindActionData
			var b := acts[j] as RebindActionData
			var live := false
			for c in a.contexts:
				live = live or b.contexts.has(c)
			if not live:
				continue
			for ea in InputBindings.default_events(a.action):
				for eb in InputBindings.default_events(b.action):
					if not InputBindings.events_equal(ea, eb):
						continue
					var enc := InputBindings.encode(ea)
					if not rc.overlap_allowed(a.action, b.action, InputBindings.device_of(ea), enc):
						out.append("[SE-4] %s and %s share %s while both are live (not whitelisted)" % [a.action, b.action, enc])
	return out


## SE-5.
static func glyph_errors() -> PackedStringArray:
	var out := PackedStringArray()
	var used := {}
	for action in InputMap.get_actions():
		if String(action).begins_with("debug_"):
			continue
		for ev in InputBindings.default_events(action):
			if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				used[InputBindings.encode(ev)] = action
	for id: String in ["xbox", "playstation", "nintendo"]:
		var path := "res://data/input/glyphs/%s.tres" % id
		var gs := load(path) as GlyphSet
		if gs == null:
			out.append("[SE-5] glyph set %s does not load" % id)
			continue
		for enc: String in used:
			var named := ""
			if enc.begins_with("b"):
				named = gs.button_name(enc.substr(1).to_int())
			else:
				named = str(gs.axes.get(enc, ""))
			if named == "":
				out.append("[SE-5] glyph set %s has no name for %s (used by %s)" % [id, enc, used[enc]])
	return out


static func _settings() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Settings") if tree else null
