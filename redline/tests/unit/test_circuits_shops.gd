extends RedlineTestCase
## M3.4: Circuits (capacity + effects), shops, new weapons, data cross-refs.

const PLAYER_SCENE := preload("res://player/Player.tscn")
const NEEDLE := preload("res://enemies/variants/Needle.tscn")

var world: Node2D
var player: Player
var input: ScriptedInputSource


func before_each() -> void:
	Game.new_game()
	world = Node2D.new()
	add_child(world)
	var floor_block := GrayboxBlock.new()
	floor_block.size = Vector2(2000, 64)
	floor_block.position = Vector2(-1000, 0)
	world.add_child(floor_block)
	player = PLAYER_SCENE.instantiate()
	player.abilities = PlayerAbilities.new()
	input = ScriptedInputSource.new()
	player.input_source = input
	world.add_child(player)
	player.respawn(Vector2(0, -2))
	await physics_frames(3)


func after_each() -> void:
	world.queue_free()
	Game.new_game()
	await physics_frames(2)


func _own_and_equip(id: String) -> void:
	Game.grant_circuit(id)
	check(Game.toggle_circuit(id), "could not equip %s" % id)


func _enemy(pos: Vector2) -> Enemy:
	var e: Enemy = NEEDLE.instantiate()
	e.ai_enabled = false
	e.position = pos
	world.add_child(e)
	return e


func test_catalog_and_cross_references() -> void:
	check(Game.catalog.validate().is_empty(), "catalog: %s" % ", ".join(Game.catalog.validate()))
	check(Game.catalog.circuits.size() >= 10, "need at least 10 circuits (bible M3: 8-12)")
	check(Game.catalog.weapons.size() >= 5, "need 5 weapons")
	for f in DirAccess.get_files_at("res://data/shops"):
		var shop: ShopData = load("res://data/shops/" + f)
		for item in shop.items:
			if item.kind == ShopItem.Kind.CIRCUIT:
				check(Game.catalog.circuit(item.item_id) != null, "%s sells unknown circuit %s" % [f, item.item_id])
			elif item.kind == ShopItem.Kind.WEAPON:
				check(Game.catalog.weapon(item.item_id) != null, "%s sells unknown weapon %s" % [f, item.item_id])
				check(item.price > 0, "%s: weapon %s needs a price" % [f, item.item_id])
	for f in DirAccess.get_files_at("res://data/npcs"):
		var p: NpcProfile = load("res://data/npcs/" + f)
		for r in p.rules:
			var d := r.dialogue
			check(d.give_circuit == "" or Game.catalog.circuit(d.give_circuit) != null, "%s gives unknown circuit" % d.id)
			check(d.give_weapon == "" or Game.catalog.weapon(d.give_weapon) != null, "%s gives unknown weapon" % d.id)
			check(d.open_menu == &"" or d.open_menu == &"loadout" or ResourceLoader.exists("res://data/shops/%s.tres" % d.open_menu), "%s opens unknown menu" % d.id)
	for q in Game.quests.quests:
		check(q.reward_circuit == "" or Game.catalog.circuit(q.reward_circuit) != null, "%s rewards unknown circuit" % q.id)


func test_capacity_limits_equipping() -> void:
	for c in Game.catalog.circuits:
		Game.grant_circuit(c.id)
	var equipped := 0
	for c in Game.catalog.circuits:
		if Game.toggle_circuit(c.id):
			equipped += 1
	check(Game.capacity_used() <= Game.core_capacity(), "over capacity")
	check(equipped > 0 and equipped < Game.catalog.circuits.size(), "capacity should stop some circuits")
	Game.state.core_shards += 2
	check(Game.core_capacity() == Game.catalog.base_core_capacity + 2, "core shards should raise capacity")


func test_glass_pulse_trades_damage() -> void:
	var e := _enemy(Vector2(20, -2))
	_own_and_equip("glass_pulse")
	await physics_frames(2)
	input.press_light()
	await physics_frames(12)
	check_near(e.health, e.data.max_health - 10.0 * 1.35, 0.01, "glass pulse melee damage")
	var hp := player.combat.health
	player.combat.take_damage(1, Vector2.ZERO, 0.0, false)
	check(player.combat.health == hp - 2, "glass pulse should double damage taken")


func test_scavenger_multiplies_scrap() -> void:
	_own_and_equip("scavenger")
	check(is_equal_approx(Game.scrap_multiplier(), 1.5), "scavenger multiplier")


func test_emergency_loop_saves_once_per_rest() -> void:
	_own_and_equip("emergency_loop")
	player.combat.take_damage(99, Vector2.ZERO, 0.0, false)
	check(player.combat.health == 1 and not player.combat.dead, "emergency loop did not save")
	player.combat.take_damage(99, Vector2.ZERO, 0.0, false)
	check(player.combat.dead, "emergency loop should only work once")


func test_ghost_step_extends_iframes() -> void:
	_own_and_equip("ghost_step")
	input.press_dodge()
	var cfg := player.config
	await physics_frames(int(cfg.dodge_iframe_end * 60.0) + 2)
	check(player.invulnerable, "ghost step should extend i-frames past the base window")


