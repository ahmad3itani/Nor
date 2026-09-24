extends RedlineTestCase
## M7 props: bodiless NPCs (figure/verb), NPC presence by world state
## (present_when, map pins included) and FlowZone drain tuning
## (drain_scale, drain_floor), on tests/fixtures/props_flow.tscn
## (tools/roomgen/fixtures_props.py).

const PROPS := "res://tests/fixtures/props_flow.tscn"
## Fixture layout: Flow1 (x1.0) spans x 100..400, Flow2 (x0.5) 250..550,
## Flow3 (x0.5, floor 1) 900..1100.
const X_OUTSIDE := 40.0
const X_FULL_ONLY := 175.0
const X_BOTH := 325.0
const X_HALF_ONLY := 475.0
const X_FLOORED := 1000.0
const MODE_NORMAL := 0
const MODE_CHALLENGE := 2

var root: Node2D
var _saved_mode: int


func before_each() -> void:
	_saved_mode = Settings.reactor_mode
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	Game.new_game()


func after_each() -> void:
	Settings.reactor_mode = _saved_mode
	SceneRouter.current_room = null
	SceneRouter.world_root = null
	root.queue_free()
	Game.new_game()
	await physics_frames(2)


func _enter() -> Room:
	SceneRouter.goto_room(PROPS, &"start")
	await physics_frames(10)
	var room := SceneRouter.current_room as Room
	room.player.input_source = ScriptedInputSource.new()
	return room


## Teleports Rook onto the floor at x and lets the Areas see it.
func _place(p: Player, x: float) -> void:
	p.global_position = Vector2(x, -1)
	p.velocity = Vector2.ZERO
	await physics_frames(4)


func _npc(room: Room, key: String) -> NPC:
	return room.find_child("NPC_" + key, true, false) as NPC


func _zone(room: Room, n: String) -> FlowZone:
	return room.find_child(n, true, false) as FlowZone


# --- NPC objects -------------------------------------------------------------------

func test_npc_figure_false_draws_no_body_and_uses_verb() -> void:
	var room := await _enter()
	var radio := _npc(room, "props_radio")
	var person := _npc(room, "props_npc_not_x")
	check(radio != null and person != null, "fixture NPCs missing")
	check(not radio.draws_figure(), "a radio should not draw a body")
	check(person.draws_figure(), "a person keeps the placeholder figure")
	check(radio.prompt_text().contains("Listen"), "radio prompt should use its verb: %s" % radio.prompt_text())
	check(radio.prompt_text().contains("Radio"), "prompt still names the speaker")
	check(person.prompt_text().begins_with("Talk"), "default verb is Talk: %s" % person.prompt_text())
	check(radio.can_interact(room.player), "radio with no present_when is always usable")


func test_present_when_toggles_on_flag_change() -> void:
	var room := await _enter()
	var with_x := _npc(room, "props_npc_x")
	var without_x := _npc(room, "props_npc_not_x")
	var p := room.player
	check(not with_x.visible and not with_x.can_interact(p), "flag:x NPC should be absent before x")
	check(without_x.visible and without_x.can_interact(p), "!flag:x NPC should be present before x")
	with_x.interact(p)
	check(Game.flag_int("talks_props_npc_x") == 0, "an absent NPC cannot be talked to")
	Game.set_flag("x")
	check(with_x.visible and with_x.can_interact(p), "flag:x NPC should appear once x is set")
	check(not without_x.visible and not without_x.can_interact(p), "!flag:x NPC should leave once x is set")
	# A reset profile (new game / load) re-evaluates too.
	Game.new_game()
	check(not with_x.visible and without_x.visible, "presence should follow game_state_reset")


func test_npc_present_when_consumed_by_validator() -> void:
	var v := ContentValidator.new().check_room(PROPS, false)
	check(v.consumed.has("x"), "present_when flag should count as consumed: %s" % str(v.consumed.keys()))
	for e in v.errors:
		check(not e.contains("drain_"), "fixture drain values should validate: %s" % e)
		check(not e.contains("unknown condition"), "present_when conditions should parse: %s" % e)


