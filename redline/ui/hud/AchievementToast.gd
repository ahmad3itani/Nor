class_name AchievementToast
extends CanvasLayer
## The achievement toast (M9 D1 §4.6, T07). Platform instantiates it as a
## child at layer 70: above the HUD (50) and the cinematic overlay (65),
## under menus (80) and the memory player (85).
##
## Design intent:
## - Story beats come first. A toast waits while the tree is paused (a menu,
##   the Act I card), a scene locks input, a memory plays or a room
##   transition runs, and resumes where it stopped. Platform already holds the
##   announcement during a challenge run and its result card (R02.9).
## - It never takes focus, never pauses and never uses CombatHud's hint queue
##   (a lesson line is never delayed by a toast, D-103).
## - Several unlocks at once (a retroactive load, D-143) collapse into one
##   toast when toast_collapse_at or more are waiting.
## - Settings.achievement_toasts off: nothing is shown or played; the unlock
##   is still recorded and listed in the menu.
## - Settings.flash_reduction: fade only, no slide, no glyph pulse.
## - Top centre, 168 x 30 at native 480 x 270 (x = (view.x - w) / 2, y = 6),
##   scaled with the UI size. It stays clear of the style rank (top right),
##   the run timer (top left), the Core block (bottom left) and the boss bar.
##   In the compact HUD (UI size above 100 %) the boss bar moves to the top
##   centre, so the toast drops just under the boss block.

## No resource text of its own: the lines are Loc literals and data text
## (AchievementData.LOC_FIELDS).
const LOC_FIELDS := {}
const LOC_EXEMPT := []
const SIZE := Vector2(168, 30)
const TOP := 6.0
const SLIDE_S := 0.18
const FADE_OUT_S := 0.25
const PULSE_S := 0.6
const SFX := &"achievement"
const BG := Color(0.04, 0.03, 0.07, 0.88)
## CombatHud has no class_name; its layout helpers are static.
const HUD := preload("res://ui/hud/CombatHud.gd")

## Waiting unlock ids (in unlock order).
var queue: PackedStringArray = []
## The toast on screen: {"ids": PackedStringArray, "t": seconds shown}; {}
## when none.
var current: Dictionary = {}
## Toasts shown so far (tests).
var shown_count: int = 0

var _root: Control


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.focus_mode = Control.FOCUS_NONE
	_root.draw.connect(_draw_toast)
	add_child(_root)
	EventBus.achievement_unlocked.connect(_on_unlocked)


func _on_unlocked(id: String, _retroactive: bool) -> void:
	enqueue(id)


## Queues `id` for display (the dev "Test toast" row calls this directly, so
## nothing is written to the store).
func enqueue(id: String) -> void:
	if not Settings.achievement_toasts or AchievementLibrary.by_id(id) == null:
		return
	queue.append(id)


## Drops everything (test teardown, dev reset).
func clear() -> void:
	queue.clear()
	current = {}
	if _root:
		_root.queue_redraw()


## Whether the toast must wait now (see the header).
func held() -> bool:
	if not is_inside_tree() or get_tree().paused:
		return true
	if Cinematics.locks_input() or SceneRouter.transitioning:
		return true
	var mem := MemoryScenePlayer.active_instance
	return is_instance_valid(mem) and mem.is_playing()


func showing() -> bool:
	return not current.is_empty()


func _process(delta: float) -> void:
	var hold := held()
	visible = not hold
	if hold:
		return
	if not Settings.achievement_toasts:
		# Turned off while some were waiting: they stay unlocked, unshown.
		clear()
		return
	if current.is_empty() and not queue.is_empty():
		_start_next()
	if not current.is_empty():
		current["t"] = float(current["t"]) + delta
		if float(current["t"]) >= _seconds():
			current = {}
			if not queue.is_empty():
				_start_next()
	_root.queue_redraw()


func _start_next() -> void:
	var ids := PackedStringArray()
	if queue.size() >= _collapse_at():
		ids = queue.duplicate()
		queue.clear()
	else:
		ids.append(queue[0])
		queue.remove_at(0)
	current = {"ids": ids, "t": 0.0}
	shown_count += 1
	AudioManager.play_sfx(SFX)


func _seconds() -> float:
	return Platform.config.toast_seconds if Platform.config else 3.5


func _collapse_at() -> int:
	return Platform.config.toast_collapse_at if Platform.config else 4


func collapsed() -> bool:
	return showing() and (current["ids"] as PackedStringArray).size() > 1


## The two lines on screen: [header, main line].
func lines() -> PackedStringArray:
	if not showing():
		return PackedStringArray()
	var ids: PackedStringArray = current["ids"]
	if ids.size() > 1:
		return PackedStringArray([Loc.tn("{n} ACHIEVEMENT UNLOCKED", "{n} ACHIEVEMENTS UNLOCKED", ids.size()),
			Loc.t("See them in the Journal.")])
	var a := AchievementLibrary.by_id(ids[0])
	return PackedStringArray([Loc.t("ACHIEVEMENT"), Loc.t(a.title) if a else ids[0]])


