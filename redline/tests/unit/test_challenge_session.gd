extends RedlineTestCase
## The run lifecycle (M9 D2 §3.1-§3.2, D-147, R04.1-R04.4, R04.11, R04.19,
## R04.24): ProfileSandbox swaps the whole state and restores the same
## objects; the profile file never changes during a run; a world start saves
## first; quit returns to the start point (or the title) with the pre-run
## profile; restarts rebuild a fresh kit and never touch the held profile;
## on_finish_flags land on the profile after the restore; Anchors and NPCs are
## off in runs; the result card is never dropped; unlocks never record from
## fabricated states; the swap happens between rooms, never during the fade.

const H := preload("res://tests/fixtures/challenges/ChallengeHarness.gd")

var h: H


func before_each() -> void:
	h = H.new(self, "challenge_session")
	h.setup()


func after_each() -> void:
	await h.teardown()


func _start_trial_from_a(ret: Dictionary = {"room": H.WORLD_A, "entry": &"start"}) -> bool:
	await h.goto(H.WORLD_A, &"start")
	return await h.start(H.fx(H.TRIAL), ret)


func test_begin_swaps_whole_state_and_restore_returns_same_object() -> void:
	var profile := Game.state
	var abilities := Game.abilities
	var st := ProfileSandbox.kit_state(H.fx(H.TRIAL).kit, H.fx(H.TRIAL), profile)
	var ab := ProfileSandbox.kit_abilities(st)
	var resets: Array = []
	h.listen(EventBus.game_state_reset, func() -> void: resets.append(1))
	var sb := ProfileSandbox.begin(st, ab)
	check(Game.state == st and Game.abilities == ab and Game.held_profile == profile, "sandbox in, profile held")
	check(resets.size() == 1, "begin emits game_state_reset")
	Game.state.flags["x"] = true
	sb.restore()
	check(Game.state == profile and Game.abilities == abilities and Game.held_profile == null, "the same objects come back")
	check(not profile.flags.has("x") and resets.size() == 2, "the sandbox's changes stay in the sandbox")
	var silent := ProfileSandbox.begin(st, ab, false)
	check(resets.size() == 2, "a silent begin emits nothing")
	silent.restore(false)
	check(resets.size() == 2 and Game.state == profile, "a silent restore too")


func test_begin_refused_while_held() -> void:
	var profile := Game.state
	var sb := ProfileSandbox.begin(GameState.new(), PlayerAbilities.new(), false)
	var again := ProfileSandbox.begin(GameState.new(), PlayerAbilities.new(), false)
	check(again == null and Game.held_profile == profile, "a second begin is refused; the profile stays held")
	check(not Challenges.start(H.fx(H.TRIAL), {}), "start refused while a profile is held")
	sb.restore(false)
	check(Game.state == profile, "restored")


func test_profile_file_untouched_during_run() -> void:
	check(await _start_trial_from_a(), "run started")
	var path := SaveManager.profile_path(1)
	var before := FileAccess.get_file_as_bytes(path)
	check(not before.is_empty(), "the start saved the profile")
	Game.rest_at_anchor(H.WORLD_A, "start")
	h.drive().move_x = 1
	await physics_frames(20)
	Game.save_game()
	check(FileAccess.get_file_as_bytes(path) == before, "an Anchor rest or save in the sandbox writes the held profile unchanged")
	check(Game.state.last_anchor_id == "start" and Game.held_profile.last_anchor_id == "", "the rest only touched the sandbox")


func test_save_before_start_from_world_room() -> void:
	var r := await h.goto(H.WORLD_A, &"start")
	r.player.combat.health = 2
	check(not FileAccess.file_exists(SaveManager.profile_path(1)), "no save yet")
	check(await h.start(H.fx(H.TRIAL), {"room": H.WORLD_A, "entry": &"start"}), "run started")
	var d := SaveManager.load_profile(1)
	check(int(d.get("health", -9)) == 2, "captured and saved before the swap (%s)" % d.get("health"))


func test_quit_returns_to_room_entry() -> void:
	var profile := Game.state
	check(await _start_trial_from_a({"room": H.WORLD_B, "entry": &"from_other"}), "run started")
	Challenges.quit()
	check(await h.until(func() -> bool: return not Challenges.active() and SceneRouter.current_room_path == H.WORLD_B and not SceneRouter.transitioning), "back in the world")
	var r := h.room()
	check(r and r.spawns[r.active_spawn_index].spawn_id == &"from_other", "at the return entry")
	check(Game.state == profile and Game.held_profile == null, "the profile object is back")
	check(not r.player.cinematic_lock and r.player.input_override == null, "a live, unfrozen player")


