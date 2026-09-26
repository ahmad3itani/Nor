extends RedlineTestCase
## The shipped Act I challenges (M9 T08, D2 §1-§2.2): every file validates
## and the cross-file rules (ChallengeRules CH-1..CH-15) are clean; kits stay
## equal to the story presets they were copied from; the boss rematches start
## where the dev boss restart does; unlocks follow the profile; the Collector
## rematch replays within 2 frames of its bake and the Krail rematch arms and
## ends on the kill; medals follow D-150 and sit at or above the rig ghost and
## the boss floor; the campaign split list is valid.

const H := preload("res://tests/fixtures/challenges/ChallengeHarness.gd")
const DIR := "res://data/challenges"
const IDS: PackedStringArray = ["br_collector", "br_collector_nohit", "br_krail", "br_krail_nohit", "tt_first_pursuit",
	"tt_escape_tunnel", "tt_neon_roofs", "tt_rainline", "mo_maintenance_shaft", "nh_security_station"]
## kit -> [story preset it was copied from, flags added, documented clears].
## set_flags = preset + added - clears; clear_flags = clears (D2 §2.2).
const KIT_SOURCES := {
	"kit_collector": ["fresh", ["got_pulse_blade"], ["collector_drone_defeated", "got_service_pistol"]],
	"kit_krail": ["charted", [], ["warden_krail_defeated", "unlocked_dash"]],
	"kit_undercity_mid": ["collector_down", ["got_pulse_blade"], ["collector_drone_defeated", "got_service_pistol"]],
	"kit_undercity_late": ["collector_down", ["got_pulse_blade"], []],
	"kit_lowlight": ["grid_rerouted", [], []],
	"kit_lowlight_rainline": ["grid_rerouted", [], ["chase_rainline_done"]],
	"kit_lowlight_scanners": ["grid_rerouted", [], ["lowlight_power_rerouted"]],
}
## Shipped without a rig ghost, with provisional medals (D-140/D-150).
const PROVISIONAL := {"br_krail": [8640, 6120, 4860, 3600], "br_krail_nohit": [8640, 6120, 4860, 3600]}

var h: H


func before_each() -> void:
	h = H.new(self, "challenge_content")
	h.setup()
	ChallengeLibrary.data_dir = ChallengeLibrary.DEFAULT_DIR
	ChallengeLibrary.clear_cache()


func after_each() -> void:
	BuildInfo.set_force_demo(-1)
	await h.teardown()


func _ch(id: String) -> ChallengeData:
	return ChallengeLibrary.by_id(id)


func _all() -> Array[ChallengeData]:
	var out: Array[ChallengeData] = []
	for id in IDS:
		out.append(_ch(id))
	return out


func test_all_challenges_validate_and_rules_clean() -> void:
	var listed := ChallengeLibrary.all().map(func(c: ChallengeData) -> String: return c.id)
	for id in IDS:
		var ch := _ch(id)
		check(ch != null, "%s is listed by ChallengeLibrary" % id)
		if ch == null:
			continue
		check(listed.has(id), "%s is offered in this build" % id)
		check(ch.validate().is_empty(), "%s validates: %s" % [id, ch.validate()])
		check(ch.revision == 1, "%s is revision 1" % id)
		check(ch.score_kind == ChallengeData.ScoreKind.TIME, "%s scores TIME" % id)
		check(ch.description.length() <= 120, "%s description <= 120 chars" % id)
		check(ch.start_room.begins_with("res://") and (ch.finish_exit_target == "" or ch.finish_exit_target.begins_with("res://")),
			"%s writes full res:// paths" % id)
	# The flag graph of the real content, then the cross-file rules.
	var v := ContentValidator.new().run(true)
	var paths: Array[String] = []
	var list: Array[ChallengeData] = []
	for path in DataDir.list(DIR):
		var res := load(path)
		if res is ChallengeData:
			list.append(res)
			paths.append(path)
	var r := ChallengeRules.check_list(list, paths, v)
	check((r["errors"] as PackedStringArray).is_empty(), "ChallengeRules errors: %s" % [r["errors"]])
	check((r["warnings"] as PackedStringArray).is_empty(), "ChallengeRules warnings: %s" % [r["warnings"]])
	check(RankLadder.shared().validate().is_empty() and ChallengeConfig.shared().validate().is_empty(), "CH-11/CH-14 data validates")


