extends RedlineTestCase
## Style meter logic and Redline Core behaviour (bible §6, §10).

const PLAYER_SCENE := preload("res://player/Player.tscn")
const NEEDLE_DATA := preload("res://data/enemies/needle.tres")

var cfg: StyleConfig


func before_each() -> void:
	cfg = load("res://data/style/default_style.tres")


func _meter() -> StyleMeter:
	return StyleMeter.new(cfg)


func test_style_config_and_reactor_modes_validate() -> void:
	check(cfg.validate().is_empty(), "style config invalid: %s" % ", ".join(cfg.validate()))
	for f in DirAccess.get_files_at("res://data/reactor"):
		if f.ends_with(".tres"):
			var r: ReactorConfig = load("res://data/reactor/" + f)
			check(r.validate().is_empty(), "%s invalid: %s" % [f, ", ".join(r.validate())])


func test_repetition_gives_diminishing_style() -> void:
	var repeat := _meter()
	var varied := _meter()
	var none: Array[StringName] = []
	for i in 4:
		repeat.add_hit(&"light", 20.0, none)
	for tag in [&"light", &"heavy", &"launcher", &"air"]:
		varied.add_hit(tag, 20.0, none)
	check(varied.points > repeat.points * 1.5, "variety should beat repetition (%.1f vs %.1f)" % [varied.points, repeat.points])


func test_context_multipliers() -> void:
	var plain := _meter()
	var aerial := _meter()
	var none: Array[StringName] = []
	var air: Array[StringName] = [&"aerial", &"after_movement"]
	var a := plain.add_hit(&"x", 20.0, none)
	var b := aerial.add_hit(&"x", 20.0, air)
	check_near(b, a * cfg.aerial_multiplier * cfg.movement_multiplier, 0.01, "aerial+movement multiplier")


func test_rank_progression_decay_and_damage() -> void:
	var m := _meter()
	check(m.rank_name() == "D", "should start at D")
	m.add_bonus(cfg.rank_thresholds[4] + 1.0)
	check(m.rank_name() == "S", "expected S, got %s" % m.rank_name())
	var before := m.points
	m.tick(cfg.decay_delay * 0.5)
	check_near(m.points, before, 0.001, "no decay before the delay")
	m.tick(cfg.decay_delay + 1.0)
	check(m.points < before, "no decay after the delay")
	var p := m.points
	m.take_damage()
	check_near(m.points, p * cfg.damage_keep, 0.01, "damage should cut points")
	m.add_bonus(99999.0)
	check(m.rank_name() == "REDLINE", "top rank should be reachable")


func _spawn_player() -> Player:
	var world := Node2D.new()
	world.name = "ReactorWorld"
	add_child(world)
	var block := GrayboxBlock.new()
	block.size = Vector2(400, 64)
	block.position = Vector2(-200, 0)
	world.add_child(block)
	var p: Player = PLAYER_SCENE.instantiate()
	p.abilities = PlayerAbilities.new()
	p.input_source = ScriptedInputSource.new()
	world.add_child(p)
	p.respawn(Vector2(0, -2))
	return p


func _cleanup(p: Player) -> void:
	p.get_parent().queue_free()
	await physics_frames(2)


func test_core_drains_only_in_flow() -> void:
	var p := _spawn_player()
	await physics_frames(2)
	var start := p.reactor.charge
	await physics_frames(60)
	check_near(p.reactor.charge, start, 0.001, "drained outside a flow zone")
	p.reactor.enter_flow()
	await physics_frames(60)
	check_near(p.reactor.charge, start - p.reactor.config.drain_per_second, 0.5, "drain rate in flow")
	await _cleanup(p)


func test_kill_and_perfect_dodge_refill_core() -> void:
	var p := _spawn_player()
	await physics_frames(2)
	p.reactor.charge = 10.0
	var enemy: Enemy = preload("res://enemies/variants/Needle.tscn").instantiate()
	enemy.ai_enabled = false
	p.get_parent().add_child(enemy)
	var hit := HitInfo.create(p, NEEDLE_DATA.attacks[0], Vector2.ZERO, Vector2.RIGHT)
	EventBus.enemy_killed.emit(enemy, hit)
	check(p.reactor.charge >= 10.0 + NEEDLE_DATA.reactor_reward * p.reactor.config.gain_multiplier - 0.01, "kill did not refill")
	var c := p.reactor.charge
	EventBus.perfect_dodge.emit(enemy)
	check(p.reactor.charge > c, "perfect dodge did not refill")
	await _cleanup(p)


func test_burnout_drains_health_at_zero() -> void:
	var p := _spawn_player()
	await physics_frames(2)
	p.reactor.enter_flow()
	p.reactor.charge = 0.0
	await physics_frames(int(p.reactor.config.burnout_interval * 60.0) + 3)
	check(p.combat.health == p.combat.config.max_health - 1, "burnout should cost a pip (hp %d)" % p.combat.health)
	await _cleanup(p)


func test_style_from_real_hits_and_kill() -> void:
	var p := _spawn_player()
	await physics_frames(2)
	var enemy: Enemy = preload("res://enemies/variants/Needle.tscn").instantiate()
	enemy.ai_enabled = false
	enemy.position = Vector2(20, -2)
	p.get_parent().add_child(enemy)
	await physics_frames(2)
	var input := p.input_source as ScriptedInputSource
	for i in 6:
		input.press_light()
		await physics_frames(12)
	check(not is_instance_valid(enemy) or enemy.is_dead() or enemy.health < 30.0, "hits did not land")
	check(p.style.meter.points > 0.0, "no style from hits")
	await _cleanup(p)
