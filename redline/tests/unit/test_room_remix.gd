extends RedlineTestCase
## NG+ room remix (M9 D3 §2.5/§2.6, D-154/D-155, R09.11): the shipped data
## validates against the base rooms, nothing changes while the remix is off,
## every op kind lands while it is on, bosses read the variant before _ready,
## the whitelist keeps geometry, exits, collectibles and arena gates out,
## and a remix never pays more Scrap than the base room.

const UC := "res://world/rooms/undercity/"
const LL := "res://world/rooms/lowlight/"
const MEDICAL := "res://world/rooms/undercity/MedicalRuin.tscn"
const SHAFT := "res://world/rooms/undercity/MaintenanceShaft.tscn"
const BAY := "res://world/rooms/undercity/CollectorBay.tscn"
const TOWER := "res://world/rooms/lowlight/WardenTower.tscn"

var root: Node2D


func before_each() -> void:
	Game.new_game()
	RemixLibrary.clear_cache()


func after_each() -> void:
	if is_instance_valid(root):
		SceneRouter.current_room = null
		SceneRouter.world_root = null
		root.queue_free()
	Game.new_game()
	RemixLibrary.clear_cache()
	await physics_frames(2)


func _inst(path: String) -> Node:
	return (load(path) as PackedScene).instantiate()


func _count(n: Node) -> int:
	return n.find_children("*", "", true, false).size()


func test_every_remix_file_validates() -> void:
	var paths := RemixLibrary.all_paths()
	check(paths.size() == 16, "16 Act I rooms have a remix (Wake and the Relay none): %d" % paths.size())
	for path in paths:
		var r := load(path) as RoomRemix
		check(r != null, "%s loads as a RoomRemix" % path)
		if r == null:
			continue
		check(r.validate().is_empty(), "%s validate: %s" % [path.get_file(), r.validate()])
		var errs := RemixRules.check(r, path)
		check(errs.is_empty(), "%s RemixRules: %s" % [path.get_file(), errs])
		check(r.active_when == "flag:ng_remix", "%s runs only with the NG+ remix option" % path.get_file())
		check(not r.intent.is_empty(), "%s says what it is for" % path.get_file())
	for name in ["Wake", "Relay"]:
		check(RemixLibrary.for_room("res://world/rooms/x/%s.tscn" % name) == null, "%s has no remix" % name)
	var v := ContentValidator.new()
	RemixRules.run(v)
	check(v.errors.is_empty(), "RemixRules over the shipped data: %s" % [v.errors])


func test_inactive_applies_nothing() -> void:
	for path in [MEDICAL, SHAFT, BAY, TOWER]:
		var a := _inst(path)
		var b := _inst(path)
		check(RemixLibrary.apply(a, path) == 0, "%s: no ops while ng_remix is unset" % path.get_file())
		check(_count(a) == _count(b), "%s: node count unchanged" % path.get_file())
		check(int(RemixLibrary.last_applied.get(path, -1)) == 0, "last_applied records 0")
		a.free()
		b.free()


func test_active_ops_land() -> void:
	Game.set_flag("ng_remix")
	var med := _inst(MEDICAL)
	var n := RemixLibrary.apply(med, MEDICAL)
	check(n == 2, "MedicalRuin applies its 2 ops (%d)" % n)
	var n3 := med.get_node_or_null("Enemies/Needle3") as Enemy
	check(n3 != null and is_equal_approx(n3.data.attacks[0].startup, 0.36), "SET Needle3.data = needle_remix")
	check(med.get_node_or_null("Enemies/Needle4") == null, "SWAP removed Needle4")
	var hop := med.get_node_or_null("Enemies/Needle4R") as Enemy
	check(hop != null and hop.data.id == &"hopper", "SWAP placed a Hopper as Needle4R")
	var dormant := med.get_node_or_null("Enemies/Needle1") as Enemy
	check(dormant != null and not dormant.ai_enabled, "the dormant practice Needle is untouched")
	med.free()
	var shaft := _inst(SHAFT)
	var before := shaft.get_node("Enemies").get_child_count()
	RemixLibrary.apply(shaft, SHAFT)
	check(shaft.get_node("Enemies").get_child_count() == before + 1, "ADD appended one enemy")
	var added := shaft.get_node_or_null("Enemies/NeedleR1") as Enemy
	var beside := shaft.get_node("Enemies/Needle2") as Enemy
	check(added != null and added.position == beside.position + Vector2(56, 0), "ADD NeedleR1 stands 56 px from Needle2")
	shaft.free()
	# REMOVE (no shipped room removes; a fixture proves the op).
	var fx := RoomRemix.new()
	fx.room = MEDICAL
	var op := RemixOp.new()
	op.kind = RemixOp.Kind.REMOVE_ENEMY
	op.target = NodePath("Enemies/Needle2")
	fx.ops = [op]
	var med2 := _inst(MEDICAL)
	check(RemixLibrary.apply_ops(med2, fx) == 1 and med2.get_node_or_null("Enemies/Needle2") == null, "REMOVE frees the enemy")
	med2.free()
	# Hazards: SET a timing Resource and a float on whitelisted classes.
	var pb := _inst(LL + "PowerBlock.tscn")
	RemixLibrary.apply(pb, LL + "PowerBlock.tscn")
	var s2 := pb.get_node("Geometry/Shutter_S2") as PowerShutter
	check(s2.timing.resource_path.ends_with("shutter_run_remix.tres"), "SET Shutter_S2.timing")
	pb.free()
	var ss := _inst(LL + "SecurityStation.tscn")
	RemixLibrary.apply(ss, LL + "SecurityStation.tscn")
	check(is_equal_approx((ss.get_node("Hazards/Scanner_ss_high_2") as ScannerBeam).phase, 0.5), "SET Scanner_ss_high_2.phase")
	ss.free()