func test_kits_match_their_source_presets() -> void:
	for kit_id: String in KIT_SOURCES:
		var kit := load("%s/kits/%s.tres" % [DIR, kit_id]) as ChallengeKit
		check(kit != null, "%s loads" % kit_id)
		if kit == null:
			continue
		var src: Array = KIT_SOURCES[kit_id]
		var preset := StoryPresets.by_id(src[0])
		check(preset != null, "%s: preset %s exists" % [kit_id, src[0]])
		if preset == null:
			continue
		var want := {}
		for f in Array(preset.flags) + Array(src[1]):
			want[f] = true
		for f in src[2]:
			want.erase(f)
		var have := {}
		for f in kit.set_flags:
			have[f] = true
		check(have.keys().size() == kit.set_flags.size(), "%s: no flag set twice" % kit_id)
		var missing := want.keys().filter(func(f: String) -> bool: return not have.has(f))
		var extra := have.keys().filter(func(f: String) -> bool: return not want.has(f))
		check(missing.is_empty() and extra.is_empty(), "%s drifted from preset %s: missing %s, extra %s" % [kit_id, src[0], missing, extra])
		check(Array(kit.clear_flags) == Array(src[2]), "%s clears exactly %s (has %s)" % [kit_id, src[2], kit.clear_flags])
		check(not kit.set_flags.has("transit_pass"), "%s never sets transit_pass (CH-12)" % kit_id)


func test_boss_starts_match_devactions_boss_restart_target() -> void:
	for id in ["br_collector", "br_collector_nohit", "br_krail", "br_krail_nohit"]:
		var ch := _ch(id)
		var target := DevActions.boss_restart_target(ch.boss_id)
		check(target.size() == 2 and ch.start_room == target[0] and ch.start_entry == target[1],
			"%s starts at %s/%s, the dev boss restart uses %s" % [id, ch.start_room, ch.start_entry, target])
		check(ch.start_on == ChallengeData.StartOn.BOSS_STARTED and ch.end_on == ChallengeData.EndOn.BOSS_DEFEATED,
			"%s times from boss_started to boss_defeated" % id)


func test_unlocks_fresh_locked_act1_preset_unlocked() -> void:
	Game.new_game()
	for ch in _all():
		check(not ChallengeLibrary.unlocked(ch), "%s is locked on a fresh profile" % ch.id)
	check(not ChallengeLibrary.rig_open(), "the rig is closed on a fresh profile")
	StoryPresets.apply("act1_complete")
	check(ChallengeLibrary.rig_open(), "the Act I close opens the rig")
	# The M8 presets predate the chase flag: the Rainline unlocks read it.
	for ch in _all():
		var needs_chase := ch.unlock_when == "flag:chase_rainline_done"
		check(ChallengeLibrary.unlocked(ch) != needs_chase, "%s after the act1_complete preset: unlocked %s" % [ch.id, ChallengeLibrary.unlocked(ch)])
	Game.set_flag("chase_rainline_done")
	for ch in _all():
		check(ChallengeLibrary.unlocked(ch), "%s unlocks once Act I and the chase are done" % ch.id)


func test_every_exit_finish_resolves() -> void:
	for ch in _all():
		if ch.end_on != ChallengeData.EndOn.EXIT:
			continue
		var room := (load(ch.start_room) as PackedScene).instantiate()
		check(ChallengeRules.spawn_ids(room).has(ch.start_entry), "%s: %s has spawn %s" % [ch.id, ch.start_room.get_file(), ch.start_entry])
		check(ChallengeRules.exit_targets(room).has(ch.finish_exit_target), "%s: %s has an exit to %s" % [ch.id, ch.start_room.get_file(), ch.finish_exit_target])
		check(ResourceLoader.exists(ch.finish_exit_target), "%s: the exit target exists" % ch.id)
		room.free()


