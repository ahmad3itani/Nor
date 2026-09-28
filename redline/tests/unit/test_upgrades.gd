extends RedlineTestCase
## Upgrades and schematics (expansion PW1, D-182..D-187, D-218): the data,
## the buy/grant/rebranch rules, stat scoping, save/NG+/sandbox handling and
## the one secret rule schematics follow.

const SAVE_V3 := "res://tests/fixtures/save_v3_slice.json"
const ROOM_A := "res://tests/fixtures/WorldA.tscn"
## Written for one test and removed in its body after the last scan, and
## again in after_each (never committed): a scene in a
## world-room folder, so every secret scan sees it as the runtime would.
const TMP_ROOM := "res://world/rooms/undercity/ZzTestSchematicFixture.tscn"
const PHASE1 := ["pulse_blade", "split_katars", "service_pistol", "scattergun", "heavy_revolver", "dash_coil",
	"evade_servo", "injector_rework", "surge", "capacity_lattice"]

var _got: Array = []


func before_each() -> void:
	Game.new_game()
	_got.clear()


func after_each() -> void:
	Challenges.force_active = false
	if FileAccess.file_exists(TMP_ROOM):
		DirAccess.remove_absolute(TMP_ROOM)
		SliceStats.clear_cache()
		NewGamePlus.clear_cache()
		WorldMapIndex.clear_cache()
	UpgradeLibrary.clear_cache()
	Game.new_game()


func _on_purchased(id: String, tier: int, price: int) -> void:
	_got.append([id, tier, price])


func _tier(price: int, mults: Dictionary, vals: Dictionary, br: int = 0) -> UpgradeTier:
	var t := UpgradeTier.new()
	t.price = price
	t.multipliers = mults
	t.values = vals
	t.branch = br
	return t


func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true


func _fixture_branch() -> UpgradeData:
	var u := UpgradeData.new()
	u.id = "test_fixture_branch"
	u.display_name = "Fixture"
	u.category = UpgradeData.Category.ABILITY
	u.tiers.append(_tier(50, {"dash_cooldown": 0.9}, {}))
	u.tiers.append(_tier(100, {"weapon_damage": 1.2}, {}, 1))
	u.tiers.append(_tier(120, {"hit_reactor_gain": 1.3}, {}, 2))
	u.tiers.append(_tier(90, {"charge_time": 0.7}, {}, 3))
	return u


func test_data_valid() -> void:
	var all := UpgradeLibrary.all()
	var ids := {}
	for u in all:
		check(not ids.has(u.id), "duplicate upgrade id %s" % u.id)
		ids[u.id] = true
		check(u.validate().is_empty(), "%s: %s" % [u.id, u.validate()])
		check(u.content_check().is_empty(), "%s: %s" % [u.id, u.content_check()])
		for t in u.tiers:
			for k in t.multipliers.keys() + t.values.keys():
				check(UpgradeData.KNOWN_STATS.has(StringName(k)), "%s: unknown stat %s" % [u.id, k])
			check(t.summary != "" and t.summary.length() <= 90, "%s: tier summary 1-90 chars" % u.id)
		if u.weapon_id != "":
			check(Game.catalog.weapon(u.weapon_id) != null, "%s: weapon in catalog" % u.id)
		var v := ContentValidator.new()
		v.check_resource(u, "res://data/upgrades/%s.tres" % u.id)
		check(v.errors.is_empty(), "%s lints clean: %s" % [u.id, v.errors])
	for id in PHASE1:
		check(ids.has(id), "Phase-1 upgrade %s exists" % id)
	var sch := SchematicList.shared()
	check(sch.validate().is_empty(), "schematics.tres: %s" % [sch.validate()])
	for id in ["foundry_pattern", "deflector", "servo_coil", "resonator", "drain_baffle", "arc_capacitor", "guard_breaker"]:
		check(sch.has_id(id) and sch.district_of(id) != "", "schematic %s named and placed" % id)
	# The fixture rules: a broken branch group and an unknown stat fail.
	var bad := _fixture_branch()
	bad.tiers[2].branch = 3
	bad.tiers[3].branch = 2
	check(not bad.validate().is_empty(), "branch tiers out of order fail")
	var odd := _fixture_branch()
	odd.tiers[0].values = {"max_health_bonus": 1}
	check(not odd.validate().is_empty(), "max_health_bonus is not a stat yet (D-211)")
	var cond := _fixture_branch()
	cond.tiers[0].requires = PackedStringArray(["flag:sch_nope"])
	check(not cond.content_check().is_empty(), "an unknown schematic is an error")
	# Exact Phase-1 prices and the granted Surge I (D-218).
	var want := {"pulse_blade": 110, "split_katars": 110, "service_pistol": 70, "scattergun": 100, "heavy_revolver": 110,
		"dash_coil": 120, "evade_servo": 80, "injector_rework": 110, "surge": 160, "capacity_lattice": 240}
	var stock := 0
	for id: String in want:
		var u := UpgradeLibrary.get_upgrade(id)
		check(u != null and u.tiers.size() == 1 and u.tiers[0].price == want[id], "%s Phase-1 price %d" % [id, want[id]])
		if u:
			stock += u.tiers[0].price
			check(u.tiers[0].granted == (id == "surge"), "%s granted only for Surge I" % id)
	check(stock == 1210, "Phase-1 stock 1,210 (%d)" % stock)
	check(UpgradeLibrary.get_upgrade("capacity_lattice").station == UpgradeData.Station.VELL, "the Lattice is Vell's")