## A boss SET lands before _ready: the fight reads the variant's health and
## the behaviour's exports (setup copies first_deck into its deck).
func test_boss_set_before_ready() -> void:
	Game.set_flag("ng_remix")
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	for pair: Array in [[BAY, "Enemies/CollectorDrone1", 420.0], [TOWER, "Enemies/WardenKrail1", 560.0]]:
		SceneRouter.goto_room(pair[0], &"")
		await physics_frames(3)
		var boss := SceneRouter.current_room.get_node_or_null(pair[1]) as Enemy
		check(boss != null and is_equal_approx(boss.data.max_health, pair[2]) and is_equal_approx(boss.health, pair[2]),
			"%s: health %s from the variant" % [pair[1], boss.health if boss else -1.0])
		check(boss != null and boss.data.scrap_drop == (80 if pair[0] == BAY else 150), "the boss keeps its base drop (R09.11)")
	SceneRouter.goto_room(BAY, &"")
	await physics_frames(3)
	var beh := SceneRouter.current_room.get_node("Enemies/CollectorDrone1/Behavior")
	check(is_equal_approx(float(beh.get("phase2_threshold")), 0.6) and int(beh.get("rng_seed")) == 23, "Collector behaviour exports set")
	var deck: Array = beh.get("_deck")
	var first: Array = beh.get("first_deck")
	check(first.size() == 4 and first[0] == &"collector_tag_volley", "first_deck in the remix order (%s)" % [first])
	check(deck.size() <= 4 and deck.all(func(c: StringName) -> bool: return first.has(c)), "setup dealt the remix first deck (%s)" % [deck])
	SceneRouter.goto_room(TOWER, &"")
	await physics_frames(3)
	var kb := SceneRouter.current_room.get_node("Enemies/WardenKrail1/Behavior")
	check((kb.get("summon_offsets") as Array).size() == 3 and (kb.get("summon_scene") as PackedScene).resource_path.ends_with("Hopper.tscn"),
		"Krail summons Hoppers at three offsets")


## RM-2/RM-3/RM-4 on fixtures: geometry, exits, collectibles and the arena
## gates are rejected, stale names are errors, an ADD outside the bounds is
## an error, and apply skips every bad op.
func test_whitelist_rejects_geometry_exits_collectibles_gates() -> void:
	var fx := RoomRemix.new()
	fx.room = BAY
	var bad := [
		["Geometry/Floor", &"position", "RM-3"],
		["Triggers/Exit1", &"target_room", "RM-3"],
		["Interactables/Collectible1", &"scrap_amount", "RM-3"],
		["Geometry/ArenaGateLeft", &"position", "RM-3"],
		["Triggers/BossArena", &"boss_id", "RM-3"],
		["Enemies/CollectorDrone1", &"scrap_drop", "RM-3"],
		["Enemies/Needle99", &"data", "RM-2"],
	]
	for b: Array in bad:
		var op := RemixOp.new()
		op.kind = RemixOp.Kind.SET
		op.target = NodePath(b[0])
		op.property = b[1]
		op.value = 1
		fx.ops.append(op)
	var out_of_bounds := RemixOp.new()
	out_of_bounds.kind = RemixOp.Kind.ADD_ENEMY
	out_of_bounds.target = NodePath("Enemies/CollectorDrone1")
	out_of_bounds.scene_kind = "Needle"
	out_of_bounds.data = load("res://data/enemies/needle_remix.tres")
	out_of_bounds.offset = Vector2(5000, 0)
	fx.ops.append(out_of_bounds)
	var errs := RemixRules.check(fx, "res://data/remix/CollectorBay.tres")
	for b: Array in bad:
		check(Array(errs).any(func(e: String) -> bool: return e.begins_with("[%s]" % b[2]) and e.contains(String(b[0]))),
			"%s.%s is an %s error" % [b[0], b[1], b[2]])
	check(Array(errs).any(func(e: String) -> bool: return e.begins_with("[RM-4]")), "an ADD outside the bounds is an RM-4 error")
	check(RemixRules.check(fx, "res://data/remix/Elsewhere.tres").has(
		"[RM-1] Elsewhere.tres: the file name must equal the room basename (CollectorBay.tscn)"), "RM-1 file name rule")
	var inst := _inst(BAY)
	var floor_pos := (inst.get_node("Geometry/Floor") as Node2D).position
	fx.ops.pop_back()
	check(RemixLibrary.apply_ops(inst, fx) == 0, "every whitelisted-out op is skipped")
	check((inst.get_node("Geometry/Floor") as Node2D).position == floor_pos, "the floor did not move")
	inst.free()
	# The whitelist table itself (a pin: widening it is a design decision).
	check(RemixOp.SET_WHITELIST.keys().size() == 8 and not RemixOp.SET_WHITELIST.has("Collectible") and not RemixOp.SET_WHITELIST.has("RoomExit"),
		"SET_WHITELIST as D3 §2.5")


