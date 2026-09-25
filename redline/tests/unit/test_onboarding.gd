extends RedlineTestCase
## M7 onboarding (M1): the campaign New Game (unarmed, Core readout hidden),
## weapon pickups, pre-Anchor respawn and EntryCheckpoint, the title-screen
## entries and their playtest sessions, and the unlock-all dev profile.
## Fixtures: tools/roomgen/fixtures_onboarding.py.

const ROOM_A := "res://tests/fixtures/onboarding_a.tscn"
const ROOM_B := "res://tests/fixtures/onboarding_b.tscn"
const BAD_CHECKPOINT := "res://tests/fixtures/onboarding_badcheckpoint.tscn"
const RELAY := "res://world/rooms/lowlight/Relay.tscn"
const TEST_SAVE_DIR := "user://test_onboarding_saves"
const TEST_PLAYTEST_DIR := "user://test_onboarding_playtests"

var root: Node2D
var banners: Array[String] = []
var _saved_recording: bool
var _saved_variant: String


func before_each() -> void:
	_saved_recording = Settings.playtest_recording
	_saved_variant = Settings.playtest_variant
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	SaveManager.save_dir = TEST_SAVE_DIR
	Game.onboarding = Game.ONBOARDING
	Game.new_game()
	banners.clear()
	EventBus.hint_requested.connect(_on_hint)


func after_each() -> void:
	EventBus.hint_requested.disconnect(_on_hint)
	Playtest.end_session("test_done")
	Playtest.allow_headless = false
	Playtest.dir = Playtest.DIR
	Settings.playtest_recording = _saved_recording
	Settings.playtest_variant = _saved_variant
	for dir in [TEST_PLAYTEST_DIR, TEST_SAVE_DIR]:
		if DirAccess.dir_exists_absolute(dir):
			for f in DirAccess.get_files_at(dir):
				DirAccess.remove_absolute("%s/%s" % [dir, f])
	SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR
	SceneRouter.current_room = null
	SceneRouter.world_root = null
	root.queue_free()
	Game.onboarding = Game.ONBOARDING
	Game.new_game()
	await physics_frames(2)


func _on_hint(text: String, _seconds: float) -> void:
	banners.append(text)


## The shipped config with the campaign switched on and fixture A as the start.
func _campaign_config() -> OnboardingConfig:
	var c := (Game.ONBOARDING as OnboardingConfig).duplicate() as OnboardingConfig
	c.enforce = true
	c.campaign_start_room = ROOM_A
	c.campaign_start_entry = &"start"
	return c


func _start_campaign() -> void:
	Game.onboarding = _campaign_config()
	Game.start_campaign()


func _enter(path: String, entry: StringName) -> Room:
	SceneRouter.goto_room(path, entry)
	await physics_frames(3)
	return SceneRouter.current_room as Room


func _input_of(p: Player) -> ScriptedInputSource:
	if not p.input_source is ScriptedInputSource:
		p.input_source = ScriptedInputSource.new()
	return p.input_source as ScriptedInputSource


func _wait_room_change(from: Node, frames := 240) -> bool:
	for i in frames:
		await physics_frames(1)
		if SceneRouter.current_room != from and is_instance_valid(SceneRouter.current_room) and not SceneRouter.transitioning:
			await physics_frames(2)
			return true
	return false


func _room() -> Room:
	return SceneRouter.current_room as Room


func _needle(room: Room) -> Enemy:
	return room.find_child("Needle1", true, false) as Enemy


func _hud() -> CanvasLayer:
	var hud: CanvasLayer = load("res://ui/hud/CombatHud.gd").new()
	add_child(hud)
	return hud


func _core_visible(hud: Node) -> bool:
	return bool(hud.call("core_bar_visible"))


func _title() -> MenuScreen:
	var title: MenuScreen = load("res://ui/menus/TitleMenu.gd").new()
	add_child(title)
	title.open_menu()
	return title


func _record() -> void:
	Settings.playtest_recording = true
	Settings.playtest_variant = "baseline"
	Playtest.dir = TEST_PLAYTEST_DIR
	Playtest.allow_headless = true