func test_buy_flow() -> void:
	EventBus.upgrade_purchased.connect(_on_purchased)
	var u := UpgradeLibrary.get_upgrade("pulse_blade")
	var t := UpgradeLibrary.next_tiers(u)[0]
	Game.state.scrap_banked = 500
	check(not UpgradeLibrary.can_buy(u, t), "requires block (no met_mara)")
	check(UpgradeLibrary.missing(t) == PackedStringArray(["flag:met_mara"]), "missing lists the requirement")
	check(not UpgradeLibrary.buy(u, t) and Game.state.total_scrap() == 500, "a blocked buy spends nothing")
	Game.set_flag("met_mara")
	Challenges.force_active = true
	check(not UpgradeLibrary.can_buy(u, t) and not UpgradeLibrary.buy(u, t), "refused while a challenge runs (D-147)")
	Challenges.force_active = false
	Game.state.scrap_banked = 100
	check(not UpgradeLibrary.can_buy(u, t), "110 Scrap needed")
	Game.state.scrap_banked = 500
	check(UpgradeLibrary.buy(u, t), "bought")
	check(Game.flag_int("upg_pulse_blade") == 1 and Game.state.total_scrap() == 390, "flag +1, 110 spent")
	check(_got == [["pulse_blade", 1, 110]], "upgrade_purchased(pulse_blade, 1, 110): %s" % [_got])
	check(UpgradeLibrary.next_tiers(u).is_empty() and not UpgradeLibrary.buy(u, t), "MAX blocks")
	check(UpgradeLibrary.total_owned() == 1 and Game.count_metric("upgrades") == 1, "count:upgrades reads purchases")
	check(Game.has_flag("hint_charge"), "the charge hint is shown once at install")
	# The granted Surge I is never bought.
	var s := UpgradeLibrary.get_upgrade("surge")
	Game.set_flag("warden_krail_defeated")
	check(not UpgradeLibrary.can_buy(s, s.tiers[0]), "a granted tier is not for sale")
	EventBus.upgrade_purchased.disconnect(_on_purchased)