func test_quit_from_title_start_emits_quit_to_title() -> void:
	var host := h.make_host()
	var profile := Game.state
	var seen: Array = []
	h.listen(Signal(host, &"quit_to_title"), func() -> void: seen.append([Game.state == profile, Game.held_profile == null]))
	check(await h.start(H.fx(H.TRIAL), {"title": true}), "run started from the title")
	Challenges.quit()
	check(seen == [[true, true]], "quit_to_title once, after the restore (%s)" % [seen])
	check(not Challenges.active(), "run over")


func test_title_start_closes_title() -> void:
	var host := h.make_host(true)
	var title: MenuScreen = host.get("title")
	check(title.visible, "title open")
	check(await h.start(H.fx(H.TRIAL), {"title": true}), "run started")
	check(not title.visible, "the title closed before the run room")


func test_new_game_mid_run_never_restores_into_other_profile() -> void:
	var profile := Game.state
	check(await h.start(H.fx(H.TRIAL), {}), "run started")
	Game.new_game()
	var other := Game.state
	Challenges.quit()
	check(Game.state == other and Game.state != profile, "the new game's state stays")
	check(Game.held_profile == null and not Challenges.active(), "the held profile is let go")


func test_theatre_on_during_run_and_restored() -> void:
	CinematicMode.theatre = false
	check(await h.start(H.fx(H.TRIAL), {}), "run started")
	check(CinematicMode.theatre, "theatre on in the run")
	Challenges.quit()
	check(not CinematicMode.theatre, "restored off")
	CinematicMode.theatre = true
	check(await h.start(H.fx(H.TRIAL), {}), "run started again")
	Challenges.quit()
	check(CinematicMode.theatre, "restored on")
	CinematicMode.theatre = false


func test_room_hints_preset_no_hint_fires() -> void:
	Game.set_ability(&"dash", true)
	var hints: Array = []
	h.listen(EventBus.hint_requested, func(text: String, _s: float) -> void: hints.append(text))
	check(await h.start(H.fx(H.STAGED), {}), "staged run started")
	check(Game.has_flag("hint_fx_stage_tip") and Game.has_flag("hint_first_flow"), "tips preset in the sandbox")
	h.drive().move_x = 1
	await physics_frames(60)
	check(h.player().global_position.x > 130.0, "walked through the tip (%.0f)" % h.player().global_position.x)
	check(not hints.has("A fixture tip."), "no tip fires in a run (%s)" % [hints])
	check(not Game.held_profile.flags.has("hint_fx_stage_tip"), "the profile keeps its own tips")


func test_restart_rebuilds_fresh_sandbox() -> void:
	var profile := Game.state
	check(await _start_trial_from_a(), "run started")
	var states: Array = [Game.state]
	for i in 3:
		Game.set_flag("fx_secret_opened")
		Game.mark_collected("fx_wall")
		Challenges.restart(&"reset")
		check(await h.until(func() -> bool: return Challenges.attempt() == i + 2 and h.room() != null and not states.has(Game.state)), "attempt %d loaded" % (i + 2))
		await physics_frames(1)
		check(not Game.has_flag("fx_secret_opened") and not Game.is_collected("fx_wall"), "attempt %d: a fresh kit state" % (i + 2))
		check(Game.held_profile == profile, "attempt %d: the held profile is the original" % (i + 2))
		states.append(Game.state)
	Challenges.quit()
	await h.until(func() -> bool: return not Challenges.active() and not SceneRouter.transitioning)
	check(Game.state == profile and not profile.flags.has("fx_secret_opened"), "the restore target is the original profile")


func test_on_finish_flags_set_after_restore() -> void:
	Game.set_ability(&"dash", true)
	var profile := Game.state
	check(await h.start(H.fx(H.STAGED), {}), "staged run started")
	Challenges.finish(ChallengeData.Outcome.FINISHED)
	check(not profile.flags.has("fx_depth_reached") and not Game.state.flags.has("fx_depth_reached"), "not set during the run")
	Challenges.quit()
	check(Game.state == profile and profile.flags.get("fx_depth_reached", false), "set on the profile after the restore")
	check(bool(SaveManager.load_profile(1).get("flags", {}).get("fx_depth_reached", false)), "and saved")


func test_on_finish_flags_not_set_without_finish() -> void:
	Game.set_ability(&"dash", true)
	check(await h.start(H.fx(H.STAGED), {}), "staged run started")
	Challenges.quit()
	check(not Game.state.flags.has("fx_depth_reached"), "a quit without a finish earns nothing")