## The first room_enter after session_start, or {}.
func _first_room_enter() -> Dictionary:
	if Playtest.session == null:
		return {}
	var started := false
	for e: Dictionary in Playtest.session.data["events"]:
		if e["type"] == "session_start":
			started = true
		elif started and e["type"] == "room_enter":
			return e
	return {}


# --- Campaign start ------------------------------------------------------------------

## Hints queue (bible §42): a second hint waits until the first has been up
## HINT_MIN_SECONDS instead of replacing it at once (Security Station's
## calibration line, the Maintenance Shaft's dodge line). Duplicates are not
## queued twice.
func test_hud_hints_queue_with_a_minimum_hold() -> void:
	var hud := _hud()
	hud.call("request_hint", "first", 3.5)
	hud.call("request_hint", "second", 3.5)
	hud.call("request_hint", "second", 3.5)
	check(hud.call("current_hint") == "first", "the first hint shows first")
	await physics_frames(60)
	check(hud.call("current_hint") == "first", "the first hint holds for at least 2 s (%s)" % hud.call("current_hint"))
	await physics_frames(70)
	check(hud.call("current_hint") == "second", "the second hint follows after the hold (%s)" % hud.call("current_hint"))
	await physics_frames(230)
	check(hud.call("current_hint") == "", "the duplicate was not queued (%s)" % hud.call("current_hint"))
	hud.queue_free()


func test_start_campaign_state() -> void:
	_start_campaign()
	var st := Game.state
	check(st.owned_weapons.is_empty(), "campaign should own no weapons (got %s)" % [st.owned_weapons])
	check(st.melee_weapon == "" and st.ranged_weapon == "", "campaign slots should be empty")
	check(Game.has_flag("core_hud_hidden"), "campaign should hide the Core readout")
	check(Game.campaign_start_room() == ROOM_A and Game.campaign_start_entry() == &"start", "campaign start room/entry")


## The shipped config is the campaign (D6); a config with enforce off is the
## legacy slice start, and start_campaign() is then plain new_game().
func test_shipped_config_starts_in_wake() -> void:
	var shipped := Game.ONBOARDING as OnboardingConfig
	check(shipped.enforce, "the shipped config enforces the campaign start")
	check(shipped.campaign_start_room == "res://world/rooms/undercity/Wake.tscn" and shipped.campaign_start_entry == &"start", "the campaign starts in Wake at 'start'")
	check(shipped.title_subtitle == "Act I  —  Undercity to Lowlight", "subtitle: %s" % shipped.title_subtitle)
	check(shipped.start_owned_weapons.is_empty() and bool(shipped.start_flags.get("core_hud_hidden", false)), "unarmed, Core readout hidden")


func test_start_campaign_noop_when_not_enforced() -> void:
	var off := (Game.ONBOARDING as OnboardingConfig).duplicate() as OnboardingConfig
	off.enforce = false
	Game.onboarding = off
	Game.state.scrap_banked = 77
	Game.start_campaign()
	check(Game.state.to_dict() == GameState.new().to_dict(), "start_campaign without enforce must equal new_game()")
	check(Game.campaign_start_room() == Game.START_ROOM and Game.campaign_start_entry() == Game.START_ENTRY, "legacy start is the Relay")


func test_new_game_unchanged_for_legacy() -> void:
	Game.new_game()
	var st := Game.state
	check(st.owned_weapons.has(GameState.DEFAULT_MELEE) and st.owned_weapons.has(GameState.DEFAULT_RANGED), "legacy owns the full kit")
	check(st.melee_weapon == GameState.DEFAULT_MELEE and st.ranged_weapon == GameState.DEFAULT_RANGED, "legacy slots equipped")
	check(not Game.has_flag("core_hud_hidden"), "legacy shows the Core")
	var room := await _enter(ROOM_A, &"start")
	check(room.player.combat.melee_weapon != null and room.player.combat.ranged_weapon() != null, "legacy player is armed")


