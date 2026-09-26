class_name AccessibilityDevActions
extends RefCounted
## Dev console helpers for the §24 options and the adaptive-assist advisor
## (M9 D4 §12, the M6 rule: every dev tool is a DevActions-style function).
## Debug builds only (the dev console never opens in a release export). The
## presets write the developer's own settings file, like the Settings menu.

## Every assist on at its strongest ordinary value (never the Redline Core).
const ALL_ASSISTS := {"reactor_mode": 1, "burnout_hurts": false, "damage_assist": 2, "aim_assist": 2,
	"generous_checkpoints": true, "jump_hold_mode": 1, "map_hints": 2}
## The readability preset: high contrast, 150 % UI, strong backdrop dim.
const READABLE := {"high_contrast": true, "ui_scale": 2, "background_dim": 2}


static func apply_all_assists() -> void:
	_apply(ALL_ASSISTS)


static func apply_readable_preset() -> void:
	_apply(READABLE)


## Off -> red-green -> blue-yellow -> Off. Returns the new mode.
static func cycle_colorblind() -> int:
	var d := Settings.settings_catalog().def(&"colorblind_mode") if Settings.settings_catalog() else null
	var n := d.value_count() if d and d.value_count() > 0 else 3
	_apply({"colorblind_mode": (Settings.colorblind_mode + 1) % n})
	return Settings.colorblind_mode


## Every page with its own reset back to its defaults (the Settings menu's
## "Reset all settings"); bindings, playtest rows and language stay.
static func restore_defaults() -> void:
	Settings.reset_keys(Settings.reset_all_keys())
	_after_change()


static func reset_controls() -> void:
	Settings.bindings = InputBindings.reset(Settings.bindings)
	InputBindings.apply(Settings.bindings)
	Settings.save_settings()
	EventBus.input_bindings_changed.emit(&"")


## One line per rebound action ("defaults" when nothing is rebound), to the
## log. Returns the text.
static func print_bindings() -> String:
	var lines := PackedStringArray()
	for action: String in Settings.bindings:
		lines.append("%s: %s" % [action, JSON.stringify(Settings.bindings[action])])
	var text := "BINDINGS " + ("defaults" if lines.is_empty() else "; ".join(lines))
	print(text)
	return text


## The advisor Main instanced (null in a bare test tree).
static func advisor() -> AssistAdvisor:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.get_first_node_in_group(&"assist_advisor") as AssistAdvisor


## "Trigger assist suggestion (current room)": the room's death count goes
## to its threshold and the card opens now. Returns whether it opened.
static func trigger_suggestion_here() -> bool:
	var a := advisor()
	return a != null and a.dev_trigger_here()


static func toggle_advisor_quiet() -> bool:
	AssistAdvisor.dev_quiet = not AssistAdvisor.dev_quiet
	return AssistAdvisor.dev_quiet


## Readable state for the page header.
static func summary() -> String:
	var tags := Settings.active_assists()
	return "assists: %s · contrast %s · UI %d · dim %d · colour %d · advisor %s" % [
		"none" if tags.is_empty() else ", ".join(tags), "on" if Settings.high_contrast else "off",
		Settings.ui_scale, Settings.background_dim, Settings.colorblind_mode,
		"quiet" if AssistAdvisor.dev_quiet else ("on" if Settings.assist_suggestions else "off")]


static func _apply(values: Dictionary) -> void:
	for k: String in values:
		Settings.set(k, values[k])
	if values.has("reactor_mode"):
		var room := SceneRouter.current_room as Room
		if room and is_instance_valid(room.player):
			room.player.reactor.apply_mode(Settings.reactor_mode)
	_after_change()


static func _after_change() -> void:
	Settings.save_settings()
	UiTheme.invalidate()
	EventBus.settings_changed.emit()