func test_map_pins_follow_present_when() -> void:
	var info := WorldMapIndex.room_info(PROPS)
	var by_id := {}
	for n: Dictionary in info["npcs"]:
		by_id[n["id"]] = n
	check(by_id.has("props_npc_x") and by_id.has("props_npc_not_x"), "index should list both NPCs")
	if not (by_id.has("props_npc_x") and by_id.has("props_npc_not_x")):
		return
	check(by_id["props_npc_x"]["present_when"] == PackedStringArray(["flag:x"]), "index should carry present_when")
	check(not WorldMapIndex.npc_present(by_id["props_npc_x"]), "flag:x pin hidden before x")
	check(WorldMapIndex.npc_present(by_id["props_npc_not_x"]), "!flag:x pin shown before x")
	check(WorldMapIndex.npc_present(by_id["props_radio"]), "no present_when = always shown")
	var ids := MapView.visible_npcs(info).map(func(n: Dictionary) -> String: return n["id"])
	check(ids.has("props_npc_not_x") and not ids.has("props_npc_x"), "map pins before x: %s" % str(ids))
	Game.set_flag("x")
	check(WorldMapIndex.npc_present(by_id["props_npc_x"]), "flag:x pin shown after x")
	check(not WorldMapIndex.npc_present(by_id["props_npc_not_x"]), "!flag:x pin hidden after x")
	ids = MapView.visible_npcs(info).map(func(n: Dictionary) -> String: return n["id"])
	check(ids.has("props_npc_x") and not ids.has("props_npc_not_x"), "map pins after x: %s" % str(ids))


# --- FlowZone drain tuning ---------------------------------------------------------

func test_drain_scale_half() -> void:
	Settings.reactor_mode = MODE_NORMAL
	var room := await _enter()
	var p := room.player
	p.reactor.apply_mode(MODE_NORMAL)
	await _place(p, X_HALF_ONLY)
	check(p.reactor.in_flow(), "should be inside the half zone")
	check_near(p.reactor.drain_scale(), 0.5, 0.001, "half zone scale")
	p.reactor.charge = 70.0
	await physics_frames(600)
	check_near(p.reactor.charge, 45.0, 0.5, "10 s at x0.5 in Normal (5/s)")
	var bad := FlowZone.new()
	bad.drain_scale = 0.0
	bad.drain_floor = 100.0
	check(bad.content_errors(null).size() == 2, "out-of-range drain values should be reported")
	check(_zone(room, "Flow2").content_errors(null).is_empty(), "valid zone reports nothing")
	check(_zone(room, "Flow2").debug_text().contains("x0.5"), "debug label shows the scale: %s" % _zone(room, "Flow2").debug_text())
	check(_zone(room, "Flow3").debug_text().contains("floor 1"), "debug label shows the floor: %s" % _zone(room, "Flow3").debug_text())
	check(not _zone(room, "Flow1").debug_text().contains("x"), "untuned zone shows only its label")
	bad.free()


func test_overlapping_zones_use_largest_scale() -> void:
	Settings.reactor_mode = MODE_NORMAL
	var room := await _enter()
	var p := room.player
	p.reactor.apply_mode(MODE_NORMAL)
	await _place(p, X_BOTH)
	check_near(p.reactor.drain_scale(), 1.0, 0.001, "overlap takes the larger scale")
	p.reactor.charge = 70.0
	await physics_frames(120)
	check_near(p.reactor.charge, 60.0, 0.3, "2 s in the overlap drains at the full rate")
	await _place(p, X_HALF_ONLY)
	check_near(p.reactor.drain_scale(), 0.5, 0.001, "leaving Flow1 falls back to Flow2's scale")
	await _place(p, X_OUTSIDE)
	check(not p.reactor.in_flow(), "outside every zone")
	var c := p.reactor.charge
	await physics_frames(60)
	check_near(p.reactor.charge, c, 0.001, "no drain outside zones")