func test_config_validates() -> void:
	var errors := (Game.ONBOARDING as OnboardingConfig).validate()
	check(errors.is_empty(), "shipped onboarding config invalid: %s" % ", ".join(errors))
	var bad := _campaign_config()
	bad.campaign_start_room = "res://nope/Nowhere.tscn"
	bad.start_owned_weapons = PackedStringArray(["no_such_weapon"])
	check(bad.validate().size() == 2, "missing room and unknown weapon should both be errors: %s" % [bad.validate()])
	var typo := _campaign_config()
	typo.campaign_start_entry = &"strat"
	check(typo.validate().size() == 1, "a start entry that is not a spawn in the room should be an error: %s" % [typo.validate()])


# --- Unarmed start and pickups -----------------------------------------------------

func test_attack_does_nothing_unarmed() -> void:
	_start_campaign()
	var room := await _enter(ROOM_A, &"start")
	var p := room.player
	check(p.combat.melee_weapon == null and p.combat.ranged_weapon() == null, "unarmed player has a weapon")
	# Stand next to the dormant Needle (skipping the rack) and swing.
	p.teleport(Vector2(245, -2))
	p.facing = 1
	await physics_frames(3)
	var needle := _needle(room)
	var states: Array[StringName] = []
	p.state_machine.state_changed.connect(func(_from: StringName, to: StringName) -> void: states.append(to))
	var input := _input_of(p)
	input.press_light()
	await physics_frames(20)
	input.press_heavy()
	await physics_frames(20)
	input.press_ranged()
	await physics_frames(20)
	check(not states.has(&"melee"), "unarmed attack entered the melee state (%s)" % [states])
	check(needle.health == needle.data.max_health, "unarmed attack damaged the Needle")


func test_rack_equips_blade_and_hits() -> void:
	_start_campaign()
	var room := await _enter(ROOM_A, &"start")
	var p := room.player
	var input := _input_of(p)
	input.move_x = 1
	for i in 120:
		await physics_frames(1)
		if p.global_position.x > 190.0:
			break
	input.move_x = 0
	await physics_frames(20)
	check(p.combat.melee_weapon != null and String(p.combat.melee_weapon.id) == "pulse_blade", "rack did not equip the blade on the live player")
	check(Game.state.melee_weapon == "pulse_blade", "blade not equipped in the profile")
	check(Game.has_flag("got_pulse_blade"), "got_pulse_blade not set")
	var acquired := banners.filter(func(t: String) -> bool: return t.begins_with("WEAPON ACQUIRED"))
	check(acquired.size() == 1, "expected one WEAPON ACQUIRED banner, got %s" % [banners])
	check(room.find_child("Pickup_pulse_blade", true, false) == null or (room.find_child("Pickup_pulse_blade", true, false) as Node).is_queued_for_deletion(), "rack pickup should be gone")
	var needle := _needle(room)
	p.teleport(Vector2(245, -2))
	p.facing = 1
	await physics_frames(3)
	input.press_light()
	await physics_frames(25)
	check(needle.health < needle.data.max_health, "blade swing did not damage the Needle")


func test_pistol_drop_equips_ranged_slot() -> void:
	_start_campaign()
	Game.grant_weapon("pulse_blade")
	var room := await _enter(ROOM_B, &"from_a")
	var p := room.player
	p.teleport(Vector2(700, -2))
	await physics_frames(2)
	var input := _input_of(p)
	input.move_x = 1
	for i in 90:
		await physics_frames(1)
		if p.global_position.x > 780.0:
			break
	input.move_x = 0
	await physics_frames(2)
	check(Game.has_flag("got_service_pistol"), "got_service_pistol not set")
	check(Game.state.ranged_weapon == "service_pistol", "pistol not equipped in the profile")
	var w := p.combat.ranged_weapon()
	check(w != null and String(w.id) == "service_pistol", "pistol not equipped on the live player")
	check(Game.state.melee_weapon == "pulse_blade", "pistol must not touch the melee slot")


func test_pickup_absent_when_owned_or_flagged() -> void:
	# Legacy profile owns the blade: the rack frees itself.
	var room := await _enter(ROOM_A, &"start")
	check(room.find_child("Pickup_pulse_blade", true, false) == null, "rack should be gone when the blade is owned")
	# Campaign with the flag already set (a respawned boss reward).
	_start_campaign()
	Game.set_flag("got_service_pistol")
	room = await _enter(ROOM_B, &"from_a")
	check(room.find_child("Pickup_service_pistol", true, false) == null, "drop should be gone when its flag is set")
	# Campaign, nothing taken: both present.
	_start_campaign()
	room = await _enter(ROOM_A, &"start")
	check(room.find_child("Pickup_pulse_blade", true, false) != null, "rack should be present in a fresh campaign")
	room = await _enter(ROOM_B, &"from_a")
	check(room.find_child("Pickup_service_pistol", true, false) != null, "drop should be present in a fresh campaign")


