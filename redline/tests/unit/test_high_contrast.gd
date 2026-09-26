extends RedlineTestCase
## M9 T12 (bible §24, D4 §7.2, D-161): high contrast in the theme, HUD and
## world, and the background dim. High contrast never relies on colour alone.

const HUD_PATH := "res://ui/hud/CombatHud.gd"
const VISUAL_PATH := "res://enemies/base/EnemyVisual.gd"
const PLAYER_VISUAL_PATH := "res://player/animation/PlayerPlaceholderVisual.gd"

var _snap: Dictionary = {}


func before_each() -> void:
	_snap = snapshot_settings()
	UiTheme.invalidate()


func after_each() -> void:
	restore_settings(_snap)


func test_theme_variant_colors() -> void:
	Settings.high_contrast = false
	var t := UiTheme.get_theme()
	check(t.get_color("font_color", "Label") == UiTheme.TEXT, "default text colour is the M8 one")
	check(is_equal_approx((t.get_stylebox("panel", "PanelContainer") as StyleBoxFlat).bg_color.a, UiTheme.BG.a), "default panel keeps its see-through background")
	Settings.high_contrast = true
	UiTheme.invalidate()
	var hc := UiTheme.get_theme()
	check(hc != t, "high contrast builds its own theme")
	check(hc.get_color("font_color", "Label") == Color.WHITE, "high-contrast text is white")
	check(hc.get_color("font_disabled_color", "Button") == UiTheme.HC_MUTED, "high-contrast muted colour")
	check(is_equal_approx((hc.get_stylebox("panel", "PanelContainer") as StyleBoxFlat).bg_color.a, 1.0), "high-contrast panel is opaque")
	var bg := Color(UiTheme.BG, 1.0)
	check(ColorVision.contrast(UiTheme.HC_MUTED, bg) >= 7.0, "high-contrast muted text >= 7:1 (%.2f)" % ColorVision.contrast(UiTheme.HC_MUTED, bg))
	check(ColorVision.contrast(UiTheme.HC_TEXT, bg) >= 7.0, "high-contrast text >= 7:1")


func test_focus_not_colour_only() -> void:
	Settings.high_contrast = false
	var f := UiTheme.get_theme().get_stylebox("focus", "Button") as StyleBoxFlat
	check(f.border_width_left == 2 and f.border_width_right == 0, "default focus: the M8 left bar")
	Settings.high_contrast = true
	UiTheme.invalidate()
	var hf := UiTheme.get_theme().get_stylebox("focus", "Button") as StyleBoxFlat
	check(hf.border_width_left == 2 and hf.border_width_right == 2, "high-contrast focus has borders on both sides")
	check(hf.bg_color != (UiTheme.get_theme().get_stylebox("normal", "Button") as StyleBoxFlat).bg_color, "focused row fill differs from a normal row")
	check(UiTheme.DISABLED_PREFIX.strip_edges() != "", "disabled rows carry a text prefix")


func test_empty_pip_hollow() -> void:
	var hud := load(HUD_PATH) as GDScript
	var red := Color("e8283c")
	var m8_empty: Array = hud.call("pip_ops", false, false, false, red)
	check(m8_empty.size() == 1 and m8_empty[0][0] == &"fill", "a default empty health pip keeps the M8 faint fill")
	var hc_empty: Array = hud.call("pip_ops", false, false, true, red)
	check(hc_empty.size() == 1 and hc_empty[0][0] == &"outline", "high contrast: an empty pip is a hollow box")
	var injector_empty: Array = hud.call("pip_ops", false, true, false, red)
	check(injector_empty.size() == 1 and injector_empty[0][0] == &"outline", "an empty injector is hollow in every mode (shape cue)")
	var full: Array = hud.call("pip_ops", true, true, false, red)
	check(full.size() == 1 and full[0] == [&"fill", red], "a full pip is filled")
	var hc_full: Array = hud.call("pip_ops", true, false, true, red)
	check(hc_full.size() == 2 and hc_full[1][0] == &"outline" and hc_full[1][1] == Color.WHITE, "high contrast outlines full pips in white")
	# The damage-assist carry shows on the next pip to go.
	check(is_equal_approx(hud.call("pip_fill", 0, 3, 0.5), 1.0), "lower pips stay full")
	check(is_equal_approx(hud.call("pip_fill", 2, 3, 0.25), 0.75), "the top pip is drawn at (1 - carry)")
	check(is_equal_approx(hud.call("pip_fill", 3, 3, 0.25), 0.0), "pips above health are empty")
	check(is_equal_approx(hud.call("pip_fill", 2, 3, 0.0), 1.0), "no carry: the M8 look")


func test_enemy_outline_hc() -> void:
	var v := load(VISUAL_PATH) as GDScript
	check(v.call("body_outline_color", false, false) == Color(0, 0, 0, 0.6), "default outline is the M8 dark edge")
	check(v.call("body_outline_color", false, true) == Color.WHITE, "high contrast: a white 1 px outline")
	check(v.call("body_outline_color", true, true) == Color("ffcf5a"), "elites keep the gold outline")
	check(is_equal_approx(v.call("telegraph_width", true), 2.0) and is_equal_approx(v.call("telegraph_width", false), 1.0), "telegraph lines are 2 px in high contrast")
	var pv := load(PLAYER_VISUAL_PATH) as GDScript
	check(pv.call("outline_color", true) == Color.WHITE and pv.call("outline_color", false) == Color(0, 0, 0, 0.6), "the player outline follows the mode")


func test_background_dim_modulate() -> void:
	Settings.background_dim = 0
	var backdrop := DistrictBackdrop.new()
	add_child(backdrop)
	check(backdrop.sky_layer().modulate == Color.WHITE, "Off leaves the backdrop untouched")
	var cfg := Settings.config()
	Settings.background_dim = 2
	EventBus.settings_changed.emit()
	var d := cfg.background_dim[2]
	check(backdrop.sky_layer().modulate.is_equal_approx(Color(1.0 - d, 1.0 - d, 1.0 - d, 1.0)), "Strong dims by %.2f (%s)" % [d, backdrop.sky_layer().modulate])
	Settings.background_dim = 1
	backdrop.apply_dim()
	check(is_equal_approx(backdrop.sky_layer().modulate.r, 1.0 - cfg.background_dim[1]), "Some dims by the config value")
	# Independent of high contrast: turning contrast on changes nothing here.
	Settings.background_dim = 0
	Settings.high_contrast = true
	backdrop.apply_dim()
	check(backdrop.sky_layer().modulate == Color.WHITE, "high contrast does not force the dim")
	backdrop.queue_free()