func test_blood_capacitor_heals_every_four_kills() -> void:
	_own_and_equip("blood_capacitor")
	player.combat.take_damage(2, Vector2.ZERO, 0.0, false)
	var hp := player.combat.health
	var needle_data: EnemyData = load("res://data/enemies/needle.tres")
	for i in 4:
		var e := _enemy(Vector2(400 + i * 40, -2))
		await physics_frames(1)
		EventBus.enemy_killed.emit(e, HitInfo.create(player, needle_data.attacks[0], Vector2.ZERO, Vector2.RIGHT))
	check(player.combat.health == hp + 1, "blood capacitor did not heal after 4 kills")


func test_revolver_pierces_two_extra_targets() -> void:
	var rev := Game.catalog.weapon("heavy_revolver")
	player.combat.set_loadout(null, rev)
	var targets: Array[Enemy] = []
	for x in [60, 100, 140, 180]:
		targets.append(_enemy(Vector2(x, -2)))
	await physics_frames(2)
	input.press_ranged()
	await physics_frames(20)
	var hit := 0
	for t in targets:
		if t.health < t.data.max_health:
			hit += 1
	check(hit == 1 + rev.shot.projectile.pierce, "revolver should hit %d targets, hit %d" % [1 + rev.shot.projectile.pierce, hit])


func test_katars_have_a_four_hit_chain() -> void:
	player.combat.set_loadout(Game.catalog.weapon("split_katars"), null)
	var ids: Array[String] = []
	for i in 4:
		input.press_light()
		await physics_frames(7)
		ids.append(String(player.combat.current_attack.id) if player.combat.current_attack else "-")
	var expected: Array[String] = ["katar_light_1", "katar_light_2", "katar_light_3", "katar_light_4"]
	check(ids == expected, "katar chain: %s" % [ids])


func test_shop_buying_rules() -> void:
	var menu: MenuScreen = load("res://ui/menus/ShopMenu.gd").new()
	add_child(menu)
	var shop: ShopData = load("res://data/shops/shop_mara.tres")
	var katars := shop.items[0]
	check(not menu.buy(katars), "should not afford with 0 scrap")
	Game.state.scrap_banked = 400
	check(menu.buy(katars), "purchase failed")
	check(Game.state.owned_weapons.has("split_katars") and Game.state.total_scrap() == 250, "weapon/scrap wrong after purchase")
	check(not menu.buy(katars), "bought the same weapon twice")
	var injector := shop.items[2]
	var cap := player.combat.injector_capacity()
	check(menu.buy(injector), "upgrade purchase failed")
	check(player.combat.injector_capacity() == cap + 1, "spare injector did not raise capacity")
	menu.queue_free()


## M7 D5a: Iko's black-market stock resolves through the catalog, and the
## Bootleg Injector stacks with Mara's Spare Injector via its own flag.
func test_iko_stock_registered() -> void:
	var shop: ShopData = load("res://data/shops/shop_iko.tres")
	check(shop.items.size() == 4, "Iko should stock 4 items, has %d" % shop.items.size())
	for id in ["hot_wire", "live_current", "slipstream"]:
		var c := Game.catalog.circuit(id) as CircuitData
		check(c != null, "circuit %s not in catalog" % id)
		if c:
			check(c.validate().is_empty(), "%s: %s" % [id, ", ".join(c.validate())])
			check(shop.items.any(func(i: ShopItem) -> bool: return i.kind == ShopItem.Kind.CIRCUIT and i.item_id == id), "Iko does not sell %s" % id)
	check(Game.catalog.validate().is_empty(), "catalog: %s" % ", ".join(Game.catalog.validate()))
	_own_and_equip("slipstream")
	check(is_equal_approx(Game.circuit_mult(&"iframe_time"), 1.2), "slipstream iframe_time")
	check(is_equal_approx(Game.circuit_value(&"runners_debt"), 0.25), "slipstream runners_debt")

	var menu: MenuScreen = load("res://ui/menus/ShopMenu.gd").new()
	add_child(menu)
	var bootleg: ShopItem = shop.items[0]
	check(bootleg.kind == ShopItem.Kind.UPGRADE and bootleg.upgrade_flag == "injector_upgrades_bootleg", "item 0 should be the Bootleg Injector")
	check(menu.item_price(bootleg) == 260, "bootleg price")
	var cap := player.combat.injector_capacity()
	check(not menu.is_owned(bootleg), "bootleg owned before purchase")
	Game.state.scrap_banked = 1000
	check(menu.buy(bootleg), "bootleg purchase failed")
	check(player.combat.injector_capacity() == cap + 1, "bootleg did not raise injector capacity")
	check(menu.is_owned(bootleg), "bootleg should show as owned")
	check(not menu.buy(bootleg), "bought the bootleg twice")
	# Mara's Spare Injector is a separate item on a separate flag: it stacks.
	var spare: ShopItem = (load("res://data/shops/shop_mara.tres") as ShopData).items[2]
	check(not menu.is_owned(spare), "bootleg must not mark Mara's injector owned")
	check(menu.buy(spare), "spare injector purchase failed")
	check(player.combat.injector_capacity() == cap + 2, "injector upgrades should stack")
	menu.queue_free()


func test_menus_open_and_close_without_errors() -> void:
	Game.grant_circuit("scavenger")
	var loadout: MenuScreen = load("res://ui/menus/LoadoutMenu.gd").new()
	add_child(loadout)
	loadout.open_menu()
	check(get_tree().paused, "loadout should pause")
	loadout.close_menu()
	check(not get_tree().paused, "loadout should unpause")
	loadout.queue_free()
