extends RedlineTestCase
## Data validation for movement tuning (bible §35: "data validation").

const PRESET_DIR := "res://data/movement"


func test_all_presets_validate() -> void:
	var files := DirAccess.get_files_at(PRESET_DIR)
	check(files.size() > 0, "no movement presets found")
	for f in files:
		if not f.ends_with(".tres"):
			continue
		var cfg := load("%s/%s" % [PRESET_DIR, f]) as PlayerMovementConfig
		check(cfg != null, "%s is not a PlayerMovementConfig" % f)
		if cfg:
			var problems := cfg.validate()
			check(problems.is_empty(), "%s invalid: %s" % [f, ", ".join(problems)])


func test_derived_jump_math_matches_authored_values() -> void:
	var cfg := PlayerMovementConfig.new()
	cfg.jump_height = 56.0
	cfg.jump_time_to_apex = 0.35
	# Analytic apex of v^2 / 2g must equal the authored height.
	var v := -cfg.jump_velocity()
	check_near(v * v / (2.0 * cfg.rise_gravity()), 56.0, 0.001, "apex height")
	check_near(v / cfg.rise_gravity(), 0.35, 0.0001, "time to apex")


func test_validate_catches_bad_values() -> void:
	var cfg := PlayerMovementConfig.new()
	cfg.max_run_speed = 0.0
	cfg.coyote_time = 1.0
	cfg.low_size = Vector2(12, 40)
	var problems := cfg.validate()
	check(problems.size() >= 3, "expected >= 3 problems, got %d" % problems.size())


func test_step_compensated_jump_velocity_hits_height() -> void:
	# Simulate the exact integration order Player uses: gravity then move.
	var cfg := PlayerMovementConfig.new()
	var dt := 1.0 / 60.0
	var v := cfg.jump_velocity_for_step(dt)
	var y := 0.0
	var min_y := 0.0
	for i in 60:
		v += cfg.rise_gravity() * dt
		y += v * dt
		min_y = minf(min_y, y)
	check_near(-min_y, cfg.jump_height, 0.5, "discrete apex height")