func test_weapon_pickup_content_flags_without_ready() -> void:
	var rack := (load("res://interactables/PulseBladeRack.tscn") as PackedScene).instantiate() as WeaponPickup
	check(rack.content_flags().get("produces", []) == ["got_pulse_blade"], "rack flags: %s" % [rack.content_flags()])
	check(rack.content_errors(null).is_empty(), "rack names a real weapon")
	rack.free()
	var drop := (load("res://interactables/ServicePistolDrop.tscn") as PackedScene).instantiate() as WeaponPickup
	check(drop.size == Vector2(24, 150), "pistol drop trigger must be 24x150 (cannot be jumped over from the catwalk)")
	check(drop.content_flags().get("produces", []) == ["got_service_pistol"], "drop flags: %s" % [drop.content_flags()])
	drop.free()
	var raw := WeaponPickup.new()
	raw.weapon_id = "no_such_weapon"
	check(raw.effective_flag() == "got_no_such_weapon", "empty flag_id should default to got_<weapon>")
	check(raw.content_errors(null).size() == 1, "unknown weapon should be a content error")
	raw.free()


# --- Hidden Core HUD ------------------------------------------------------------------

func test_core_hud_hidden_until_flag_cleared() -> void:
	var hud: CanvasLayer = _hud()
	check(_core_visible(hud), "legacy profile shows the Core bar")
	_start_campaign()
	check(not _core_visible(hud), "campaign hides the Core bar")
	Game.set_flag("core_hud_hidden", false)
	check(_core_visible(hud), "clearing the flag shows the Core bar")
	check(float(hud.get("_core_reveal")) > 0.0 and float(hud.get("_core_online")) > 0.0, "first reveal should fill in and say CORE ONLINE")
	await physics_frames(150)
	check(float(hud.get("_core_online")) == 0.0, "CORE ONLINE should fade after its time")
	Game.new_game()
	check(_core_visible(hud), "a new legacy game shows the Core bar")
	hud.queue_free()


# --- Pre-Anchor respawn ------------------------------------------------------------------

func test_pre_anchor_respawn() -> void:
	_start_campaign()
	var a := await _enter(ROOM_A, &"start")
	check(Game.state.last_entry_room == ROOM_A and Game.state.last_entry_id == "start", "room entry not noted")
	a.player.teleport(Vector2(990, -2))
	_input_of(a.player).move_x = 1
	check(await _wait_room_change(a), "exit to B did not fire")
	var b := _room()
	check(SceneRouter.current_room_path == ROOM_B, "not in B")
	check(Game.state.last_entry_room == ROOM_B and Game.state.last_entry_id == "from_a", "B entry not noted")
	b.player.combat.take_damage(99, Vector2.ZERO, 0.0, true)
	check(await _wait_room_change(b), "death did not reload a room")
	var r := _room()
	check(SceneRouter.current_room_path == ROOM_B, "pre-Anchor death should return to B, not %s" % SceneRouter.current_room_path)
	check(absf(r.player.global_position.x - 40.0) < 24.0, "pre-Anchor respawn not at from_a (x=%.1f)" % r.player.global_position.x)
	check(r.player.combat.health == r.player.combat.config.max_health, "respawn not at full health")
	# Rest: the Anchor wins from now on.
	Game.rest_at_anchor(ROOM_B, "ob_anchor")
	r.player.combat.take_damage(99, Vector2.ZERO, 0.0, true)
	check(await _wait_room_change(r), "second death did not reload a room")
	check(absf(_room().player.global_position.x - 950.0) < 24.0, "death after resting should return to the Anchor (x=%.1f)" % _room().player.global_position.x)


