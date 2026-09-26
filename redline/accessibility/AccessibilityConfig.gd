class_name AccessibilityConfig
extends Resource
## Tuning for every §24 option that has numbers (bible §31 resource name,
## D4 §2.2). Settings stores the player's choice as an index; this resource
## says what each index means, so tuning never touches code and the menu
## labels stay honest. Loaded at runtime by Settings (never a preload const,
## CLAUDE.md pitfall) and exposed as Settings.access_config.
##
## T03 writes the final data (data/accessibility/accessibility_config.tres);
## T11 (assists, advisor) and T12 (haptics, comfort) only read it.

const PATH := "res://data/accessibility/accessibility_config.tres"
## Localization (D5): damage source ids, never shown.
const LOC_EXEMPT := ["damage_exempt_sources"]

@export_group("Aim assist")
## index = Settings.aim_assist (0 Off, 1 Light, 2 Strong).
@export var aim_cone_deg: PackedFloat32Array = [0.0, 14.0, 32.0]
@export var aim_range_px: PackedFloat32Array = [0.0, 170.0, 230.0]
@export var aim_require_on_screen: bool = true

@export_group("Damage assist")
## index = Settings.damage_assist: 0 Off, 1 Bosses reduced, 2 All reduced,
## 3 All greatly reduced (D-152: separate from the Core mode).
@export var damage_scale: PackedFloat32Array = [1.0, 0.5, 0.5, 0.25]
@export var damage_bosses_only: Array[bool] = [false, true, false, false]
## Sources never scaled (the reactor setting covers burnout).
@export var damage_exempt_sources: PackedStringArray = ["burnout"]

@export_group("UI scale")
## index = Settings.ui_scale (100 %, 125 %, 150 %).
@export var ui_scales: PackedFloat32Array = [1.0, 1.25, 1.5]
## Panel content height (px of the 270 canvas) before a menu scrolls.
@export var menu_max_height: int = 250
## Default menu panel width per UI scale (clamped to the viewport - 16).
@export var menu_panel_width: PackedInt32Array = [360, 400, 460]

@export_group("Adaptive assist (§23)")
## Deaths in one boss-fight context before a suggestion.
@export var boss_deaths: int = 4
## Deaths in one room without leaving it.
@export var room_deaths: int = 5
## Counted deaths expire after this many seconds (real time).
@export var window_seconds: float = 900.0
## Minimum time between two suggestions.
@export var cooldown_seconds: float = 1200.0
@export var max_per_session: int = 2
## Cause -> suggested settings, first match wins (D4 §10.3).
@export var rules: Array[AssistRule] = []

@export_group("Haptics")
## One row per EventBus signal Haptics listens to (D4 §6).
@export var haptics: Array[HapticEvent] = []

@export_group("Comfort")
## index = Settings.background_dim (Off, Some, Strong): backdrop darkening.
@export var background_dim: PackedFloat32Array = [0.0, 0.3, 0.55]
## With flash reduction on, nothing flashes faster than this (WCAG 2.3.1).
@export var flash_max_hz: float = 3.0

@export_group("Input")
## index = Settings.rebind_wait: seconds a rebind capture listens before it
## gives up (0 = no limit; Esc, Backspace or pad Start always cancel).
@export var rebind_timeout_sec: PackedFloat32Array = [5.0, 10.0, 0.0]
## Real time a capture waits (after every held key and button is released)
## before it listens, so the confirm press never binds itself.
@export var rebind_arm_sec: float = 0.15
## A trigger must pass this before it counts as a press in a capture.
@export var rebind_trigger_threshold: float = 0.6
## "Always full height" jump: the latch lets go after this many frames at most
## (T11 PlayerInputSource reads it).
@export var jump_latch_max_frames: int = 40

@export_group("Text")
## Text auto-advance (D-110): a fully typed line stays for
## base + chars x per_char seconds, x SubtitleStyle.time_scale().
@export var auto_advance_base_s: float = 1.2
@export var auto_advance_per_char_s: float = 0.045


## Reading time of a fully typed line before auto-advance moves on (before
## the subtitle-speed scale).
func auto_advance_seconds(chars: int) -> float:
	return auto_advance_base_s + maxi(chars, 0) * auto_advance_per_char_s


## The capture timeout for a Settings.rebind_wait index (0 = no limit).
func rebind_timeout(index: int) -> float:
	if rebind_timeout_sec.is_empty():
		return 0.0
	return rebind_timeout_sec[clampi(index, 0, rebind_timeout_sec.size() - 1)]