func test_branch_exclusive() -> void:
	var u := _fixture_branch()
	check(u.validate().is_empty(), "fixture valid: %s" % [u.validate()])
	check(u.max_tier() == 2 and u.branch_start() == 1, "one plain tier + one branch step")
	Game.state.scrap_banked = 1000
	check(UpgradeLibrary.next_tiers(u).size() == 1, "first the plain tier")
	check(UpgradeLibrary.buy(u, u.tiers[0]), "tier 1")
	var offer := UpgradeLibrary.next_tiers(u)
	check(offer.size() == 3, "then the three branches together")
	check(UpgradeLibrary.buy(u, u.tiers[2]), "Flow bought")
	check(Game.flag_int(u.flag()) == 2 and Game.flag_int(u.branch_flag()) == 2, "tier 2, branch 2")
	check(not UpgradeLibrary.buy(u, u.tiers[1]), "no second branch")
	check(_same(UpgradeLibrary.stats_for(u), [u.tiers[0], u.tiers[2]]), "only the owned branch applies")
	var before := Game.state.total_scrap()
	check(UpgradeLibrary.rebranch(u, 3), "rebranch to Utility")
	check(Game.state.total_scrap() == before - 40 and Game.flag_int(u.flag()) == 2 and Game.flag_int(u.branch_flag()) == 3,
		"40 Scrap, tier unchanged, branch 3")
	check(_same(UpgradeLibrary.stats_for(u), [u.tiers[0], u.tiers[3]]), "Utility applies now")
	check(not UpgradeLibrary.rebranch(u, 3), "same branch refused")
	Challenges.force_active = true
	check(not UpgradeLibrary.rebranch(u, 1), "rebranch refused in a challenge")
	Challenges.force_active = false
	check(UpgradeLibrary.sink_of(u) == 50 + 120, "one price per branch group (the highest): %d" % UpgradeLibrary.sink_of(u))
	check(UpgradeLibrary.act_max(u, 1) == Vector2i(2, 1), "act max includes the group")


func test_weapon_scope() -> void:
	Game.set_flag("upg_split_katars", 1)
	check(Game.upgrade_mult(&"weapon_damage", "pulse_blade") == 1.0, "a katar upgrade never changes the blade")
	check(Game.upgrade_mult(&"weapon_damage", "") == 1.0, "nor a global query")
	check_near(Game.upgrade_mult(&"weapon_damage", "split_katars"), 1.1, 0.0001, "the katars read it")
	check(Game.upgrade_value(&"charge_heavy", "split_katars") == 1.0, "Mk II charges")
	Game.set_flag("upg_dash_coil", 1)
	check_near(Game.upgrade_mult(&"dash_cooldown", "pulse_blade"), 0.8, 0.0001, "global upgrades count for every weapon")
	check_near(Game.upgrade_mult(&"dash_cooldown"), 0.8, 0.0001, "and for a global query")


func test_capacity_lattice() -> void:
	var base := Game.core_capacity()
	Game.set_flag("upg_capacity_lattice", 1)
	check(Game.core_capacity() == base + 1, "Lattice I: capacity +1 (%d -> %d)" % [base, Game.core_capacity()])
	# CIRCUITS.md band: Act I max capacity (4 + 5 shards + Lattice I) against
	# the catalog's total Circuit cost stays 40-50 %.
	var cost := 0
	for c in Game.catalog.circuits:
		cost += (c as CircuitData).cost
	var act1_max := Game.catalog.base_core_capacity + 5 + UpgradeLibrary.act_max(UpgradeLibrary.get_upgrade("capacity_lattice"), 1).x
	var ratio := float(act1_max) / float(cost)
	check(act1_max == 10 and cost == 21, "Act I: capacity 10 of 21 (%d of %d)" % [act1_max, cost])
	check(ratio >= 0.40 and ratio <= 0.50, "capacity band %.2f" % ratio)


func test_injector_bonus_stat() -> void:
	var before := Game.injector_bonus()
	var u := UpgradeData.new()
	u.id = "test_fixture_injector"
	u.display_name = "Fixture"
	u.category = UpgradeData.Category.CORE
	u.station = UpgradeData.Station.LUMA
	u.tiers.append(_tier(100, {}, {"injector_bonus": 1}))
	UpgradeLibrary.all().append(u)
	check(Game.injector_bonus() == before, "not owned: no bonus")
	Game.set_flag(u.flag(), 1)
	check(Game.injector_bonus() == before + 1, "Field Injector style tier adds one charge (D-213)")
	Game.set_flag("injector_upgrades", 1)
	check(Game.injector_bonus() == before + 2, "and stacks with the shop injectors")