func test_continue_uses_last_entry() -> void:
	Game.note_room_entry(ROOM_B, &"ob_mid")
	check(Game.save_game() == OK, "save failed")
	Game.new_game()
	check(Game.load_game(), "load failed")
	check(Game.state.last_entry_room == ROOM_B and Game.state.last_entry_id == "ob_mid", "last_entry_* lost in the save roundtrip")
	check(Game.respawn_room() == ROOM_B and Game.respawn_entry() == &"ob_mid", "Continue should use the last entry before any Anchor")
	# Anchors always win, and a later entry no longer moves the respawn point.
	Game.state.last_anchor_room = RELAY
	Game.state.last_anchor_id = "start"
	Game.note_room_entry(ROOM_A, &"start")
	check(Game.state.last_entry_room == ROOM_B, "note_room_entry must be ignored once an Anchor is set")
	check(Game.respawn_room() == RELAY, "the Anchor should win")


func test_from_dict_defaults_last_entry() -> void:
	var empty := GameState.from_dict({})
	check(empty.last_entry_room == "" and empty.last_entry_id == "", "from_dict({}) should default last_entry_*")
	var v3 := GameState.new().to_dict()
	v3.erase("last_entry_room")
	v3.erase("last_entry_id")
	v3["schema_version"] = 3
	var old := GameState.from_dict(v3)
	check(old.last_entry_room == "" and old.last_entry_id == "", "a v3 save without the keys should default them")
	check(SaveManager.CURRENT_SCHEMA_VERSION == 3, "no schema bump for optional keys (D-087)")
	Game.state = old
	check(Game.respawn_room() == Game.START_ROOM and Game.respawn_entry() == Game.START_ENTRY, "old saves fall back to the slice start")


func test_entry_checkpoint_sets_respawn() -> void:
	_start_campaign()
	var b := await _enter(ROOM_B, &"from_a")
	var p := b.player
	p.teleport(Vector2(550, -2))
	await physics_frames(2)
	var input := _input_of(p)
	input.move_x = 1
	for i in 60:
		await physics_frames(1)
		if p.global_position.x > 620.0:
			break
	input.move_x = 0
	check(Game.state.last_entry_room == ROOM_B and Game.state.last_entry_id == "ob_mid", "checkpoint did not move the respawn (%s)" % Game.state.last_entry_id)
	p.combat.take_damage(99, Vector2.ZERO, 0.0, true)
	check(await _wait_room_change(b), "death did not reload a room")
	var r := _room()
	check(absf(r.player.global_position.x - 600.0) < 24.0, "respawn not at ob_mid (x=%.1f)" % r.player.global_position.x)
	# After resting, the checkpoint changes nothing.
	Game.rest_at_anchor(ROOM_B, "ob_anchor")
	var before := [Game.state.last_entry_room, Game.state.last_entry_id, Game.state.last_anchor_id]
	Game.note_room_entry(ROOM_B, &"from_a")  # would move it if the Anchor did not win
	r.player.teleport(Vector2(550, -2))
	await physics_frames(2)
	_input_of(r.player).move_x = 1
	for i in 60:
		await physics_frames(1)
		if r.player.global_position.x > 620.0:
			break
	_input_of(r.player).move_x = 0
	check([Game.state.last_entry_room, Game.state.last_entry_id, Game.state.last_anchor_id] == before, "checkpoint changed state after an Anchor rest")
	r.player.combat.take_damage(99, Vector2.ZERO, 0.0, true)
	check(await _wait_room_change(r), "second death did not reload a room")
	check(absf(_room().player.global_position.x - 950.0) < 24.0, "death after resting should return to the Anchor (x=%.1f)" % _room().player.global_position.x)


func test_entry_checkpoint_validator_needs_spawn() -> void:
	var bad := ContentValidator.new().check_room(BAD_CHECKPOINT, false)
	var want := "room onboarding_badcheckpoint: Respawn_nowhere: EntryCheckpoint names spawn 'nowhere' but no SpawnMarker has it"
	check(bad.errors.has(want), "missing checkpoint error in %s" % [bad.errors])
	var good := ContentValidator.new().check_room(ROOM_B, false)
	check(good.errors.is_empty(), "onboarding_b should validate: %s" % [good.errors])
	check(good.produced.has("got_service_pistol"), "WeaponPickup should produce its flag in the graph")


