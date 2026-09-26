extends RedlineTestCase
## M9 T11 (D4 §8.1-§8.5, §13): aim assist, damage assist with its carry, the
## burnout toggle, generous checkpoints and the "Always full height" jump.

const PLAYER_SCENE := preload("res://player/Player.tscn")
const TMP_CFG := "user://test_assists.cfg"
const SAVE_DIR := "user://test_assists_saves"
const BROKEN_LIFT := "res://world/rooms/undercity/BrokenLift.tscn"
const COLLECTOR_BAY := "res://world/rooms/undercity/CollectorBay.tscn"
const RAINLINE_CHASE := "res://world/rooms/lowlight/RainlineChase.tscn"
const MARKET := "res://world/rooms/lowlight/MarketRun.tscn"
const ALLEY := "res://world/rooms/lowlight/FloodedAlley.tscn"

var world: Node2D
var player: Player
var input: ScriptedInputSource
var _snap: Dictionary = {}
var _extras: Array[Node] = []
var _damaged: Array = []


func before_each() -> void:
	_snap = snapshot_settings()
	Settings.remove_settings_files(TMP_CFG)
	Settings._path = TMP_CFG
	Settings.apply_defaults()
	# Anchors save: never into the developer's own profiles.
	SaveManager.save_dir = SAVE_DIR
	Game.new_game()
	world = Node2D.new()
	add_child(world)
	_damaged.clear()


func after_each() -> void:
	for n in _extras:
		if is_instance_valid(n):
			n.queue_free()
	_extras.clear()
	if is_instance_valid(world):
		world.queue_free()
	await get_tree().process_frame
	get_tree().paused = false
	SceneRouter.current_room = null
	SceneRouter.current_room_path = ""
	SceneRouter.world_root = null
	SceneRouter._fade = null
	SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR
	AtomicJson.remove_tree(SAVE_DIR)
	Settings.remove_settings_files(TMP_CFG)
	restore_settings(_snap)
	Game.new_game()
	await physics_frames(2)


func _floor(pos: Vector2, size: Vector2) -> void:
	var b := GrayboxBlock.new()
	b.size = size
	b.position = pos
	world.add_child(b)


func _spawn_player(at: Vector2 = Vector2(100, 198)) -> void:
	_floor(Vector2(-200, 200), Vector2(1600, 64))
	player = PLAYER_SCENE.instantiate()
	player.abilities = PlayerAbilities.new()
	input = ScriptedInputSource.new()
	player.input_source = input
	world.add_child(player)
	player.respawn(at)
	player.combat.config = player.combat.config.duplicate()
	await physics_frames(3)


func _enemy(path: String, pos: Vector2) -> Enemy:
	var e: Enemy = load(path).instantiate()
	e.ai_enabled = false
	e.position = pos
	world.add_child(e)
	return e


func _on_damaged(amount: int, health: int) -> void:
	_damaged.append([amount, health])


# --- Aim (D4 §8.1) -------------------------------------------------------------

