extends RedlineTestCase
## M3 world framework: transitions, persistence, anchors, death/respawn,
## scrap caches, pits, injectors and interaction prompts.

const ROOM_A := "res://tests/fixtures/WorldA.tscn"
const ROOM_B := "res://tests/fixtures/WorldB.tscn"
const TEST_SAVE_DIR := "user://test_world_saves"

var root: Node2D
var prompts: Array[String] = []


func before_each() -> void:
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	SaveManager.save_dir = TEST_SAVE_DIR
	Game.new_game()
	Game.state.last_anchor_room = ROOM_A
	Game.state.last_anchor_id = "start"
	prompts.clear()
	EventBus.interact_prompt_changed.connect(_on_prompt)
	SceneRouter.goto_room(ROOM_A, &"start")
	await physics_frames(3)


func after_each() -> void:
	EventBus.interact_prompt_changed.disconnect(_on_prompt)
	SceneRouter.current_room = null
	SceneRouter.world_root = null
	root.queue_free()
	SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR
	for f in DirAccess.get_files_at(TEST_SAVE_DIR):
		DirAccess.remove_absolute("%s/%s" % [TEST_SAVE_DIR, f])
	Game.new_game()
	await physics_frames(2)


func _on_prompt(text: String) -> void:
	prompts.append(text)


func _room() -> Room:
	return SceneRouter.current_room as Room


func _player() -> Player:
	return _room().player


func _scripted() -> ScriptedInputSource:
	var p := _player()
	if not p.input_source is ScriptedInputSource:
		p.input_source = ScriptedInputSource.new()
	return p.input_source as ScriptedInputSource


func _wait_room_change(from: Node, frames := 120) -> bool:
	for i in frames:
		await physics_frames(1)
		if SceneRouter.current_room != from and is_instance_valid(SceneRouter.current_room) and not SceneRouter.transitioning:
			await physics_frames(2)
			return true
	return false


func test_exit_moves_to_entry_and_carries_momentum() -> void:
	var a := _room()
	_player().teleport(Vector2(690, -2))
	_scripted().move_x = 1
	check(await _wait_room_change(a), "exit did not change room")
	var b := _room()
	check(b.room_name == "WorldB", "arrived in wrong room")
	check(absf(b.player.global_position.x - 640.0) < 40.0, "not at the entry marker (x=%.1f)" % b.player.global_position.x)
	_scripted().move_x = 1
	await physics_frames(1)
	check(absf(b.player.velocity.x) > 50.0, "momentum not carried through the exit")


func test_health_persists_between_rooms() -> void:
	var p := _player()
	p.combat.take_damage(2, Vector2.ZERO, 0.0, false)
	var a := _room()
	p.teleport(Vector2(690, -2))
	_scripted().move_x = 1
	await _wait_room_change(a)
	check(_player().combat.health == _player().combat.config.max_health - 2, "health reset by the transition")


func test_anchor_rest_banks_scrap_heals_and_saves() -> void:
	var p := _player()
	Game.add_scrap(25)
	p.combat.take_damage(3, Vector2.ZERO, 0.0, false)
	await physics_frames(3)
	check(prompts.has("Rest"), "anchor prompt not shown (got %s)" % [prompts])
	_scripted().press_interact()
	await physics_frames(2)
	check(Game.state.scrap_banked == 25 and Game.state.scrap_unbanked == 0, "scrap not banked")
	check(p.combat.health == p.combat.config.max_health, "anchor did not heal")
	check(Game.has_save(1), "anchor did not save")


func test_death_returns_to_anchor_and_drops_unbanked_scrap() -> void:
	var a := _room()
	_player().teleport(Vector2(690, -2))
	_scripted().move_x = 1
	await _wait_room_change(a)
	var b := _room()
	Game.add_scrap(40)
	b.player.combat.take_damage(99, Vector2.ZERO, 0.0, true)
	check(await _wait_room_change(b, 240), "death did not return to a room")
	check(_room().room_name == "WorldA", "respawned in the wrong room")
	check(_player().combat.health == _player().combat.config.max_health, "respawn not at full health")
	check(Game.state.scrap_unbanked == 0 and int(Game.state.dropped_scrap.get("amount", 0)) == 40, "unbanked scrap not dropped")
	check(Game.state.dropped_scrap.get("room", "") == ROOM_B, "cache recorded in the wrong room")