func test_pistol_drop_collected_from_platform() -> void:
	_start_campaign()
	var b := await _enter(ROOM_B, &"from_a")
	var p := b.player
	p.teleport(Vector2(706, -81))
	await physics_frames(4)
	var lowest := p.global_position.y
	var input := _input_of(p)
	input.move_x = 1
	for i in 60:
		await physics_frames(1)
		lowest = maxf(lowest, p.global_position.y)
		if p.global_position.x > 770.0:
			break
	input.move_x = 0
	check(lowest < -70.0, "Rook left the platform (lowest y %.1f)" % lowest)
	check(Game.has_flag("got_service_pistol"), "pistol drop not collected from the platform")


# --- Title screen and playtest sessions ----------------------------------------------

func test_debug_relay_start_entry_exists_in_debug() -> void:
	var title := _title()
	var labels: Array = title.find_children("*", "Button", true, false).map(func(b: Node) -> String: return (b as Button).text)
	var has_entry := labels.has("Slice (Relay start)")
	check(has_entry == OS.is_debug_build(), "debug relay entry should exist only in debug builds (buttons %s)" % [labels])
	title.queue_free()


func test_subtitle_reads_onboarding_config() -> void:
	var c := _campaign_config()
	c.title_subtitle = "TEST SUBTITLE"
	Game.onboarding = c
	var title := _title()
	var texts: Array = title.find_children("*", "Label", true, false).map(func(l: Node) -> String: return (l as Label).text)
	check(texts.has("TEST SUBTITLE"), "title subtitle should come from the onboarding config (%s)" % [texts])
	check(not texts.has("vertical slice  —  Lowlight"), "literal subtitle still shown")
	title.queue_free()


func test_new_game_opens_playtest_session() -> void:
	_record()
	Game.onboarding = _campaign_config()
	var title := _title()
	title.call("_new_game")
	for i in 60:
		await physics_frames(1)
		if SceneRouter.current_room != null and not SceneRouter.transitioning:
			break
	await physics_frames(3)
	check(Playtest.is_recording(), "New Game should open a playtest session")
	check(Game.state.owned_weapons.is_empty(), "New Game should run the campaign start")
	var e := _first_room_enter()
	check(e.get("room", "") == "onboarding_a" and e.get("entry", "") == "start", "first room_enter should be the campaign start (got %s)" % [e])
	title.queue_free()


func test_debug_slice_entry_opens_session_at_relay() -> void:
	_record()
	Game.onboarding = _campaign_config()
	var title := _title()
	title.call("_new_relay_game")
	for i in 60:
		await physics_frames(1)
		if SceneRouter.current_room != null and not SceneRouter.transitioning:
			break
	await physics_frames(3)
	check(Playtest.is_recording(), "the debug entry should open a playtest session")
	if Playtest.session:
		check(Playtest.session.data["meta"]["kind"] == "new_relay", "meta.kind: %s" % Playtest.session.data["meta"]["kind"])
		var starts := Playtest.session.events_of("session_start")
		check(not starts.is_empty() and starts[0]["kind"] == "new_relay", "session_start kind")
	check(Game.state.owned_weapons.has(GameState.DEFAULT_MELEE), "the slice start keeps the full kit")
	var e := _first_room_enter()
	check(e.get("room", "") == "Relay" and e.get("entry", "") == "start", "first room_enter should be the Relay start (got %s)" % [e])
	title.queue_free()