func test_boss_rematch_collector_times_within_2_frames_of_bake() -> void:
	var ch := _ch("br_collector")
	var shipped := GhostCodec.load_file(ch.dev_ghost)
	check(shipped != null, "the Collector rig ghost ships")
	if shipped == null:
		return
	var r: Dictionary = await GhostBake.bake(get_tree(), ch)
	check(bool(r["ok"]), "the BossBot blade rematch finishes: %s" % r["failure"])
	check(absi(int(r["frames"]) - shipped.frames) <= 2, "rematch %d frames, bake %d" % [r["frames"], shipped.frames])


func test_krail_rematch_arms_and_ends_on_defeat() -> void:
	var ch := _ch("br_krail")
	check(await h.start(ch), "the Krail rematch starts")
	var room := h.room()
	check(room != null and room.name == "WardenTower", "it runs in the Warden Tower")
	check(not Game.has_flag("warden_krail_defeated") and Game.has_flag("warden_krail_intro_seen"), "the kit re-arms Krail with the short intro")
	var krail := room.find_child("WardenKrail1", true, false) as Enemy
	check(krail != null, "Krail is in the arena")
	if krail == null:
		return
	# Walk into the arena (it starts on body entry, like test_boss_grid_clamp).
	room.player.teleport(Vector2(100, 0))
	var started := await h.until(func() -> bool: return Challenges.clock.running, 30)
	check(started, "boss_started starts the clock")
	await physics_frames(20)
	krail.health = 1.0
	var attack := load("res://data/combat/hazard_attack.tres") as AttackData
	krail.receive_hit(HitInfo.create(room.player, attack, Vector2.ZERO, Vector2.RIGHT))
	await physics_frames(3)
	check(Challenges.phase() != Challenges.Phase.RUNNING, "the kill ends the run")
	var res := Challenges.last_result
	check(int(res.get("outcome", -1)) == ChallengeData.Outcome.FINISHED, "a finished run (%s)" % [res])
	check(int(res.get("value", -1)) >= 20, "the value counts the fight's frames (%s)" % res.get("value"))
	check(int(res.get("medal", -1)) == ch.medal_for(int(res.get("value", -1))), "the medal follows the thresholds")


func test_splits_list_valid() -> void:
	var list := load("%s/splits/act1_campaign.tres" % DIR) as SplitList
	check(list != null, "act1_campaign.tres is a SplitList")
	if list == null:
		return
	check(list.validate().is_empty(), "split list validates: %s" % list.validate())
	var ids := list.splits.map(func(s: SplitDef) -> String: return s.id)
	check(ids == ["uc_blade", "uc_collector", "uc_relay", "ll_power", "ll_rainline", "ll_krail", "act1_end"], "split order %s" % [ids])
	for s in list.splits:
		check(s.label.length() <= 24, "split %s label <= 24 chars" % s.id)
	check(list.splits[2].room == "res://world/rooms/lowlight/Relay.tscn", "uc_relay splits on the first Relay entry")
	check(list.index_of(SplitList.END_SPLIT) == list.splits.size() - 1, "act1_end closes the list")


func test_act1_campaign_has_auto_room_splits() -> void:
	var list := load("%s/splits/act1_campaign.tres" % DIR) as SplitList
	check(list.auto_room_splits, "auto room splits are on (R04.17)")
	check(list.splits.size() == 7, "the seven milestone splits stay")