func ui_scale_factor(index: int) -> float:
	if ui_scales.is_empty():
		return 1.0
	return ui_scales[clampi(index, 0, ui_scales.size() - 1)]


func panel_width(index: int) -> int:
	if menu_panel_width.is_empty():
		return 360
	return menu_panel_width[clampi(index, 0, menu_panel_width.size() - 1)]


## The HapticEvent row for an EventBus signal, or null.
func haptic(event: StringName) -> HapticEvent:
	for h in haptics:
		if h != null and h.event == event:
			return h
	return null


## ContentValidator resource protocol (SE-6): array lengths per group match
## the Settings choices, every number sits in its sane range.
func validate() -> PackedStringArray:
	var out := PackedStringArray()
	if aim_cone_deg.size() != 3 or aim_range_px.size() != 3:
		out.append("aim assist needs 3 cone and 3 range values (Off, Light, Strong)")
	for c in aim_cone_deg:
		if c < 0.0 or c >= 90.0:
			out.append("aim cone %.1f deg outside [0, 90)" % c)
	if aim_cone_deg.size() > 0 and (aim_cone_deg[0] != 0.0 or (aim_range_px.size() > 0 and aim_range_px[0] != 0.0)):
		out.append("aim assist Off (index 0) must have cone and range 0")
	if damage_scale.size() != 4 or damage_bosses_only.size() != 4:
		out.append("damage assist needs 4 scale and 4 bosses-only values")
	for s in damage_scale:
		if s <= 0.0 or s > 1.0:
			out.append("damage scale %.2f outside (0, 1]" % s)
	if damage_scale.size() > 0 and damage_scale[0] != 1.0:
		out.append("damage assist Off (index 0) must scale by 1.0")
	if ui_scales.size() != 3 or menu_panel_width.size() != ui_scales.size():
		out.append("ui scale needs 3 factors and 3 panel widths")
	for f in ui_scales:
		if f < 1.0 or f > 2.0:
			out.append("ui scale %.2f outside [1, 2]" % f)
	if ui_scales.size() > 0 and ui_scales[0] != 1.0:
		out.append("ui scale index 0 must be 1.0 (the M8 look)")
	if menu_panel_width.size() > 0 and menu_panel_width[0] != 360:
		out.append("menu panel width at 100 %% must stay 360 (the M8 look), got %d" % menu_panel_width[0])
	if menu_max_height < 120 or menu_max_height > 258:
		out.append("menu_max_height %d outside [120, 258]" % menu_max_height)
	if boss_deaths < 2 or room_deaths < 2:
		out.append("adaptive thresholds below 2 deaths")
	if window_seconds <= 0.0 or cooldown_seconds < 0.0 or max_per_session < 1:
		out.append("adaptive window/cooldown/session cap out of range")
	if rules.is_empty():
		out.append("no adaptive assist rules")
	for r in rules:
		if r == null:
			out.append("empty adaptive assist rule")
			continue
		out.append_array(r.validate())
	var seen := {}
	for h in haptics:
		if h == null:
			out.append("empty haptic row")
			continue
		out.append_array(h.validate())
		if seen.has(h.event):
			out.append("haptic %s listed twice" % h.event)
		seen[h.event] = true
	if background_dim.size() != 3:
		out.append("background dim needs 3 values (Off, Some, Strong)")
	for d in background_dim:
		if d < 0.0 or d >= 1.0:
			out.append("background dim %.2f outside [0, 1)" % d)
	if flash_max_hz <= 0.0 or flash_max_hz > 3.0:
		out.append("flash_max_hz %.1f outside (0, 3] (WCAG 2.3.1)" % flash_max_hz)
	if rebind_timeout_sec.size() != 3:
		out.append("rebind wait needs 3 values (5 s, 10 s, No limit)")
	for t in rebind_timeout_sec:
		if t < 0.0:
			out.append("rebind timeout %.1f below 0" % t)
	if rebind_arm_sec < 0.0 or rebind_arm_sec > 1.0:
		out.append("rebind_arm_sec %.2f outside [0, 1]" % rebind_arm_sec)
	if rebind_trigger_threshold <= 0.2 or rebind_trigger_threshold > 1.0:
		out.append("rebind trigger threshold %.2f outside (0.2, 1]" % rebind_trigger_threshold)
	if jump_latch_max_frames < 10 or jump_latch_max_frames > 90:
		out.append("jump_latch_max_frames %d outside 10..90" % jump_latch_max_frames)
	if auto_advance_base_s <= 0.0 or auto_advance_per_char_s <= 0.0:
		out.append("text auto-advance times must be positive")
	return out
