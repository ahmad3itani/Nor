class_name RedlineTestCase
extends Node
## Minimal test base (no third-party dependency). Methods named test_* are run
## in order; they may await physics frames. Use check()/check_near() to assert.

var failures: PackedStringArray = []
var _current_test: String = ""


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append("%s: %s" % [_current_test, message])


func check_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	check(absf(actual - expected) <= tolerance,
		"%s (expected %.3f +/- %.3f, got %.3f)" % [message, expected, tolerance, actual])


func physics_frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


# --- M8 shared helpers (T01 is the only editor) ---

## Presses every action on the same frame, right after SceneTree.process_frame
## (emitted just before every node's _process), so _process that frame sees
## is_action_just_pressed; releases them after `hold_frames` process frames.
## A real press maps to several actions at once (pad A = jump + ui_accept +
## cinematic_skip), hence the array. M8 tests never use parse_input_event (its
## accumulated-input flush makes the frame order unreliable headless).
func press_actions(actions: Array[StringName], hold_frames: int) -> void:
	await get_tree().process_frame
	for a in actions:
		Input.action_press(a)
	for i in hold_frames:
		await get_tree().process_frame
	for a in actions:
		Input.action_release(a)


func press_action(action: StringName, hold_frames: int) -> void:
	var one: Array[StringName] = [action]
	await press_actions(one, hold_frames)


## Height a MenuScreen's content needs once autowrap labels settle (they take
## more than one sort pass, hence 2 frames). Every '<= 270 without scrolling'
## test uses it. M9 (R03.4): menus scroll, so this measures the rows plus the
## panel margins, not the capped panel (see panel_height).
func menu_height(menu: MenuScreen) -> float:
	return await content_height(menu)


## The rows' full height plus the panel's top and bottom content margins:
## what the panel would need without a scroll area.
func content_height(menu: MenuScreen) -> float:
	for i in 2:
		await get_tree().process_frame
	var sb := menu._panel.get_theme_stylebox("panel")
	var margins := sb.get_margin(SIDE_TOP) + sb.get_margin(SIDE_BOTTOM) if sb else 0.0
	return menu._body.get_combined_minimum_size().y + margins


## The panel's real height (capped by the scroll area): 'fits or scrolls'.
func panel_height(menu: MenuScreen) -> float:
	for i in 2:
		await get_tree().process_frame
	return menu._panel.get_combined_minimum_size().y


const _M8_SETTING_KEYS := [
	"subtitle_size", "subtitle_background", "speaker_labels", "subtitle_speed",
	"cinematic_skip_hold", "memories_at_anchors", "_subtitle_size_override",
]


## Settings._ready loaded the developer's real user://settings.cfg, so tests
## that rely on the M8 defaults snapshot and set them here (before_each) and
## hand the snapshot to restore_m8_settings (after_each).
func use_default_m8_settings() -> Dictionary:
	var snap := {}
	for k in _M8_SETTING_KEYS:
		snap[k] = Settings.get(k)
	Settings.subtitle_size = 0
	Settings.subtitle_background = 1
	Settings.speaker_labels = true
	Settings.subtitle_speed = 0
	Settings.cinematic_skip_hold = true
	Settings.memories_at_anchors = true
	Settings._subtitle_size_override = -1
	return snap


func restore_m8_settings(snap: Dictionary) -> void:
	for k in snap:
		Settings.set(k, snap[k])


# --- M9 settings helpers (T03) ---

## Every stored setting (catalog keys, bindings, locale) plus the session
## overrides, for tests that change Settings; hand it to restore_settings.
func snapshot_settings() -> Dictionary:
	var snap := Settings.snapshot()
	snap["_path"] = Settings._path
	snap["_subtitle_size_override"] = Settings._subtitle_size_override
	snap["_locale_override"] = Settings._locale_override
	return snap


## Puts a snapshot_settings() back and resets the InputMap to the snapshot's
## bindings (none in a test run), so no rebind leaks into the next test.
func restore_settings(snap: Dictionary) -> void:
	Settings.restore(snap)
	Settings._path = str(snap.get("_path", Settings.SETTINGS_PATH))
	Settings._subtitle_size_override = int(snap.get("_subtitle_size_override", -1))
	Settings._locale_override = str(snap.get("_locale_override", ""))
	InputBindings.apply(Settings.bindings)
	UiTheme.invalidate()