# --- Layout (pure; test_achievements_ui checks it against the HUD rects) ---

## The toast's screen rect for a viewport `view` at UI scale `scale`.
static func rect_for(view: Vector2, scale: float) -> Rect2:
	var size := SIZE * scale
	var y := TOP
	var layout_view := view / scale
	if layout_view.x < HUD.COMPACT_WIDTH:
		var boss: Rect2 = HUD.element_rects(layout_view, ThemeDB.fallback_font,
			{"boss_title": "WARDEN KRAIL", "staggered": true})["boss"]
		y = maxf(TOP, boss.end.y * scale + 4.0)
	return Rect2(Vector2(roundf((view.x - size.x) * 0.5), y), size)


func rect() -> Rect2:
	return rect_for(get_viewport().get_visible_rect().size, UiTheme.scale())


## Vertical slide offset now: 0 under flash_reduction (fade only), otherwise
## the toast drops in from above over SLIDE_S.
func slide_offset() -> float:
	if not showing() or Settings.flash_reduction:
		return 0.0
	var k := clampf(float(current["t"]) / SLIDE_S, 0.0, 1.0)
	return -(1.0 - ease(k, 0.4)) * (rect().size.y + TOP)


func alpha() -> float:
	if not showing():
		return 0.0
	var t := float(current["t"])
	var fade_in := clampf(t / SLIDE_S, 0.0, 1.0)
	var fade_out := clampf((_seconds() - t) / FADE_OUT_S, 0.0, 1.0)
	return minf(fade_in, fade_out)


func _draw_toast() -> void:
	if not showing():
		return
	var r := rect()
	r.position.y += slide_offset()
	var s := UiTheme.scale()
	var a := alpha()
	var hc := UiTheme.high_contrast()
	var bg := Color(BG, 1.0 if hc else BG.a)
	_root.draw_rect(r, Color(bg, bg.a * a))
	_root.draw_rect(Rect2(r.position, Vector2(2.0 * s, r.size.y)), Color(UiTheme.ACCENT, a))
	if hc:
		_root.draw_rect(r, Color(Color.WHITE, a), false, 1.0)
	var ids: PackedStringArray = current["ids"]
	var ach := AchievementLibrary.by_id(ids[0])
	var glyph_c := r.position + Vector2(13.0, r.size.y * 0.5 / s) * s
	_draw_glyph(glyph_c, 5.0 * s, ach.category if ach and ids.size() == 1 else -1, a)
	var font := UiTheme.font()
	var ls := lines()
	var x := r.position.x + 24.0 * s
	var w := r.size.x - 28.0 * s
	var head := UiTheme.font_size(-2)
	var main := UiTheme.font_size()
	_root.draw_string(font, Vector2(x, r.position.y + 11.0 * s), ls[0], HORIZONTAL_ALIGNMENT_LEFT, w, head,
		Color(UiTheme.muted_color(), a))
	_root.draw_string(font, Vector2(x, r.position.y + 23.0 * s), ls[1], HORIZONTAL_ALIGNMENT_LEFT, w, main,
		Color(UiTheme.text_color(), a))


## A placeholder category mark (D-026): diamond (story), ring (exploration),
## two dots (people), bar pair (mastery); a star-ish cross when collapsed.
## The pulse is a brightness swell over the first PULSE_S, off under
## flash_reduction.
func _draw_glyph(c: Vector2, rad: float, category: int, a: float) -> void:
	var col := Color(UiTheme.ACCENT, a)
	if not Settings.flash_reduction and float(current["t"]) < PULSE_S:
		col = col.lerp(Color(Color.WHITE, a), 0.5 * (1.0 - float(current["t"]) / PULSE_S))
	match category:
		AchievementData.Category.STORY:
			_root.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -rad), c + Vector2(rad, 0),
				c + Vector2(0, rad), c + Vector2(-rad, 0)]), col)
		AchievementData.Category.EXPLORATION:
			_root.draw_arc(c, rad * 0.8, 0.0, TAU, 16, col, maxf(1.0, rad * 0.35))
		AchievementData.Category.PEOPLE:
			_root.draw_circle(c + Vector2(-rad * 0.45, 0), rad * 0.4, col)
			_root.draw_circle(c + Vector2(rad * 0.45, 0), rad * 0.4, col)
		AchievementData.Category.MASTERY:
			_root.draw_rect(Rect2(c + Vector2(-rad * 0.7, -rad), Vector2(rad * 0.5, rad * 2.0)), col)
			_root.draw_rect(Rect2(c + Vector2(rad * 0.2, -rad), Vector2(rad * 0.5, rad * 2.0)), col)
		_:
			_root.draw_rect(Rect2(c - Vector2(rad, rad * 0.25), Vector2(rad * 2.0, rad * 0.5)), col)
			_root.draw_rect(Rect2(c - Vector2(rad * 0.25, rad), Vector2(rad * 0.5, rad * 2.0)), col)
