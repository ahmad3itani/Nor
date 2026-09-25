class_name SkipGate
extends RefCounted
## The one advance/skip rule for sequences, memory vignettes and endings
## (bible §17 "skippable repeated intros", §24 "cinematic skip"; D-108).
##
## Tap and hold are exclusive, because one button (Space / Enter / pad A) is
## cinematic_skip, jump and ui_accept at once:
## - a TAP (released within TAP_SECONDS, fired on release, never on press)
##   only advances text, and only if an advance action was part of the press;
## - a SKIP is a hold of cinematic_skip: HOLD_SECONDS on a first view,
##   REPEAT_HOLD_SECONDS on a repeat view (still a hold, since a tap advances).
##   A hold never advances text; releasing early just resets the bar;
## - "Skip scenes: Press twice" (Settings.cinematic_skip_hold == false): a tap
##   of cinematic_skip inside the window that arms ARM_DELAY_SECONDS after a
##   TAP skips. Taps in the dead window are swallowed (a fast double tap never
##   advances twice), and on a first view the first window of the scene only
##   teaches, so a reader's quick double tap never skips an unseen scene.
## Presses that began before the gate could see them (the entry mash, the key
## that closed a menu, a press carried over a pause) are ignored until released.
##
## update() is pure logic (tests drive it); poll() feeds it from Input.

enum Out { NONE, TAP, SKIP }

## Same list as ui/dialogue/DialogueBox.gd ADVANCE_ACTIONS (that script has no
## class_name, so everything else reads this one; a test pins the equality).
const ADVANCE_ACTIONS: Array[StringName] = [&"interact", &"ui_accept", &"jump", &"attack_light"]
const TAP_SECONDS := 0.25
const HOLD_SECONDS := 0.8
const REPEAT_HOLD_SECONDS := 0.4
const DOUBLE_TAP_SECONDS := 0.6
const ARM_DELAY_SECONDS := 0.15
const GRACE_SECONDS := 0.25
const PROMPT_SHOW_SECONDS := 2.0

var first_view: bool = true
## Whether the skip prompt should be drawn this frame (see prompt_text()).
var prompt_visible: bool = false

var _grace_left: float = GRACE_SECONDS
## A press seen already down (or begun during grace) waits for a full release.
var _blocked: bool = false
var _tracking: bool = false
var _press_time: float = 0.0
var _press_advance: bool = false
var _press_skip: bool = false
var _press_in_window: bool = false
var _press_in_dead: bool = false
var _progress: float = 0.0
var _prompt_left: float = 0.0
## Press-twice window: dead for _arm_left, then armed for _window_left.
var _arm_left: float = 0.0
var _window_left: float = 0.0
var _window_teaches: bool = false
var _taught: bool = false


func _init(is_first_view: bool = true) -> void:
	first_view = is_first_view
	# Repeat views show "Hold [x] to skip" from frame 0; first views stay clean.
	_update_prompt(Settings.cinematic_skip_hold)


func update(delta: float, skip_held: bool, skip_just_pressed: bool, adv_held: bool, adv_just_pressed: bool) -> int:
	var hold_mode := Settings.cinematic_skip_hold
	_grace_left = maxf(_grace_left - delta, 0.0)
	_prompt_left = maxf(_prompt_left - delta, 0.0)
	if _arm_left > 0.0:
		_arm_left = maxf(_arm_left - delta, 0.0)
	elif _window_left > 0.0:
		_window_left = maxf(_window_left - delta, 0.0)
	var out := _step(delta, hold_mode, skip_held, skip_just_pressed, adv_held, adv_just_pressed)
	_update_prompt(hold_mode)
	return out


func _step(delta: float, hold_mode: bool, skip_held: bool, skip_just: bool, adv_held: bool, adv_just: bool) -> int:
	var any_held := skip_held or adv_held
	var any_just := skip_just or adv_just
	if _blocked:
		if any_held:
			return Out.NONE
		_blocked = false
	if not _tracking:
		if any_just and _grace_left <= 0.0:
			_begin_press(skip_held or skip_just, adv_held or adv_just)
		elif any_held:
			_blocked = true
		return Out.NONE
	if any_held:
		_press_time += delta
		if skip_held and _press_time >= TAP_SECONDS:
			_progress = _press_time
			if _press_time >= _hold_seconds():
				_end_press()
				_blocked = true
				return Out.SKIP
		else:
			_progress = 0.0
		return Out.NONE
	# Released.
	var was_tap := _press_time < TAP_SECONDS
	_end_press()
	if not was_tap:
		return Out.NONE
	if not hold_mode:
		if _press_in_dead:
			return Out.NONE
		if _press_in_window and _press_skip:
			_window_left = 0.0
			return Out.SKIP
	if not _press_advance:
		return Out.NONE
	if not hold_mode:
		_open_window()
	return Out.TAP


func _begin_press(with_skip: bool, with_advance: bool) -> void:
	_tracking = true
	_press_time = 0.0
	_progress = 0.0
	_press_skip = with_skip
	_press_advance = with_advance
	_press_in_dead = _arm_left > 0.0
	_press_in_window = _arm_left <= 0.0 and _window_left > 0.0 and not _window_teaches
	_prompt_left = PROMPT_SHOW_SECONDS


func _end_press() -> void:
	_tracking = false
	_press_time = 0.0
	_progress = 0.0


## Press twice: every TAP opens a window. On a first view the scene's first
## window only teaches (shows "again to skip"); later windows can skip.
func _open_window() -> void:
	_arm_left = ARM_DELAY_SECONDS
	_window_left = DOUBLE_TAP_SECONDS
	_window_teaches = first_view and not _taught
	_taught = true


func _hold_seconds() -> float:
	return HOLD_SECONDS if first_view else REPEAT_HOLD_SECONDS


func _update_prompt(hold_mode: bool) -> void:
	if hold_mode:
		prompt_visible = not first_view or _prompt_left > 0.0 or _progress > 0.0
	else:
		prompt_visible = _arm_left > 0.0 or _window_left > 0.0 or _progress > 0.0


## Restart the grace and drop the tracked press. Callers invoke it on the first
## frame after the tree was paused, so the "Resume" press never skips or advances.
func notify_unpaused() -> void:
	_grace_left = GRACE_SECONDS
	_end_press()
	_blocked = true


## Hold bar fill 0..1 (0 unless cinematic_skip is being held past a tap).
func progress_ratio() -> float:
	return clampf(_progress / _hold_seconds(), 0.0, 1.0)


func prompt_text() -> String:
	var glyph := InputGlyphs.label(&"cinematic_skip")
	if Settings.cinematic_skip_hold or _progress > 0.0:
		return "Hold [%s] to skip" % glyph
	return "[%s] again to skip" % glyph


## Feeds the gate from the live Input state.
static func poll(gate: SkipGate, delta: float) -> int:
	var adv_held := false
	var adv_just := false
	for a in ADVANCE_ACTIONS:
		if Input.is_action_pressed(a):
			adv_held = true
		if Input.is_action_just_pressed(a):
			adv_just = true
	return gate.update(delta, Input.is_action_pressed(&"cinematic_skip"),
		Input.is_action_just_pressed(&"cinematic_skip"), adv_held, adv_just)