func test_medals_redline_at_or_above_dev_frames() -> void:
	var rooms := {}
	var v := ContentValidator.new()
	for ch in _all():
		if ch.dev_bot != &"none":
			var g := GhostCodec.load_file(ch.dev_ghost)
			check(g != null and g.kind == "dev", "%s ships its rig ghost" % ch.id)
			if g:
				check(ch.medal_thresholds[3] >= g.frames, "%s: Redline %d under the rig ghost's %d" % [ch.id, ch.medal_thresholds[3], g.frames])
		check(ChallengeRules.floor_errors(ch, rooms, v).is_empty(), "%s: CH-10 %s" % [ch.id, ChallengeRules.floor_errors(ch, rooms, v)])
	for n: Node in rooms.values():
		if is_instance_valid(n):
			n.free()


func test_krail_redline_above_floor() -> void:
	var ch := _ch("br_krail")
	var room := (load(ch.start_room) as PackedScene).instantiate() as Room
	var f := ChallengeRules.boss_floor_frames(ch, room)
	room.free()
	check(f > 0, "the Krail floor is computable (%d)" % f)
	check(ch.medal_thresholds[3] >= f, "Redline %d >= floor %d" % [ch.medal_thresholds[3], f])
	check(ChallengeRules.best_kit_dps(ch.kit) > 0.0, "the kit has damage")


func test_medal_ratios_match_d150() -> void:
	for ch in _all():
		var m := ch.medal_thresholds
		if PROVISIONAL.has(ch.id):
			check(Array(m) == PROVISIONAL[ch.id], "%s keeps the provisional medals %s (has %s)" % [ch.id, PROVISIONAL[ch.id], m])
			continue
		if ch.dev_bot != &"none":
			var g := GhostCodec.load_file(ch.dev_ghost)
			if g:
				var want := GhostBake.suggest_medals(g.frames)
				check(m == want, "%s medals %s, D-150 from the rig ghost's %d frames gives %s" % [ch.id, m, g.frames, want])
			continue
		# No bot: the ratios hold around its (provisional) Redline.
		var r := float(m[3])
		var want := PackedInt32Array([GhostBake.round_up_half_s(r * 2.4), GhostBake.round_up_half_s(r * 1.7),
			GhostBake.round_up_half_s(r * 1.35), m[3]])
		check(m == want, "%s medals %s, D-150 ratios around Redline give %s" % [ch.id, m, want])
		check(m[3] % (RunClock.FPS / 2) == 0, "%s Redline is a whole half second" % ch.id)


func test_tt_escape_tunnel_absent_in_demo() -> void:
	BuildInfo.set_force_demo(1)
	var ids := ChallengeLibrary.all().map(func(c: ChallengeData) -> String: return c.id)
	check(not ids.has("tt_escape_tunnel"), "a demo build never offers the tunnel trial (it ends at the Relay)")
	check(ids.has("br_collector") and ids.has("tt_first_pursuit") and ids.has("mo_maintenance_shaft"), "the Undercity runs stay (%s)" % [ids])
	BuildInfo.set_force_demo(-1)
	ids = ChallengeLibrary.all().map(func(c: ChallengeData) -> String: return c.id)
	check(ids.has("tt_escape_tunnel"), "the full build offers it")


func test_silver_floor_warns() -> void:
	var ch := _ch("tt_neon_roofs").duplicate() as ChallengeData
	check(ChallengeRules.medal_warnings(ch).is_empty(), "the shipped medals raise no CH-13/CH-15 warning")
	var cfg := ChallengeConfig.shared()
	var r := ch.medal_thresholds[3]
	var floor_frames := roundi(r * cfg.silver_floor_mult + cfg.silver_floor_add_s * RunClock.FPS)
	ch.medal_thresholds = PackedInt32Array([floor_frames + 600, floor_frames - 30, r + 60, r])
	var w := ChallengeRules.medal_warnings(ch)
	check(w.size() == 2, "a Silver under the floor and a Gold 1 s off Redline warn twice (%s)" % [w])
	check(Array(w).any(func(s: String) -> bool: return s.begins_with("[CH-15]")), "CH-15 names the Silver floor")
	check(Array(w).any(func(s: String) -> bool: return s.begins_with("[CH-13]")), "CH-13 names the Gold gap")