func _cands(list: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c: Dictionary in list:
		out.append(c)
	return out


func test_aim_off_unchanged() -> void:
	var c := _cands([{"pos": Vector2(100, 5), "visible": true}])
	check(AimAssist.adjust(Vector2.RIGHT, Vector2.ZERO, c, 0.0, 0.0) == Vector2.RIGHT, "Off leaves the aim alone")
	var off := AimAssist.cone_and_range(0, Settings.config())
	check(off == Vector2.ZERO, "index 0 is Off (%s)" % off)
	await _spawn_player()
	Settings.aim_assist = 0
	check(player.combat.assisted_aim(Vector2.RIGHT, player.global_position) == Vector2.RIGHT, "Off: PlayerCombat keeps the aim")


func test_aim_picks_smallest_angle() -> void:
	var c := _cands([
		{"pos": Vector2(100, 30), "visible": true},
		{"pos": Vector2(60, 5), "visible": true},
		{"pos": Vector2(100, -20), "visible": true},
	])
	var got := AimAssist.adjust(Vector2.RIGHT, Vector2.ZERO, c, 32.0, 230.0)
	check(got.is_equal_approx(Vector2(60, 5).normalized()), "the smallest angle wins (got %s)" % got)
	# Same angle: the nearer target wins.
	var tie := _cands([{"pos": Vector2(200, 20), "visible": true}, {"pos": Vector2(100, 10), "visible": true}])
	var t := AimAssist.adjust(Vector2.RIGHT, Vector2.ZERO, tie, 32.0, 230.0)
	check(t.is_equal_approx(Vector2(100, 10).normalized()), "a tie goes to the nearest")


func test_aim_respects_cone_and_range() -> void:
	var cfg := Settings.config()
	var light := AimAssist.cone_and_range(1, cfg)
	var strong := AimAssist.cone_and_range(2, cfg)
	check(light == Vector2(cfg.aim_cone_deg[1], cfg.aim_range_px[1]) and strong.x > light.x, "cone/range come from AccessibilityConfig")
	# 20 degrees off the aim: outside Light's 14, inside Strong's 32.
	var p := Vector2.RIGHT.rotated(deg_to_rad(20.0)) * 120.0
	var c := _cands([{"pos": p, "visible": true}])
	check(AimAssist.adjust(Vector2.RIGHT, Vector2.ZERO, c, light.x, light.y) == Vector2.RIGHT, "outside the Light cone")
	check(AimAssist.adjust(Vector2.RIGHT, Vector2.ZERO, c, strong.x, strong.y).is_equal_approx(p.normalized()), "inside the Strong cone")
	var far := _cands([{"pos": Vector2(light.y + 20.0, 0), "visible": true}])
	check(AimAssist.adjust(Vector2(1, -0.05).normalized(), Vector2.ZERO, far, light.x, light.y) == Vector2(1, -0.05).normalized(), "out of range: unchanged")
	var hidden := _cands([{"pos": Vector2(100, 5), "visible": false}])
	check(AimAssist.adjust(Vector2.RIGHT, Vector2.ZERO, hidden, 32.0, 230.0) == Vector2.RIGHT, "a hidden target is ignored")


func test_aim_blocked_by_wall() -> void:
	await _spawn_player()
	var e := _enemy("res://enemies/variants/ScoutDrone.tscn", Vector2(220, 190))
	await physics_frames(3)
	var from := player.global_position + Vector2(0, -12)
	var open := AimAssist.candidates_for(player, from, 230.0, false)
	check(open.size() == 1 and bool(open[0]["visible"]), "clear line: visible (%s)" % [open])
	_floor(Vector2(160, 100), Vector2(16, 100))
	await physics_frames(3)
	var blocked := AimAssist.candidates_for(player, from, 230.0, false)
	check(blocked.size() == 1 and not bool(blocked[0]["visible"]), "a WORLD wall blocks the line of sight (%s)" % [blocked])
	Settings.aim_assist = 2
	var aim := player.combat.assisted_aim(Vector2.RIGHT, from)
	check(aim == Vector2.RIGHT, "no bend toward a target behind a wall (got %s)" % aim)
	e.queue_free()


func test_aim_ignores_dead() -> void:
	await _spawn_player()
	var e := _enemy("res://enemies/variants/ScoutDrone.tscn", Vector2(220, 180))
	await physics_frames(3)
	var from := player.global_position + Vector2(0, -12)
	Settings.aim_assist = 2
	var live := player.combat.assisted_aim(Vector2.RIGHT, from)
	check(not live.is_equal_approx(Vector2.RIGHT), "a live target in the cone bends the shot")
	e.ai = Enemy.AI.DEAD
	check(AimAssist.candidates_for(player, from, 230.0, false).is_empty(), "the dead are not candidates")
	check(player.combat.assisted_aim(Vector2.RIGHT, from) == Vector2.RIGHT, "no bend toward the dead")


# --- Damage (D4 §8.2) ------------------------------------------------------------

func _hits(n: int, source := "hazard", from_boss := false) -> Array[int]:
	var lost: Array[int] = []
	for i in n:
		var before := player.combat.health
		player.combat.take_damage(1, Vector2.ZERO, 0.0, false, source, false, from_boss)
		lost.append(before - player.combat.health)
	return lost


func test_damage_carry_sequence_half() -> void:
	await _spawn_player()
	Settings.damage_assist = 2
	var lost := _hits(4)
	check(lost == [0, 1, 0, 1], "All reduced (0.5): 0, 1, 0, 1 (got %s)" % [lost])


func test_damage_quarter() -> void:
	await _spawn_player()
	Settings.damage_assist = 3
	var lost := _hits(4)
	check(lost == [0, 0, 0, 1], "All greatly reduced (0.25): 0, 0, 0, 1 (got %s)" % [lost])
	check_near(player.combat.damage_carry, 0.0, 0.001, "the carry empties on the whole pip")


func test_bosses_only_scope() -> void:
	await _spawn_player()
	Settings.damage_assist = 1
	var boss := _enemy("res://bosses/CollectorDrone.tscn", Vector2(300, 190))
	var scout := _enemy("res://enemies/variants/ScoutDrone.tscn", Vector2(-100, 190))
	await physics_frames(2)
	var attack := AttackData.new()
	attack.damage = 1.0
	var lost_scout: Array[int] = []
	var lost_boss: Array[int] = []
	for i in 2:
		player.combat.hurt_invuln_timer = 0.0
		var hp := player.combat.health
		player.combat.receive_hit(HitInfo.create(scout, attack, Vector2.ZERO, Vector2.RIGHT))
		lost_scout.append(hp - player.combat.health)
	player.combat.health = player.combat.config.max_health
	for i in 2:
		player.combat.hurt_invuln_timer = 0.0
		var hp := player.combat.health
		player.combat.receive_hit(HitInfo.create(boss, attack, Vector2.ZERO, Vector2.RIGHT))
		lost_boss.append(hp - player.combat.health)
	var per_hit := int(ceil(attack.damage))
	check(lost_scout == [per_hit, per_hit], "Bosses: reduced leaves a scout's hits whole (got %s)" % [lost_scout])
	check(lost_boss[0] + lost_boss[1] < per_hit * 2, "a boss's hits are reduced (got %s)" % [lost_boss])


func test_burnout_exempt() -> void:
	await _spawn_player()
	Settings.damage_assist = 3
	check(_hits(2, "burnout") == [1, 1], "burnout is never scaled (the Core setting covers it)")


func test_nonlethal_still_clamps() -> void:
	await _spawn_player()
	Settings.damage_assist = 2
	player.combat.health = 1
	player.combat.damage_carry = 0.5
	player.combat.take_damage(1, Vector2.ZERO, 0.0, false, "chase", true)
	check(player.combat.health == 1 and not player.combat.dead, "a teaching set piece still never kills (hp %d)" % player.combat.health)


func test_zero_pip_hit_still_hurts_and_emits() -> void:
	await _spawn_player()
	Settings.damage_assist = 2
	EventBus.player_damaged.connect(_on_damaged)
	var hp := player.combat.health
	var result := player.combat.take_damage(1, Vector2(-60, -80), 0.05, true, "hazard")
	EventBus.player_damaged.disconnect(_on_damaged)
	check(player.combat.health == hp, "the first half pip is only buffered")
	check(result == CombatResult.HIT, "still a hit (result %d)" % result)
	check(_damaged.size() == 1 and int(_damaged[0][0]) == 0, "player_damaged(0, ...) still emits: %s" % [_damaged])
	check(player.combat.hurt_invuln_timer > 0.0 and player.current_state_id() == &"hurt", "knockback, i-frames and the hurt state stay")


func test_carry_resets_on_respawn_and_rest() -> void:
	await _spawn_player()
	player.combat.damage_carry = 0.5
	EventBus.player_respawned.emit(player, &"start")
	check(player.combat.damage_carry == 0.0, "a respawn empties the carry")
	player.combat.damage_carry = 0.5
	EventBus.anchor_rested.emit(null)
	check(player.combat.damage_carry == 0.0, "a rest empties the carry")


# --- Reactor (D4 §8.3) --------------------------------------------------------------

func _burn(seconds: float) -> int:
	var reactor := player.reactor
	reactor.config = reactor.config.duplicate()
	reactor.enter_flow()
	var hp := player.combat.health
	for i in int(seconds * 60.0):
		reactor.charge = 0.0
		await physics_frames(1)
	reactor.exit_flow()
	return hp - player.combat.health


func test_burnout_off_no_health_loss_sfx_kept() -> void:
	await _spawn_player()
	Settings.burnout_hurts = false
	AudioManager._last_played.erase(&"burnout")
	var lost := await _burn(player.reactor.config.burnout_interval * 2.5)
	check(lost == 0, "burnout off: no health lost (lost %d)" % lost)
	check(AudioManager._last_played.has(&"burnout"), "the burnout sfx still plays (the Core still teaches its rule)")
	check(not ReactorCore.burnout_enabled(), "burnout_enabled follows the setting")


func test_challenge_kit_forces_burnout() -> void:
	await _spawn_player()
	Settings.burnout_hurts = false
	Challenges.force_reactor_mode = 0
	check(ReactorCore.burnout_enabled(), "a kit that forces a Core mode always burns")
	var lost := await _burn(player.reactor.config.burnout_interval * 1.5)
	check(lost >= 1, "the Pulse Pit rule: burnout hurts in a forced-Core run (lost %d)" % lost)
	Challenges.force_reactor_mode = -1


# --- Checkpoints (D4 §8.5) -------------------------------------------------------------

func test_generous_respawn_room_entry() -> void:
	Game.rest_at_anchor(BROKEN_LIFT, "a1")
	Game.note_room_entry(MARKET, &"from_alley")
	Settings.generous_checkpoints = true
	check(Game.respawn_room() == MARKET and Game.respawn_entry() == &"from_alley",
		"generous: the session's last entry (%s/%s)" % [Game.respawn_room(), Game.respawn_entry()])
	Challenges.force_active = true
	check(Game.respawn_room() == BROKEN_LIFT, "a challenge run owns deaths: the normal chain")
	Challenges.force_active = false


func test_generous_off_uses_anchor() -> void:
	Game.rest_at_anchor(BROKEN_LIFT, "a1")
	Game.note_room_entry(MARKET, &"from_alley")
	Settings.generous_checkpoints = false
	check(Game.respawn_room() == BROKEN_LIFT and Game.respawn_entry() == &"a1", "off: the Anchor")


func test_respawn_policy_never() -> void:
	check(WorldMapIndex.respawn_policy(RAINLINE_CHASE) == 1, "a room with a ChaseDirector never respawns at its entry")
	check(WorldMapIndex.respawn_policy(MARKET) == 0, "an ordinary room allows it")
	check(WorldMapIndex.respawn_policy("res://no/such/room.tscn") == 1, "an unknown path never becomes a respawn point")


func test_chase_room_policy_never() -> void:
	Game.rest_at_anchor(BROKEN_LIFT, "a1")
	Game.note_room_entry(RAINLINE_CHASE, &"from_bell")
	Settings.generous_checkpoints = true
	check(Game.respawn_room() == BROKEN_LIFT, "the chase room falls back to the Anchor (got %s)" % Game.respawn_room())


## D-063: the saved pre-Anchor entry still stops moving once an Anchor is
## set; only the session entry follows every door.
func test_d063_unchanged() -> void:
	Game.note_room_entry(ALLEY, &"from_relay")
	check(Game.state.last_entry_room == ALLEY and Game._session_entry_room == ALLEY, "before any rest both follow the door")
	Game.rest_at_anchor(BROKEN_LIFT, "a1")
	Game.note_room_entry(MARKET, &"from_alley")
	check(Game.state.last_entry_room == ALLEY, "the saved pre-Anchor entry is untouched after a rest")
	check(Game._session_entry_room == MARKET, "the session entry still follows")
	Settings.generous_checkpoints = false
	check(Game.respawn_room() == BROKEN_LIFT, "generous off: Anchor first, as in M8")


## After a real Save & Quit to the title and Continue, the respawn is the
## Anchor again: the session entry is never saved.
func test_continue_ignores_session_entry() -> void:
	Settings.generous_checkpoints = true
	var main: Node = (load("res://Main.tscn") as PackedScene).instantiate()
	main.set("start_room", BROKEN_LIFT)
	add_child(main)
	_extras.append(main)
	await physics_frames(5)
	var host := main.get_node("Menus") as MenuHost
	var anchors: Array = WorldMapIndex.room_info(BROKEN_LIFT)["anchors"]
	check(not anchors.is_empty(), "BrokenLift has an Anchor")
	var anchor_id: String = anchors[0]["id"] if not anchors.is_empty() else "a1"
	Game.rest_at_anchor(BROKEN_LIFT, anchor_id)
	SceneRouter.transition_to(COLLECTOR_BAY, &"from_lift")
	await _wait_idle()
	check(SceneRouter.current_room_path == COLLECTOR_BAY, "walked into the Collector Bay")
	check(Game.respawn_room() == COLLECTOR_BAY, "generous: this session respawns at the bay's entry")
	check(host.open(&"pause"), "pause opens")
	(host.screen(&"pause") as PauseMenu)._quit()
	await _wait_idle()
	var title := host.get_node("TitleMenu") as MenuScreen
	check(title.is_open(), "back at the title")
	title.call("_continue")
	await _wait_idle()
	check(Game._session_entry_room == BROKEN_LIFT, "the session starts over at the Continue room")
	check(SceneRouter.current_room_path == BROKEN_LIFT, "Continue starts at the Anchor (in %s)" % SceneRouter.current_room_path)


func _wait_idle(max_frames := 240) -> void:
	await get_tree().process_frame
	for i in max_frames:
		if not SceneRouter.transitioning:
			break
		await get_tree().process_frame
	await physics_frames(3)


# --- Jump (D4 §8.4) --------------------------------------------------------------

## Peak height of a jump: held for the whole arc, or tapped (released after 2 frames).
func _jump_peak(hold: bool, mode: int) -> float:
	Settings.jump_hold_mode = mode
	player.respawn(Vector2(100, 198))
	await physics_frames(5)
	var floor_y := player.global_position.y
	input.press_jump()
	var min_y := floor_y
	for i in 70:
		await physics_frames(1)
		if i == 1 and not hold:
			input.release_jump()
		min_y = minf(min_y, player.global_position.y)
	input.release_jump()
	return floor_y - min_y


func test_auto_full_jump_matches_held_height() -> void:
	await _spawn_player()
	var held := await _jump_peak(true, 0)
	var tap := await _jump_peak(false, 0)
	var latched := await _jump_peak(false, 1)
	check(tap < held * 0.6, "a tap is a short hop in Hold mode (tap %.1f, held %.1f)" % [tap, held])
	check_near(latched, held, 0.5, "Always full height: a tap reaches the held height")
