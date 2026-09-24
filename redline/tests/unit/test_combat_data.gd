extends RedlineTestCase
## Data validation for weapons, enemies and combat configs (bible §35).


func _validate_dir(dir: String) -> void:
	var files := DirAccess.get_files_at(dir)
	check(files.size() > 0, "no resources in %s" % dir)
	for f in files:
		if not f.ends_with(".tres"):
			continue
		var res := load("%s/%s" % [dir, f])
		check(res != null and res.has_method("validate"), "%s/%s not validatable" % [dir, f])
		if res and res.has_method("validate"):
			var problems: PackedStringArray = res.validate()
			check(problems.is_empty(), "%s invalid: %s" % [f, ", ".join(problems)])


func test_weapons_validate() -> void:
	_validate_dir("res://data/weapons")


func test_enemies_validate() -> void:
	_validate_dir("res://data/enemies")


func test_combat_configs_validate() -> void:
	_validate_dir("res://data/combat")


func test_attack_hitbox_mirrors_with_facing() -> void:
	var a := AttackData.new()
	a.hitbox = Rect2(2, -30, 26, 22)
	var right := a.world_hitbox(Vector2(100, 0), 1)
	var left := a.world_hitbox(Vector2(100, 0), -1)
	check(right == Rect2(102, -30, 26, 22), "right-facing hitbox wrong: %s" % right)
	check(left == Rect2(72, -30, 26, 22), "left-facing hitbox wrong: %s" % left)


func test_melee_chain_has_rising_payoff() -> void:
	# Design rule: the chain finisher must hit harder and stagger more than openers.
	var w: WeaponData = load("res://data/weapons/pulse_blade.tres")
	var last := w.light_chain[w.light_chain.size() - 1]
	for i in w.light_chain.size() - 1:
		check(last.damage > w.light_chain[i].damage, "finisher damage not above opener %d" % i)
		check(last.poise_damage > w.light_chain[i].poise_damage, "finisher poise not above opener %d" % i)