func test_scrap_cache_spawns_and_recovers() -> void:
	Game.state.dropped_scrap = {"room": ROOM_A, "x": 200.0, "y": 0.0, "amount": 30}
	SceneRouter.goto_room(ROOM_A, &"start")
	await physics_frames(3)
	var caches := _room().find_children("*", "ScrapCache", true, false)
	check(caches.size() == 1, "cache not spawned in its room")
	_player().teleport(Vector2(200, -2))
	await physics_frames(4)
	check(Game.state.scrap_unbanked == 30 and Game.state.dropped_scrap.is_empty(), "cache not recovered")


func test_currency_loss_toggle_keeps_scrap() -> void:
	Settings.currency_loss = false
	Game.add_scrap(15)
	Game.on_player_death(ROOM_A, Vector2.ZERO)
	Settings.currency_loss = true
	check(Game.state.scrap_unbanked == 15 and Game.state.dropped_scrap.is_empty(), "scrap dropped with loss disabled")


func test_pit_costs_a_pip_and_returns_to_safe_ground() -> void:
	var a := _room()
	_player().teleport(Vector2(690, -2))
	_scripted().move_x = 1
	await _wait_room_change(a)
	var p := _player()
	_scripted().move_x = 0
	await physics_frames(10)
	var safe := p.global_position
	p.teleport(Vector2(330, -40))  # over the gap between 236 and 400
	for i in 120:
		await physics_frames(1)
		if p.combat.health < p.combat.config.max_health:
			break
	await physics_frames(2)
	check(p.combat.health == p.combat.config.max_health - 1, "pit should cost exactly one pip")
	check(p.global_position.distance_to(safe) < 8.0, "not returned to safe ground")


func test_pit_never_returns_you_to_a_ledge_lip() -> void:
	var a := _room()
	_player().teleport(Vector2(690, -2))
	_scripted().move_x = 1
	await _wait_room_change(a)
	var p := _player()
	_scripted().move_x = 0
	await physics_frames(10)
	# Run right off the ledge that ends at x 236 and keep holding right.
	p.teleport(Vector2(150, p.global_position.y))
	_scripted().move_x = 1
	for i in 180:
		await physics_frames(1)
		if p.combat.health < p.combat.config.max_health:
			break
	_scripted().move_x = 0
	await physics_frames(2)
	check(p.combat.health == p.combat.config.max_health - 1, "should have fallen into the pit once")
	check(p.global_position.x <= 236.0 - p.config.safe_ground_reach + 7.0, "respawned on the lip at x %.1f" % p.global_position.x)


func test_injector_heals_and_is_consumed() -> void:
	var p := _player()
	p.combat.take_damage(3, Vector2.ZERO, 0.0, false)
	var before := p.combat.injectors
	_scripted().press_heal()
	await physics_frames(int(p.combat.config.heal_time * 60.0) + 4)
	check(p.combat.health == p.combat.config.max_health - 3 + p.combat.config.heal_amount, "heal amount wrong")
	check(p.combat.injectors == before - 1, "injector not consumed")


func test_hit_interrupts_heal_without_consuming() -> void:
	var p := _player()
	p.combat.take_damage(3, Vector2.ZERO, 0.0, false)
	var before := p.combat.injectors
	_scripted().press_heal()
	await physics_frames(10)
	check(p.current_state_id() == &"heal", "not channelling")
	var needle_attack: AttackData = preload("res://data/enemies/needle.tres").attacks[0]
	var hit := HitInfo.create(null, needle_attack, Vector2(100, -50), Vector2.RIGHT)
	hit.source_position = p.global_position - Vector2(10, 0)
	p.receive_hit(hit)
	await physics_frames(40)
	check(p.combat.injectors == before, "interrupted heal consumed an injector")
