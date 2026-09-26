extends RedlineTestCase
## M9 T12 (bible §24, D4 §7.1): the flash-reduction gaps. With the setting on,
## nothing flashes faster than AccessibilityConfig.flash_max_hz (3 Hz) and no
## full-white frame covers more than a sprite. Each gated consumer exposes a
## pure helper, checked here with the setting off and on.

const VISUAL_PATH := "res://enemies/base/EnemyVisual.gd"
const HUD_PATH := "res://ui/hud/CombatHud.gd"
const PLAYER_VISUAL_PATH := "res://player/animation/PlayerPlaceholderVisual.gd"
const COLLECTOR_PATH := "res://bosses/CollectorDroneBehavior.gd"
const KRAIL_PATH := "res://bosses/WardenKrailBehavior.gd"

var _snap: Dictionary = {}


func before_each() -> void:
	_snap = snapshot_settings()


func after_each() -> void:
	restore_settings(_snap)


func test_enemy_visual_flash_reduced() -> void:
	var v := load(VISUAL_PATH) as GDScript
	var full: Color = v.call("hit_tint", false)
	var soft: Color = v.call("hit_tint", true)
	check(full == Color(3, 3, 3), "default hit tint is the M8 overbright flash")
	check(soft.r < full.r and soft.r > 1.0, "reduced hit tint is softer but still reads (%s)" % soft)
	check(v.call("flash_color", false) == Color.WHITE, "default placeholder flash is white")
	check((v.call("flash_color", true) as Color).a <= 0.5, "reduced placeholder flash is half alpha")
	check(is_equal_approx(v.call("windup_pulse", 0.3, true), v.call("windup_pulse", 0.9, true)), "reduced wind-up pulse holds still")


func test_hud_rank_flash_reduced() -> void:
	var hud := load(HUD_PATH) as GDScript
	var base := Color(0.8, 0.2, 0.3)
	check(hud.call("rank_color", base, true, false) == Color.WHITE, "default: the rank flashes white")
	check(hud.call("rank_color", base, true, true) == base, "reduced: the rank swaps in place")
	check(hud.call("rank_color", base, false, false) == base, "no flash outside a rank change")


func test_hitspark_reduced() -> void:
	check(HitSpark.spark_amount(8, false) == 8 and HitSpark.spark_amount(8, true) == 4, "reduced sparks are halved")
	check(HitSpark.spark_amount(1, true) == 1, "never fewer than one spark")
	var c := Color(0.2, 0.8, 1.0, 1.0)
	check(HitSpark.core_color(c, false) == Color.WHITE, "default sparks have a white core")
	check(HitSpark.core_color(c, true) == c, "reduced sparks start in their own colour")
	Settings.flash_reduction = true
	var s := HitSpark.spawn(self, Vector2.ZERO, Vector2.RIGHT, c, 8)
	check(s.amount == 4 and s.color_ramp.get_color(0) == c, "spawn reads the setting")
	s.queue_free()


func test_player_and_boss_lamps_reduced() -> void:
	var pv := load(PLAYER_VISUAL_PATH) as GDScript
	check(is_equal_approx(pv.call("hurt_alpha", 0.0, false), 1.0), "no blink outside i-frames")
	check(is_equal_approx(pv.call("hurt_alpha", 0.5, true), pv.call("hurt_alpha", 0.47, true)), "reduced: the post-hit body holds one alpha")
	check(pv.call("hurt_alpha", 0.5, true) < 1.0, "reduced: still see-through while invulnerable")
	var col := load(COLLECTOR_PATH) as GDScript
	var blinks := false
	for i in 12:
		blinks = blinks or bool(col.call("lamp_blink", i / 60.0, true))
	check(not blinks, "reduced: the Collector's volley lamp never blinks white")


func test_no_flash_above_3hz() -> void:
	var max_hz := Settings.config().flash_max_hz
	check(max_hz <= 3.0, "flash_max_hz is the WCAG 3 Hz")
	var v := load(VISUAL_PATH) as GDScript
	var pv := load(PLAYER_VISUAL_PATH) as GDScript
	var col := load(COLLECTOR_PATH) as GDScript
	var krail := load(KRAIL_PATH) as GDScript
	# Sample each helper over one second at 60 fps with the setting on and
	# count on -> off transitions.
	var probes := {
		"enemy wind-up": func(t: float) -> bool: return float(v.call("windup_pulse", t, true)) > 0.75,
		"player hurt blink": func(t: float) -> bool: return float(pv.call("hurt_alpha", 1.0 - t, true)) < 1.0,
		"collector lamp": func(t: float) -> bool: return bool(col.call("lamp_blink", t, true)),
		"krail crackle": func(t: float) -> bool: return bool(krail.call("crackle_lit", roundi(t * 60.0), true)),
		"map guide": func(t: float) -> bool: return MapView.guide_alpha(t, true) > 0.7,
	}
	for name: String in probes:
		var n := _transitions(probes[name])
		check(n <= max_hz, "%s: %d on->off per second with flash reduction" % [name, n])
	# Without the setting the old wind-up pulse is faster: the gate matters.
	var raw := _transitions(func(t: float) -> bool: return float(v.call("windup_pulse", t, false)) > 0.75)
	check(raw > 3, "the ungated wind-up pulse is above 3 Hz (%d), so gating it matters" % raw)


func test_krail_crackle_frame_driven_and_static_under_flash_reduction() -> void:
	var script := load(KRAIL_PATH) as GDScript
	var consts := script.get_script_constant_map()
	check(int(consts["CRACKLE_PERIOD_FRAMES"]) >= 20, "crackle period >= 20 frames (<= 3 Hz at 60 fps)")
	check(int(consts["CRACKLE_ON_FRAMES"]) < int(consts["CRACKLE_PERIOD_FRAMES"]), "the crackle is lit for part of the period")
	check(not FileAccess.get_file_as_string(KRAIL_PATH).contains("get_ticks_msec"), "no wall-clock time in the crackle")
	# In both modes the crackle stays at or under 3 Hz.
	var raw := _transitions(func(t: float) -> bool: return bool(script.call("crackle_lit", roundi(t * 60.0), false)))
	check(raw <= 3, "default crackle %d/s" % raw)
	var b: Node = script.new()
	b.set("phase", 2)
	Settings.flash_reduction = false
	var lit := []
	for i in 48:
		b.call("tick", 1.0 / 60.0)
		lit.append(bool(b.call("crackle_visible")))
	check(lit.count(true) == 2 * int(consts["CRACKLE_ON_FRAMES"]), "lit on %d of 48 frames" % lit.count(true))
	Settings.flash_reduction = true
	var steady := true
	for i in 30:
		b.call("tick", 1.0 / 60.0)
		steady = steady and bool(b.call("crackle_visible"))
	check(steady, "flash reduction draws the crackle steady")
	b.set("phase", 1)
	check(not bool(b.call("crackle_visible")), "no crackle in phase 1")
	b.free()


## On -> off transitions of `probe(t)` over one second at 60 fps.
func _transitions(probe: Callable) -> int:
	var n := 0
	var prev := bool(probe.call(0.0))
	for i in range(1, 61):
		var cur := bool(probe.call(i / 60.0))
		if prev and not cur:
			n += 1
		prev = cur
	return n
