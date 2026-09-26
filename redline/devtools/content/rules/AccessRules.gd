class_name AccessRules
extends RefCounted
## Visual accessibility data rules (M9 T12, D4 §7.3, §11 item 5), run by
## ContentValidator.validate_m9 (RULE_MODULES):
## AC-1 every palette loads, has every semantic key, and the default palette
##      defines every role key (so the default look is the old constants)
## AC-2 every palette colour has >= 3:1 contrast against UiTheme.BG
## AC-3 under each of its own CVD simulations (none for the default palette)
##      a palette keeps danger / warning / info pairwise >= min_state_distance
##      apart in OKLab
## AC-4 every HapticEvent row names an EventBus signal (Haptics connects by name)

const MIN_CONTRAST := 3.0


static func run(v: ContentValidator) -> void:
	var pals: Array[AccessPalette] = []
	for path in Palette.PATHS:
		var p := load(path) as AccessPalette if ResourceLoader.exists(path) else null
		if p == null:
			v.errors.append("[AC-1] %s is missing or not an AccessPalette" % path)
			continue
		pals.append(p)
	for i in pals.size():
		v.errors.append_array(completeness_errors(pals[i], i == 0 and pals[i].id == &"default"))
		v.errors.append_array(contrast_errors(pals[i]))
		v.errors.append_array(state_distance_errors(pals[i]))
	var cfg := load(AccessibilityConfig.PATH) as AccessibilityConfig
	if cfg:
		v.errors.append_array(haptic_errors(cfg))


## AC-1.
static func completeness_errors(p: AccessPalette, is_default: bool) -> PackedStringArray:
	var out := PackedStringArray()
	for e in p.validate():
		out.append("[AC-1] %s" % e)
	if is_default:
		for role in AccessPalette.ROLES:
			if not p.colors.has(role):
				out.append("[AC-1] the default palette must define role '%s' (the old constant)" % role)
	return out


## AC-2.
static func contrast_errors(p: AccessPalette) -> PackedStringArray:
	var out := PackedStringArray()
	var bg := Color(UiTheme.BG, 1.0)
	for k in p.keys():
		var c := p.resolve(k)
		var ratio := ColorVision.contrast(c, bg)
		if ratio < MIN_CONTRAST:
			out.append("[AC-2] palette %s: '%s' has %.2f:1 contrast on the UI background (want >= %.1f)" % [p.id, k, ratio, MIN_CONTRAST])
	return out


## AC-3: the smallest state-pair distance per simulation, as
## [[simulation, key_a, key_b, distance], ...] (tests print it).
static func state_distances(p: AccessPalette) -> Array:
	var out: Array = []
	var sims: Array[StringName] = []
	for s in p.simulations:
		sims.append(StringName(s))
	if sims.is_empty():
		sims.append(&"none")
	var keys := AccessPalette.STATE_KEYS
	for s in sims:
		for i in keys.size():
			for j in range(i + 1, keys.size()):
				var a := ColorVision.simulate(p.resolve(keys[i]), s)
				var b := ColorVision.simulate(p.resolve(keys[j]), s)
				out.append([s, keys[i], keys[j], ColorVision.oklab_distance(a, b)])
	return out


static func state_distance_errors(p: AccessPalette) -> PackedStringArray:
	var out := PackedStringArray()
	for row: Array in state_distances(p):
		if float(row[3]) < p.min_state_distance:
			out.append("[AC-3] palette %s under %s: %s vs %s only %.3f apart in OKLab (want >= %.2f)" % [
				p.id, row[0], row[1], row[2], row[3], p.min_state_distance])
	return out


## AC-4.
static func haptic_errors(cfg: AccessibilityConfig) -> PackedStringArray:
	var out := PackedStringArray()
	var bus: Object = _event_bus()
	if bus == null:
		return out
	for h in cfg.haptics:
		if h != null and not bus.has_signal(h.event):
			out.append("[AC-4] haptic row '%s' names no EventBus signal" % h.event)
	return out


static func _event_bus() -> Object:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("EventBus") if tree and tree.root else null