## D6: the shipped title screen. Pressing New Game opens a "new" playtest
## session whose first room_enter is Wake at 'start', with Rook unarmed and
## the Core readout hidden. The debug slice entry still starts at the Relay
## under its own session kind.
func test_title_new_game_starts_session_in_wake() -> void:
	_record()
	Game.onboarding = Game.ONBOARDING
	var hud := _hud()
	var title := _title()
	var new_game: Array = title.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return (b as Button).text == "New Game")
	check(new_game.size() == 1, "the title should have one New Game button")
	if new_game.size() == 1:
		(new_game[0] as Button).pressed.emit()
	for i in 90:
		await physics_frames(1)
		if SceneRouter.current_room != null and not SceneRouter.transitioning:
			break
	await physics_frames(3)
	check(Playtest.is_recording(), "New Game should open a playtest session")
	if Playtest.session:
		check(Playtest.session.data["meta"]["kind"] == "new", "meta.kind: %s" % Playtest.session.data["meta"]["kind"])
	var e := _first_room_enter()
	check(e.get("room", "") == "Wake" and e.get("entry", "") == "start", "the first room_enter should be Wake at 'start' (got %s)" % [e])
	check(SceneRouter.current_room_path == "res://world/rooms/undercity/Wake.tscn", "New Game should load Wake, not %s" % SceneRouter.current_room_path)
	check(Game.state.owned_weapons.is_empty() and Game.state.melee_weapon == "" and Game.state.ranged_weapon == "", "Rook starts unarmed")
	var room := _room()
	if room:
		check(room.player.combat.melee_weapon == null and room.player.combat.ranged_weapon() == null, "the Wake player holds no weapon")
	check(Game.has_flag("core_hud_hidden") and not _core_visible(hud), "the Core readout starts hidden")
	title.queue_free()
	if not OS.is_debug_build():
		hud.queue_free()
		return
	Playtest.end_session("test_done")
	var debug_title := _title()
	debug_title.call("_new_relay_game")
	for i in 90:
		await physics_frames(1)
		if SceneRouter.current_room != null and not SceneRouter.transitioning and SceneRouter.current_room.name == "Relay":
			break
	await physics_frames(3)
	check(Playtest.is_recording() and Playtest.session.data["meta"]["kind"] == "new_relay", "the debug entry records as new_relay")
	var re := _first_room_enter()
	check(re.get("room", "") == "Relay" and re.get("entry", "") == "start", "the debug entry starts at the Relay (got %s)" % [re])
	check(Game.state.owned_weapons.has(GameState.DEFAULT_MELEE) and _core_visible(hud), "the slice start keeps the full kit and the Core")
	debug_title.queue_free()
	hud.queue_free()


# --- Old saves (D6) --------------------------------------------------------------------

const SAVE_V3 := "res://tests/fixtures/save_v3_slice.json"
const ESCAPE_TUNNEL := "res://world/rooms/undercity/EscapeTunnel.tscn"