func test_use_profile_loadout_copies_kit_not_progress() -> void:
	var p := Game.state
	p.owned_weapons.assign(["pulse_blade", "service_pistol", "scatter"])
	p.melee_weapon = "pulse_blade"
	p.ranged_weapon = "scatter"
	p.owned_circuits.assign(["a", "b"])
	p.equipped_circuits.assign(["a"])
	p.core_shards = 3
	p.abilities = {"dash": true}
	p.health = 2
	p.injectors = 0
	p.reactor_charge = 5.0
	p.scrap_banked = 50
	p.flags = {"collector_drone_defeated": true}
	p.collected = {"w": true}
	var ch := H.fx(H.STAGED)
	ch.kit.set_flags = PackedStringArray(["fx_kit_flag"])
	var st := ProfileSandbox.kit_state(ch.kit, ch, p)
	check(Array(st.owned_weapons) == ["pulse_blade", "service_pistol", "scatter"] and st.ranged_weapon == "scatter", "weapons copied")
	check(Array(st.owned_circuits) == ["a", "b"] and Array(st.equipped_circuits) == ["a"] and st.core_shards == 3, "circuits and shards copied")
	check(st.abilities == {"dash": true} and ProfileSandbox.kit_abilities(st).dash, "abilities copied")
	check(st.health == -1 and st.injectors == -1 and st.reactor_charge < 0.0 and st.total_scrap() == 0, "full health, injectors and Core; no Scrap")
	check(st.collected.is_empty() and not st.flags.has("collector_drone_defeated") and st.flags.get("fx_kit_flag", false), "no progress, only kit flags (%s)" % [st.flags])
	st.owned_weapons.append("x")
	check(not p.owned_weapons.has("x"), "a copy, not the profile's arrays")


func test_kit_state_fixed_kit_ignores_profile() -> void:
	Game.state.core_shards = 5
	Game.state.flags["collector_drone_defeated"] = true
	var ch := H.fx(H.REMATCH)
	var st := ProfileSandbox.kit_state(ch.kit, ch, Game.state)
	check(Array(st.owned_weapons) == ["pulse_blade"] and st.ranged_weapon == "" and st.core_shards == 0, "the kit's loadout")
	check(st.flags.get("collector_drone_defeated") == false and st.flags.get("got_pulse_blade") == true, "kit flags set and cleared (false, not erased)")
	check(st.flags.get("collector_drone_intro_seen") == true and st.flags.get("hint_first_flow") == true, "rematch skips the long intro and the Flow tip")


func test_anchor_and_npc_disabled_in_run() -> void:
	Game.set_ability(&"dash", true)
	var prompts: Array = []
	h.listen(EventBus.interact_prompt_changed, func(text: String) -> void: prompts.append(text))
	check(await h.start(H.fx(H.STAGED), {}), "staged run started")
	var r := h.room()
	var anchor := r.find_child("Anchor", true, false)
	var npc := r.find_child("NPC_props_npc_x", true, false)
	check(anchor.process_mode == Node.PROCESS_MODE_DISABLED and npc.process_mode == Node.PROCESS_MODE_DISABLED, "Anchor and NPC disabled")
	await physics_frames(3)
	check(r.player.interactor.current == null, "nothing to interact with on the Anchor (%s)" % [r.player.interactor.current])
	check(not prompts.any(func(t: String) -> bool: return t != ""), "no prompt shown (%s)" % [prompts])
	var exit := r.find_child("Exit", true, false) as RoomExit
	check(not exit.monitoring, "doors never carry a run out")


func test_start_from_1hp_world_room_gives_full_kit_health() -> void:
	var r := await h.goto(H.WORLD_A, &"start")
	r.player.combat.health = 1
	r.player.combat.injectors = 0
	check(await h.start(H.fx(H.TRIAL), {"room": H.WORLD_A, "entry": &"start"}), "run started")
	var p := h.player()
	check(p.combat.health == p.combat.config.max_health and p.combat.injectors == p.combat.injector_capacity(), "full kit health (%d)" % p.combat.health)
	check(Game.held_profile.health == 1 and Game.held_profile.injectors == 0, "the profile keeps its pre-run values")