func test_old_save_loads() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE_V3))
	var st := GameState.from_dict(SaveManager.migrate(raw))
	Game.state = st
	for f in UpgradeLibrary.all_flags():
		check(Game.flag_int(f) == 0, "%s reads 0 in an old save" % f)
	check(Game.core_capacity() == Game.catalog.base_core_capacity + st.core_shards, "capacity unchanged")
	check(Game.upgrade_mult(&"weapon_damage", st.melee_weapon) == 1.0, "no stat moves")


func test_ng_plus_carries_upgrades_and_schematics() -> void:
	var old := GameState.new()
	old.flags = {"act1_complete": true, "upg_pulse_blade": 1, "upg_capacity_lattice": 1, "sch_drain_baffle": true}
	old.collected = {"schem_drain_baffle": true}
	var s := NewGamePlus.carry(old, NewGamePlus.config(), {"remix": false, "keep_dash": false}, Game.onboarding)
	check(int(s.flags.get("upg_pulse_blade", 0)) == 1 and int(s.flags.get("upg_capacity_lattice", 0)) == 1, "upgrades carry")
	check(bool(s.flags.get("sch_drain_baffle", false)), "schematics carry (sch_ prefix)")
	check(not s.collected.has("schem_drain_baffle"), "the pickup id does not carry")
	Game.state = s
	var banners: Array = []
	var on_hint := func(text: String, _sec: float) -> void: banners.append(text)
	EventBus.hint_requested.connect(on_hint)
	var c := Collectible.new()
	c.persist_id = "schem_drain_baffle"
	c.kind = Collectible.Kind.SCHEMATIC
	c.schematic_id = "drain_baffle"
	add_child(c)
	check(not c.is_queued_for_deletion() and c._husk, "cycle 1: the spot is a husk")
	check(not c.monitoring and c.collision_mask == 0 and not c.body_entered.is_connected(c._on_body_entered), "no pickup")
	check(banners.is_empty(), "no banner")
	EventBus.hint_requested.disconnect(on_hint)
	c.free()


func test_kits_have_no_upgrades() -> void:
	var profile := GameState.new()
	profile.flags = {"upg_pulse_blade": 1, "upg_dash_coil": 1}
	for path in DataDir.list("res://data/challenges/kits"):
		var kit := load(path) as ChallengeKit
		if kit == null or kit.use_profile_loadout:
			continue
		var s := ProfileSandbox.kit_state(kit, null, profile)
		for f: String in s.flags:
			check(not f.begins_with("upg_"), "%s sets %s" % [path.get_file(), f])
		for f: String in kit.int_flags:
			check(not f.begins_with("upg_"), "%s int_flags names %s" % [path.get_file(), f])
		for f in kit.set_flags:
			check(not f.begins_with("upg_"), "%s set_flags names %s" % [path.get_file(), f])


func test_deep_rig_copies_upgrades() -> void:
	var profile := GameState.new()
	profile.flags = {"upg_pulse_blade": 1, "met_mara": true}
	var kit := ChallengeKit.new()
	kit.use_profile_loadout = true
	var s := ProfileSandbox.kit_state(kit, null, profile)
	check(int(s.flags.get("upg_pulse_blade", 0)) == 1, "the Deep Rig copies the profile's upgrades")
	check(not s.flags.has("met_mara"), "and never its progress flags")


func test_flag_sandbox_act1_max() -> void:
	var restore := FlagSandbox.begin()
	FlagSandbox.apply_act1_max_state()
	for u in UpgradeLibrary.all():
		var m := UpgradeLibrary.act_max(u, 1)
		check(Game.flag_int(u.flag()) == m.x, "%s at its Act I max %d (%s)" % [u.id, m.x, Game.state.flags.get(u.flag())])
		if u.branch_start() >= 0:
			check(Game.flag_int(u.branch_flag()) == m.y, "%s branch %d" % [u.id, m.y])
	check(Game.flag_int("upg_surge") == 1 and Game.flag_int("upg_capacity_lattice") == 1, "Surge I and Lattice I in the max state")
	restore.call()
	check(Game.flag_int("upg_surge") == 0, "the sandbox restores")