func test_first_flow_clears_core_hud_hidden() -> void:
	var room := await _enter()
	var p := room.player
	Game.set_flag("core_hud_hidden", true)
	var seen: Array = []
	var spy := func(id: String, value: Variant) -> void:
		if id == "core_hud_hidden":
			seen.append(value)
	EventBus.flag_changed.connect(spy)
	await _place(p, X_FULL_ONLY)
	check(not Game.has_flag("core_hud_hidden"), "first Flow entry should reveal the Core HUD")
	check(Game.state.flags.has("core_hud_hidden"), "the key is set to false, never erased")
	check(seen.size() == 1 and seen[0] == false, "one flag_changed(core_hud_hidden, false) expected: %s" % str(seen))
	await _place(p, X_OUTSIDE)
	await _place(p, X_FULL_ONLY)
	check(seen.size() == 1, "a second entry emits nothing more: %s" % str(seen))
	EventBus.flag_changed.disconnect(spy)


func test_drain_floor_prevents_burnout() -> void:
	Settings.reactor_mode = MODE_CHALLENGE
	var room := await _enter()
	var p := room.player
	p.reactor.apply_mode(MODE_CHALLENGE)
	p.reactor.charge = p.reactor.config.start_charge
	check_near(p.reactor.config.start_charge, 60.0, 0.001, "challenge config start")
	var hp := p.combat.health
	var hits: Array = []
	var spy := func(amount: int, _health: int) -> void: hits.append(amount)
	EventBus.player_damaged.connect(spy)
	await _place(p, X_FLOORED)
	check_near(p.reactor.drain_floor(), 1.0, 0.001, "floored zone")
	await physics_frames(1800)
	check_near(p.reactor.charge, 1.0, 0.0001, "30 s in the floored zone stops at the floor")
	check(p.combat.health == hp and hits.is_empty(), "no burnout damage inside a floored zone (hits %s)" % str(hits))
	check(p.reactor.is_critical(), "the critical state still plays at the floor")
	# An ordinary zone still drains to 0 and burns out, as before.
	await _place(p, X_OUTSIDE)
	await _place(p, X_FULL_ONLY)
	await physics_frames(30)
	check_near(p.reactor.charge, 0.0, 0.0001, "unfloored zone drains to 0")
	await physics_frames(int(p.reactor.config.burnout_interval * 60.0) + 5)
	check(p.combat.health < hp, "burnout resumes outside the floored zone")
	EventBus.player_damaged.disconnect(spy)


func test_null_zone_flow_api() -> void:
	var room := await _enter()
	var p := room.player
	var half := _zone(room, "Flow2")
	check(not p.reactor.in_flow(), "starts outside")
	p.reactor.enter_flow()
	p.reactor.enter_flow(half)
	check_near(p.reactor.drain_scale(), 1.0, 0.001, "anonymous zone counts as x1.0")
	p.reactor.exit_flow()
	check(p.reactor.in_flow(), "still inside the named zone")
	check_near(p.reactor.drain_scale(), 0.5, 0.001, "only the half zone left")
	p.reactor.exit_flow(half)
	check(not p.reactor.in_flow(), "left every zone")
	p.reactor.exit_flow()
	check(not p.reactor.in_flow(), "extra anonymous exits never go negative")
	p.reactor.enter_flow()
	check(p.reactor.in_flow(), "one anonymous enter after an extra exit is inside again")
	p.reactor.exit_flow()


func test_freed_zone_is_pruned() -> void:
	var room := await _enter()
	var p := room.player
	var zone := FlowZone.new()
	zone.drain_scale = 0.5
	p.reactor.enter_flow(zone)
	check(p.reactor.in_flow(), "inside the loose zone")
	zone.free()
	await physics_frames(2)
	check(not p.reactor.in_flow(), "a freed zone must not keep Rook in flow")


func test_roomgen_fixture_matches_script() -> void:
	var probe: Array = []
	if OS.execute("sh", ["-c", "command -v python3"], probe) != 0:
		push_warning("python3 not found: fixtures_props.py not run here (it is part of the gate)")
		return
	var out: Array = []
	var code := OS.execute("sh", ["-c", "cd '%s' && python3 -B tools/roomgen/fixtures_props.py --check" % ProjectSettings.globalize_path("res://")], out, true)
	check(code == 0, "fixtures_props.py --check reports drift: %s" % str(out))