func test_quit_restores_pre_run_profile_health() -> void:
	var r := await h.goto(H.WORLD_A, &"start")
	r.player.combat.health = 1
	r.player.combat.injectors = 0
	r.player.reactor.charge = 7.0
	check(await h.start(H.fx(H.TRIAL), {"room": H.WORLD_A, "entry": &"start"}), "run started")
	h.player().combat.take_damage(1, Vector2.ZERO, 0.0, false, "test")
	Challenges.quit()
	check(await h.until(func() -> bool: return not Challenges.active() and h.room() != null and not SceneRouter.transitioning), "back")
	await physics_frames(1)
	var p := h.player()
	check(Game.state.health == 1 and Game.state.injectors == 0 and is_equal_approx(Game.state.reactor_charge, 7.0), "the profile's pre-run values (%d, %d, %.1f)" % [Game.state.health, Game.state.injectors, Game.state.reactor_charge])
	check(p.combat.health == 1 and p.combat.injectors == 0, "the returning player too (%d)" % p.combat.health)


func test_fast_reset_restores_full_kit_health() -> void:
	check(await _start_trial_from_a(), "run started")
	var held_health := Game.held_profile.health
	var p := h.player()
	var p_id := p.get_instance_id()
	p.combat.take_damage(2, Vector2.ZERO, 0.0, false, "test")
	check(p.combat.health < p.combat.config.max_health, "hurt")
	Challenges.restart(&"reset")
	check(await h.until(func() -> bool: return h.player() != null and h.player().get_instance_id() != p_id), "reloaded")
	var q := h.player()
	check(q.combat.health == q.combat.config.max_health, "a reset gives full kit health (%d)" % q.combat.health)
	check(Game.held_profile.health == held_health, "the profile never saw the hit")


func test_unlock_not_recorded_in_theatre_or_tainted() -> void:
	await h.goto(H.WORLD_A, &"start")
	CinematicMode.theatre = true
	Game.set_flag("collector_drone_defeated")
	check(not Challenges.records.ever_unlocked("fx_trial"), "not in theatre")
	CinematicMode.theatre = false
	Game.set_flag("collector_drone_defeated", false)
	Game.state.dev_tainted = true
	Game.set_flag("collector_drone_defeated")
	check(not Challenges.records.ever_unlocked("fx_trial"), "not on a dev-tainted profile")
	Game.state.dev_tainted = false
	Game.set_flag("collector_drone_defeated", false)
	Challenges.force_active = true
	Game.set_flag("collector_drone_defeated")
	check(not Challenges.records.ever_unlocked("fx_trial"), "not during a run")
	Challenges.force_active = false
	Game.set_flag("collector_drone_defeated", false)
	# A dev flag sandbox (DevActions.satisfy_ending) holds recording while
	# its fabricated flags are live.
	var restore := FlagSandbox.begin()
	ChallengeLibrary.recording_holds += 1
	Game.set_flag("collector_drone_defeated")
	check(not Challenges.records.ever_unlocked("fx_trial"), "not inside a held flag sandbox")
	ChallengeLibrary.recording_holds -= 1
	restore.call()
	check(not Game.has_flag("collector_drone_defeated") and not Challenges.records.ever_unlocked("fx_trial"), "the restore records nothing")
	Game.set_flag("collector_drone_defeated")
	check(Challenges.records.ever_unlocked("fx_trial"), "recorded in real play")


func test_pause_during_finish_delay() -> void:
	var host := await h.boot_main(H.WORLD_A)
	check(await h.start(H.fx(H.TRIAL), {"room": H.WORLD_A, "entry": &"start"}), "run started")
	h.drive().move_x = 1
	await physics_frames(5)
	Challenges.finish(ChallengeData.Outcome.FINISHED)
	check(Challenges.finishing(), "finishing")
	await press_action(&"pause", 2)
	await get_tree().process_frame
	check(not host.pause.is_open(), "no pause menu in the finish beat")
	# R04.22: the card goes through open_when_free; with a screen open it
	# waits in the queue and pause stays refused until it is shown.
	check(host.open(&"settings"), "a blocker opens in the beat")
	var queued := func() -> bool:
		return host._queued.any(func(q: Array) -> bool: return q[0] == &"challenge_result")
	check(await h.until(func() -> bool: return Challenges.phase() == Challenges.Phase.FINISHED, 90), "the card is requested after the delay")
	check(queued.call(), "the card is queued in open_when_free (%s)" % [host._queued])
	check(Challenges.finishing() and not MenuHost.can_open(&"pause", false, false), "pause stays refused while it waits")
	host.settings.close_menu()
	await physics_frames(3)
	check(not queued.call(), "drained once the blocker closed")
	check(not Challenges.finishing(), "the window closes once the card is shown")
	check(MenuHost.can_open(&"pause", false, false), "pause opens again")
	check(h.player().cinematic_lock, "the player stays frozen until the card or a retry")