func test_remix_enemy_data_drops_nothing() -> void:
	var found := 0
	for path in DataDir.list("res://data/enemies"):
		if path.get_file().get_basename().ends_with("_remix"):
			found += 1
			var d := load(path) as EnemyData
			check(d.scrap_drop == 0, "%s drops 0 Scrap (RM-5)" % path.get_file())
			check(d.validate().is_empty(), "%s validates: %s" % [path.get_file(), d.validate()])
	check(found == 9, "nine remix EnemyData files (%d)" % found)
	var v := ContentValidator.new()
	var fx := RoomRemix.new()
	fx.room = MEDICAL
	var op := RemixOp.new()
	op.kind = RemixOp.Kind.ADD_ENEMY
	op.target = NodePath("Enemies/Needle2")
	op.scene_kind = "Needle"
	op.data = load("res://data/enemies/needle.tres")
	fx.ops = [op]
	check(Array(RemixRules.check(fx, "res://data/remix/MedicalRuin.tres")).any(func(e: String) -> bool: return e.begins_with("[RM-5]")),
		"an ADD with a paying EnemyData is an RM-5 error")
	check(v.errors.is_empty(), "no stray errors")


## R09.11: a SET/SWAP replacement pays what the replaced enemy paid; an ADD
## pays nothing. The shared variant file itself stays at 0.
func test_remix_set_keeps_base_scrap() -> void:
	Game.set_flag("ng_remix")
	var med := _inst(MEDICAL)
	RemixLibrary.apply(med, MEDICAL)
	var needle := (load("res://data/enemies/needle.tres") as EnemyData).scrap_drop
	check((med.get_node("Enemies/Needle3") as Enemy).data.scrap_drop == needle, "SET Needle3 drops the base %d" % needle)
	check((med.get_node("Enemies/Needle4R") as Enemy).data.scrap_drop == needle, "SWAP Needle4R drops the replaced Needle's %d" % needle)
	med.free()
	var shaft := _inst(SHAFT)
	RemixLibrary.apply(shaft, SHAFT)
	check((shaft.get_node("Enemies/NeedleR1") as Enemy).data.scrap_drop == 0, "ADD NeedleR1 drops 0")
	shaft.free()
	check((load("res://data/enemies/needle_remix.tres") as EnemyData).scrap_drop == 0, "the variant file still drops 0")


func test_overlay_line() -> void:
	Game.set_flag("ng_remix")
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	SceneRouter.goto_room(MEDICAL, &"")
	await physics_frames(2)
	check(Array(DebugOverlay.provider_lines()).has("REMIX MedicalRuin ops=2 active"), "F1 line: %s" % [DebugOverlay.provider_lines()])
	Game.set_flag("ng_remix", false)
	SceneRouter.goto_room(MEDICAL, &"")
	await physics_frames(2)
	check(Array(DebugOverlay.provider_lines()).has("REMIX MedicalRuin ops=0 off"), "F1 line when off: %s" % [DebugOverlay.provider_lines()])


func test_remix_act1_py_check() -> void:
	var probe: Array = []
	if OS.execute("sh", ["-c", "command -v python3"], probe) != 0:
		push_warning("python3 not found: remix_act1.py not run here (it is part of the gate)")
		return
	var out: Array = []
	var code := OS.execute("sh", ["-c", "cd '%s' && python3 -B tools/roomgen/remix_act1.py --check" % ProjectSettings.globalize_path("res://")], out, true)
	check(code == 0, "remix_act1.py --check reports drift: %s" % [out])
