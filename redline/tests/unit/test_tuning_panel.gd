extends RedlineTestCase
## The tuning panel must expose the numeric tuning values and write through
## to the live config, so tuning never requires touching controller code.

var panel: CanvasLayer
var cfg: PlayerMovementConfig


func before_each() -> void:
	panel = load("res://ui/debug/TuningPanel.gd").new()
	add_child(panel)
	cfg = PlayerMovementConfig.new()
	panel.bind_config(cfg)


func after_each() -> void:
	panel.queue_free()
	await physics_frames(1)


func test_generates_sliders_for_numeric_exports() -> void:
	check(panel.sliders.size() >= 40, "expected >= 40 sliders, got %d" % panel.sliders.size())
	for key in ["max_run_speed", "jump_height", "coyote_time", "slide_friction", "dodge_speed", "dash_speed", "air_dodges"]:
		check(panel.sliders.has(key), "no slider for %s" % key)
	check(not panel.sliders.has("standing_size"), "collision size should not be slider-tunable")


func test_slider_writes_through_to_config() -> void:
	(panel.sliders["jump_height"] as HSlider).value = 70.0
	check_near(cfg.jump_height, 70.0, 0.01, "jump_height not applied")
	(panel.sliders["air_dodges"] as HSlider).value = 2
	check(cfg.air_dodges == 2, "int property not applied")


func test_slider_ranges_respect_export_hints_and_cover_current_value() -> void:
	var s: HSlider = panel.sliders["jump_cut_multiplier"]
	check_near(s.max_value, 1.0, 0.0001, "export_range max ignored")
	for key: String in panel.sliders:
		var slider: HSlider = panel.sliders[key]
		var v := float(cfg.get(key))
		check(v >= slider.min_value and v <= slider.max_value, "%s value %.3f outside slider range" % [key, v])


func test_save_writes_loadable_resource() -> void:
	cfg.jump_height = 61.0
	cfg.set_meta(&"source_path", "user://test_tuning_save.tres")
	var path: String = panel.save_config()
	check(path != "", "save failed")
	if path != "":
		var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PlayerMovementConfig
		check(loaded != null and is_equal_approx(loaded.jump_height, 61.0), "saved value not reloaded")
		DirAccess.remove_absolute(path)