## A schema-3 slice save written by the pre-M7 build (commit 0023006: full
## weapon kit, Dash, met_orr, warden_krail_defeated, shortcut_bell_lift,
## rested at the Relay Anchor) still loads and can walk down into the
## Undercity: Continue lands at the Relay, the gallery door leads into the
## Escape Tunnel, Orr's radio plays its legacy call (rule 3) and the walk
## west ends in the Collector Bay, whose arena starts on arrival (intended:
## a veteran gets the new boss). Geometry-only: enemies pacified.
func test_v3_fixture_walks_to_undercity() -> void:
	var raw := FileAccess.get_file_as_string(SAVE_V3)
	check(raw != "", "fixture %s missing" % SAVE_V3)
	# Written by the old build: M1's keys must not appear anywhere.
	check(not raw.contains("last_entry_room") and not raw.contains("last_entry_id"), "the v3 fixture was regenerated by a post-M1 build")
	var parsed: Variant = JSON.parse_string(raw)
	check(parsed is Dictionary and int((parsed as Dictionary).get("schema_version", 0)) == 3, "fixture should be a schema-3 save")
	if not parsed is Dictionary:
		return
	check(not SaveManager.migrate(parsed as Dictionary).is_empty(), "migrate() rejected the v3 fixture")
	# Load it as Continue would: the file as is in the profile slot, then
	# Game.load_game() (SaveManager.migrate + GameState.from_dict + abilities).
	DirAccess.make_dir_recursive_absolute(TEST_SAVE_DIR)
	var file := FileAccess.open(SaveManager.profile_path(1), FileAccess.WRITE)
	file.store_string(raw)
	file.close()
	check(Game.load_game(), "the v3 fixture should load")
	var st := Game.state
	for w in ["pulse_blade", "service_pistol", "scattergun", "split_katars", "heavy_revolver"]:
		check(st.owned_weapons.has(w), "the v3 kit should own %s" % w)
	check(Game.abilities.dash, "the v3 save has Dash")
	for f in ["met_orr", "warden_krail_defeated", "shortcut_bell_lift"]:
		check(Game.has_flag(f), "the v3 save should keep %s" % f)
	check(st.last_entry_room == "" and st.last_entry_id == "", "last_entry_* should default to ''")
	check(Game.respawn_room() == RELAY and Game.respawn_entry() == &"relay", "Continue should respawn at the Relay Anchor (%s / %s)" % [Game.respawn_room(), Game.respawn_entry()])
	# Continue, then test_relay_to_undercity's gallery climb.
	await _enter(Game.respawn_room(), Game.respawn_entry())
	var bot := _v3_bot()
	if not await _v3_run(bot, [["run", 178], ["jump", 178], ["jump", 112], ["jump", 30], ["exit", -1]]):
		return
	check(SceneRouter.current_room_path == ESCAPE_TUNNEL, "the gallery door should lead into the Escape Tunnel, not %s" % SceneRouter.current_room_path)
	check(_room().player.global_position.distance_to(Vector2(1956, -240)) < 40.0, "should arrive at from_relay (at %s)" % _room().player.global_position)
	bot = _v3_bot()
	var heard: Array = []
	var listen := func(d: Resource, _npc: String) -> void: heard.append(String((d as DialogueData).id))
	EventBus.dialogue_requested.connect(listen)
	# The radio's 24 px use area is 1868..1892.
	var ok := await _v3_run(bot, [["run", 1880], ["interact"], ["wait", 5]])
	EventBus.dialogue_requested.disconnect(listen)
	check(heard == ["orr_radio_legacy"], "a legacy save should hear the radio's legacy call (rule 3), got %s" % str(heard))
	# West down the FZ3 steps and along the tunnel floor to the bay door.
	if ok and await _v3_run(bot, [["run", 1000], ["run", -40], ["exit", -1]]):
		check(SceneRouter.current_room_path == "res://world/rooms/undercity/CollectorBay.tscn" and Game.state.last_entry_id == "", "the tunnel's west door leads to the Collector Bay (an Anchor save notes no entry)")
		var arenas := _room().find_children("*", "BossArena", true, false)
		check(arenas.size() == 1 and (arenas[0] as BossArena).started, "arriving at from_tunnel starts the Collector fight")


## Pacifies the current room (no enemy AI, no Core drain) and drives its player.
func _v3_bot() -> RouteBot:
	var room := _room()
	for e in room.find_children("*", "Enemy", true, false):
		if (e as Enemy).ai_enabled:
			(e as Enemy).ai_enabled = false
			(e as Enemy).set_ai(Enemy.AI.IDLE)
	room.player.reactor.config = room.player.reactor.config.duplicate()
	room.player.reactor.config.drain_per_second = 0.0
	return RouteBot.new(get_tree(), room.player)


func _v3_run(bot: RouteBot, steps: Array) -> bool:
	var ok: bool = await bot.run(steps)
	check(ok, "%s: %s" % [_room().name if _room() else "no room", bot.failure])
	return ok


# --- Dev tools ---------------------------------------------------------------------------

func test_unlock_all_equips_and_shows_core() -> void:
	_start_campaign()
	var hud: CanvasLayer = _hud()
	check(not _core_visible(hud), "campaign hides the Core bar")
	var changes: Array = []
	var spy := func(id: String, value: Variant) -> void: changes.append([id, value])
	EventBus.flag_changed.connect(spy)
	DevActions.unlock_all()
	EventBus.flag_changed.disconnect(spy)
	check(changes.has(["core_hud_hidden", false]), "unlock_all should emit flag_changed(core_hud_hidden, false): %s" % [changes])
	check(_core_visible(hud), "Core bar should show in the same frame")
	check(Game.state.flags.has("core_hud_hidden"), "the key must be cleared, never erased")
	check(Game.state.melee_weapon == GameState.DEFAULT_MELEE and Game.state.ranged_weapon == GameState.DEFAULT_RANGED, "empty slots should get the default kit")
	check(Game.state.core_shards >= 5, "unlock_all should give every Core Shard (%d)" % Game.state.core_shards)
	for d in Game.world_map.districts():
		check(Game.has_flag("map_" + d), "unlock_all should grant map_%s" % d)
	hud.queue_free()