func test_grant_path() -> void:
	EventBus.upgrade_purchased.connect(_on_purchased)
	var banners: Array = []
	var on_hint := func(text: String, _sec: float) -> void: banners.append(text)
	EventBus.hint_requested.connect(on_hint)
	Game.state.scrap_banked = 300
	var d := DialogueData.new()
	d.id = "test_grant"
	d.lines.append(DialogueLine.new())
	d.give_upgrade = "surge"
	Game.apply_dialogue(d)
	check(Game.flag_int("upg_surge") == 1 and Game.state.total_scrap() == 300, "Surge I installed at 0 Scrap")
	check(_got == [["surge", 1, 0]], "upgrade_purchased(surge, 1, 0): %s" % [_got])
	check(banners.size() == 1 and Game.has_flag("hint_surge"), "the Surge hint shows once (%s)" % [banners])
	check(UpgradeLibrary.total_owned() == 0, "a grant is not a purchase")
	Game.apply_dialogue(d)
	check(_got.size() == 1 and banners.size() == 1, "a second give does nothing")
	var v := ContentValidator.new()
	v._check_dialogue(d, "res://data/npcs/test_grant.tres", v._catalog())
	check(v.errors.is_empty(), "giving a granted tier lints clean: %s" % [v.errors])
	var sold := DialogueData.new()
	sold.id = "test_grant_sold"
	sold.lines.append(DialogueLine.new())
	sold.give_upgrade = "dash_coil"
	v._check_dialogue(sold, "res://data/npcs/test_grant.tres", v._catalog())
	check(v.errors.size() == 1, "giving a bought tier is an error: %s" % [v.errors])
	sold.give_upgrade = "nope"
	v._check_dialogue(sold, "res://data/npcs/test_grant.tres", v._catalog())
	check(v.errors.size() == 2, "an unknown upgrade is an error: %s" % [v.errors])
	EventBus.hint_requested.disconnect(on_hint)
	EventBus.upgrade_purchased.disconnect(_on_purchased)


func test_schematic_reader_rule() -> void:
	var a := AchievementData.new()
	a.id = "test_sch_reader"
	a.conditions = PackedStringArray(["flag:sch_deflector"])
	var v := ContentValidator.new()
	v._check_schematic_readers(a, "res://data/achievements/test.tres")
	check(v.errors.size() == 1, "an achievement may not read a schematic: %s" % [v.errors])
	var q := QuestData.new()
	q.start_flag = "sch_resonator"
	v._check_schematic_readers(q, "res://data/quests/test.tres")
	check(v.errors.size() == 2, "a quest may not either: %s" % [v.errors])
	check(not ContentValidator.COUNT_METRICS.has("schematics"), "no count metric for schematics")
	check(ContentValidator.COUNT_METRICS.has("upgrades"), "count:upgrades is a metric")


## A SCHEMATIC pickup sets its flag, marks its id and shows the banner.
func test_schematic_pickup() -> void:
	var root := Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	SceneRouter.goto_room(ROOM_A, &"start")
	await physics_frames(3)
	var room := SceneRouter.current_room as Room
	var banners: Array = []
	var on_hint := func(text: String, _sec: float) -> void: banners.append(text)
	EventBus.hint_requested.connect(on_hint)
	var c := Collectible.new()
	c.persist_id = "schem_arc_capacitor"
	c.kind = Collectible.Kind.SCHEMATIC
	c.schematic_id = "arc_capacitor"
	c.position = Vector2(80, 0)
	room.add_child(c)
	var errs := c.content_errors(room)
	check(errs.is_empty(), "a well-formed schematic lints clean: %s" % [errs])
	check(c.content_flags() == {"produces": ["sch_arc_capacitor"]}, "it produces its flag")
	room.player.teleport(Vector2(80, -2))
	await physics_frames(3)
	check(Game.has_flag("sch_arc_capacitor") and Game.is_collected("schem_arc_capacitor"), "flag and collected id set")
	check(banners.size() == 1 and String(banners[0]).contains("Annex capacitor"), "banner names it: %s" % [banners])
	check(Game.state.scrap_unbanked == 0 and Game.state.core_shards == 0, "no Scrap, no shard")
	EventBus.hint_requested.disconnect(on_hint)
	var bad := Collectible.new()
	bad.kind = Collectible.Kind.SCHEMATIC
	bad.schematic_id = "nope"
	bad.persist_id = "schem_nope"
	check(bad.content_errors(room).size() == 1, "an unknown schematic id is an error")
	bad.schematic_id = "deflector"
	bad.persist_id = "sch_deflector"
	check(bad.content_errors(room).size() == 1, "persist ids are schem_<id>")
	bad.free()
	SceneRouter.current_room = null
	SceneRouter.world_root = null
	root.queue_free()
	await physics_frames(2)


