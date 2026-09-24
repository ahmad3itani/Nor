extends RedlineTestCase
## M3.2: Scrap drops, persistent collectibles, breakable walls, lore data.

const ROOM_A := "res://tests/fixtures/WorldA.tscn"
const NEEDLE := preload("res://enemies/variants/Needle.tscn")

var root: Node2D


func before_each() -> void:
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	Game.new_game()
	SceneRouter.goto_room(ROOM_A, &"start")
	await physics_frames(3)


func after_each() -> void:
	SceneRouter.current_room = null
	SceneRouter.world_root = null
	root.queue_free()
	Game.new_game()
	await physics_frames(2)


func _room() -> Room:
	return SceneRouter.current_room as Room


func test_kill_drops_scrap_that_homes_to_player() -> void:
	var e: Enemy = NEEDLE.instantiate()
	e.ai_enabled = false
	e.position = Vector2(120, -2)
	_room().add_child(e)
	await physics_frames(2)
	var expected := e.data.scrap_drop
	var kill := HitInfo.create(_room().player, e.data.attacks[0], Vector2.ZERO, Vector2.RIGHT)
	kill.attack = e.data.attacks[0].duplicate()
	kill.attack.damage = 999.0
	e.receive_hit(kill)
	await physics_frames(90)
	check(Game.state.scrap_unbanked == expected, "expected %d scrap, got %d" % [expected, Game.state.scrap_unbanked])


func test_collectible_persists_once_taken() -> void:
	var c := Collectible.new()
	c.persist_id = "test_shard"
	c.kind = Collectible.Kind.CORE_SHARD
	c.position = Vector2(80, 0)
	_room().add_child(c)
	_room().player.teleport(Vector2(80, -2))
	await physics_frames(3)
	check(Game.state.core_shards == 1, "shard not collected")
	var again := Collectible.new()
	again.persist_id = "test_shard"
	_room().add_child(again)
	await physics_frames(1)
	check(not is_instance_valid(again) or again.is_queued_for_deletion(), "collected item respawned")


func test_breakable_wall_breaks_persistently_and_respects_needs_heavy() -> void:
	var w := BreakableWall.new()
	w.persist_id = "test_wall"
	w.size = Vector2(16, 40)
	w.max_health = 20.0
	w.position = Vector2(60, -40)
	_room().add_child(w)
	await physics_frames(1)
	var blade: WeaponData = load("res://data/weapons/pulse_blade.tres")
	var light := HitInfo.create(_room().player, blade.light_chain[0], Vector2.ZERO, Vector2.RIGHT)
	check(w.receive_hit(light) == CombatResult.HIT, "light should damage a normal wall")
	w.receive_hit(light)
	await physics_frames(1)
	check(Game.is_collected("test_wall"), "broken wall not remembered")
	var hard := BreakableWall.new()
	hard.persist_id = "test_wall_hard"
	hard.needs_heavy = true
	_room().add_child(hard)
	await physics_frames(1)
	check(hard.receive_hit(light) == CombatResult.BLOCKED, "light should not crack a heavy-only wall")
	var heavy := HitInfo.create(_room().player, blade.heavy, Vector2.ZERO, Vector2.RIGHT)
	hard.receive_hit(heavy)
	hard.receive_hit(heavy)
	await physics_frames(1)
	check(Game.is_collected("test_wall_hard"), "heavy did not break the heavy-only wall")


func test_player_melee_breaks_wall_in_world() -> void:
	var w := BreakableWall.new()
	w.persist_id = "test_wall_melee"
	w.size = Vector2(16, 40)
	w.max_health = 15.0
	w.position = Vector2(62, -40)
	_room().add_child(w)
	var input := ScriptedInputSource.new()
	_room().player.input_source = input
	_room().player.teleport(Vector2(46, -2))
	await physics_frames(2)
	for i in 3:
		input.press_light()
		await physics_frames(14)
	check(Game.is_collected("test_wall_melee"), "melee did not break the wall")


func test_memory_fragments_validate() -> void:
	for f in DirAccess.get_files_at("res://data/lore"):
		if f.ends_with(".tres"):
			var m: MemoryFragmentData = load("res://data/lore/" + f)
			check(m.validate().is_empty(), "%s: %s" % [f, ", ".join(m.validate())])