func test_result_card_waits_for_open_screen() -> void:
	var host := await h.boot_main(H.WORLD_A)
	check(await h.start(H.fx(H.TRIAL), {"room": H.WORLD_A, "entry": &"start"}), "run started")
	h.drive().move_x = 1
	await physics_frames(5)
	Challenges.finish(ChallengeData.Outcome.FINISHED)
	check(host.open(&"settings"), "another screen opens in the finish beat (the blocker)")
	var queued := func() -> bool:
		return host._queued.any(func(q: Array) -> bool: return q[0] == &"challenge_result")
	check(await h.until(queued, 120), "the card waits in the open_when_free queue")
	check(Challenges.finishing(), "still finishing while it waits: pause stays shut")
	var entry: Array = host._queued.filter(func(q: Array) -> bool: return q[0] == &"challenge_result")[0]
	check((entry[1] as Dictionary).get("result", {}).get("challenge") == "fx_trial", "with the SubmitResult as context (%s)" % [entry[1]])
	host.settings.close_menu()
	await physics_frames(3)
	check(not queued.call(), "drained once the blocker closed")
	check(not Challenges.finishing(), "the window is over")


func test_start_swap_happens_between_rooms() -> void:
	var src := await h.goto(H.WORLD_A, &"start")
	var profile := Game.state
	var log: Array = []
	var note := func(what: String) -> void:
		log.append([what, is_instance_valid(src) and src.is_inside_tree(), Game.state == profile])
	h.listen(EventBus.flag_changed, func(_id: String, _v: Variant) -> void: note.call("flag_changed"))
	h.listen(EventBus.arc_stage_entered, func(_n: String, _s: String, _l: bool) -> void: note.call("arc_stage_entered"))
	h.listen(EventBus.game_state_reset, func() -> void: note.call("game_state_reset"))
	h.listen(EventBus.room_leaving, func(_r: Node) -> void: note.call("room_leaving"))
	check(Challenges.start(H.fx(H.TRIAL), {"room": H.WORLD_A, "entry": &"start"}), "start")
	check(Game.state == profile, "the profile is live until the room leaves")
	await h.until(func() -> bool: return Challenges.phase() == Challenges.Phase.RUNNING)
	var in_src: Array = log.filter(func(e: Array) -> bool: return e[1] and e[0] != "room_leaving")
	check(in_src.is_empty(), "nothing fires while the source room is in the tree (%s)" % [log])
	var resets: Array = log.filter(func(e: Array) -> bool: return e[0] == "game_state_reset")
	check(resets.size() == 1 and not resets[0][1], "one reset, after the source room left (%s)" % [log])
	var leaving: Array = log.filter(func(e: Array) -> bool: return e[0] == "room_leaving")
	check(leaving.size() == 1 and not leaving[0][2], "swapped inside room_leaving (Challenges runs first)")


func test_start_fade_does_not_touch_sandbox_or_profile() -> void:
	await h.boot_main(H.WORLD_A)
	var r := h.room()
	var profile := Game.state
	var world_player := r.player
	var saw: Array = []
	check(Challenges.start(H.fx(H.TRIAL), {"room": H.WORLD_A, "entry": &"start"}), "start")
	var t0 := profile.play_time_sec
	var flags0 := profile.flags.duplicate(true)
	var health0 := profile.health
	while Challenges.phase() == Challenges.Phase.STARTING:
		if is_instance_valid(world_player):
			saw.append([world_player.cinematic_lock, world_player.input_override != null, Game.state == profile])
		await get_tree().physics_frame
	check(saw.size() >= 3, "a real fade (%d frames)" % saw.size())
	check(saw.all(func(s: Array) -> bool: return s[0] and s[1] and s[2]), "the world player is frozen and the profile live during the fade (%s)" % [saw])
	check(is_equal_approx(profile.play_time_sec, t0) and profile.flags == flags0 and profile.health == health0, "the fade changed nothing on the profile (%.3f vs %.3f)" % [profile.play_time_sec, t0])
	check(Game.held_profile == profile and Game.state != profile, "the sandbox took over between rooms")


func test_open_from_title_loads_without_playtest() -> void:
	var host := h.make_host()
	var d := GameState.new().to_dict()
	d["flags"] = {"act1_complete": true}
	SaveManager.save_profile(1, d)
	Playtest.end_session("test")
	Challenges.open_from_title()
	check(Game.has_flag("act1_complete"), "the profile is loaded")
	check(Playtest.session == null, "no playtest session begun")
	check(host.get("opened") == [[&"challenges", {"from": "title"}]], "the list opens with the title context (%s)" % [host.get("opened")])