## Repair 3: one secret rule. A room in a demo folder with one SCHEMATIC and
## one BreakableWall adds exactly 1 secret to SliceStats, DemoRules and the
## direct scan test_demo_flow runs, and the tracker labels it 'schematic'.
func test_schematic_never_a_secret() -> void:
	SliceStats.clear_cache()
	var base_ids := (SliceStats.totals()["secret_ids"] as Array).size()
	var demo := load("res://data/release/demo.tres") as DemoConfig
	var base_demo := int(DemoRules.scope(demo)["totals"]["secrets"])
	var room := Room.new()
	room.name = "ZzTestSchematicFixture"
	var c := Collectible.new()
	c.name = "Schematic"
	c.persist_id = "schem_drain_baffle"
	c.kind = Collectible.Kind.SCHEMATIC
	c.schematic_id = "drain_baffle"
	room.add_child(c)
	c.owner = room
	var w := BreakableWall.new()
	w.name = "Wall"
	w.persist_id = "test_schem_wall"
	room.add_child(w)
	w.owner = room
	var packed := PackedScene.new()
	check(packed.pack(room) == OK, "fixture packs")
	room.free()
	check(ResourceSaver.save(packed, TMP_ROOM) == OK, "fixture written")
	SliceStats.clear_cache()
	var ids: Array = SliceStats.totals()["secret_ids"]
	check(ids.size() == base_ids + 1 and ids.has("test_schem_wall") and not ids.has("schem_drain_baffle"),
		"SliceStats counts the wall only (%d -> %d)" % [base_ids, ids.size()])
	check(int(DemoRules.scope(demo)["totals"]["secrets"]) == base_demo + 1, "DemoRules counts the wall only")
	var inst := (load(TMP_ROOM) as PackedScene).instantiate()
	var direct := 0
	for n in inst.find_children("*", "", true, false):
		if (n is Collectible and Collectible.counts_as_secret((n as Collectible).kind)) or n is BreakableWall:
			direct += 1
	inst.free()
	check(direct == 1, "the test_demo_flow direct scan counts 1 (%d)" % direct)
	var v := ContentValidator.new()
	v.check_room(TMP_ROOM, false)
	var kinds := {}
	for e: Dictionary in v.collectibles.get("ZzTestSchematicFixture", []):
		kinds[e["id"]] = e["kind"]
	check(kinds.get("schem_drain_baffle", "") == "schematic", "the tracker labels it 'schematic': %s" % [kinds])
	WorldMapIndex.clear_cache()
	var map_ids := []
	for sp: Dictionary in WorldMapIndex.room_info(TMP_ROOM)["secrets"]:
		map_ids.append(sp["id"])
	WorldMapIndex.clear_cache()
	check(map_ids == ["test_schem_wall"], "the map counts the wall only: %s" % [map_ids])
	# Removed here, not only in after_each, so a killed run cannot leave it in
	# a shipped room folder.
	DirAccess.remove_absolute(TMP_ROOM)
	SliceStats.clear_cache()
	NewGamePlus.clear_cache()
	check(not Collectible.counts_as_secret(Collectible.Kind.SCHEMATIC) and not Collectible.counts_as_secret(Collectible.Kind.SCRAP_BUNDLE)
		and Collectible.counts_as_secret(Collectible.Kind.CORE_SHARD), "counts_as_secret")
