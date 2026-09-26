extends RedlineTestCase
## The shipped rig ghosts (M9 T08, D2 §4.5, R08.4, R08.14): an in-process
## GhostBake --check of every shipped ghost gives exactly its frames; the
## tt_neon_roofs ghost's input track, replayed through the real run, gives
## the same run; and a bake pins every timing setting (a host hitstop of 0.5
## changes nothing) with no fade registered, then puts the settings back.
## Headless --fixed-fps 60 only (like every exact-frame test).

const H := preload("res://tests/fixtures/challenges/ChallengeHarness.gd")

var h: H


func before_each() -> void:
	h = H.new(self, "dev_ghosts")
	h.setup()
	ChallengeLibrary.data_dir = ChallengeLibrary.DEFAULT_DIR
	ChallengeLibrary.clear_cache()


func after_each() -> void:
	await h.teardown()


func _shipped() -> Array[ChallengeData]:
	var out: Array[ChallengeData] = []
	for ch in ChallengeLibrary.all():
		if ch.dev_bot != &"none":
			out.append(ch)
	return out


func test_dev_ghosts_current() -> void:
	var list := _shipped()
	check(list.size() >= 7, "at least the seven baked challenges ship a rig ghost (%d)" % list.size())
	for ch in list:
		var shipped := GhostCodec.load_file(ch.dev_ghost)
		check(shipped != null and shipped.kind in ["dev", "dev_hand"], "%s: %s is a readable rig ghost" % [ch.id, ch.dev_ghost])
		if shipped != null and shipped.kind == "dev_hand":
			continue # hand-played (promoted PB): no bot bake to match
		var r: Dictionary = await GhostBake.bake(get_tree(), ch)
		check(bool(r["ok"]), "%s bakes: %s" % [ch.id, r["failure"]])
		if bool(r["ok"]):
			var why := GhostBake.check_against_shipped(ch, int(r["frames"]))
			check(why == "", "%s: %s (re-bake with devtools/GhostBake.tscn)" % [ch.id, why])


func test_input_track_reproduces_dev_ghost() -> void:
	var ch := ChallengeLibrary.by_id("tt_neon_roofs")
	var shipped := GhostCodec.load_file(ch.dev_ghost)
	check(shipped != null, "the Neon Roofs rig ghost ships")
	if shipped == null:
		return
	var r: Dictionary = await GhostBake.bake(get_tree(), ch, false, shipped)
	check(bool(r["ok"]), "the replayed inputs finish the run: %s" % r["failure"])
	if not bool(r["ok"]):
		return
	var g: GhostData = r["ghost"]
	check(g.frames == shipped.frames, "replay %d frames, rig ghost %d" % [g.frames, shipped.frames])
	var a := g.sample(g.sample_count() - 1)
	var b := shipped.sample(shipped.sample_count() - 1)
	check(a.get("x") == b.get("x") and a.get("y") == b.get("y"), "the replay ends where the ghost does (%s vs %s)" % [a, b])
	check(g.samples == shipped.samples, "every sample matches")


func test_bake_pins_timing_settings() -> void:
	var ch := ChallengeLibrary.by_id("tt_neon_roofs")
	var shipped := GhostCodec.load_file(ch.dev_ghost)
	Settings.hitstop_scale = 0.5
	Settings.aim_assist = 2
	Settings.jump_hold_mode = 1
	var r: Dictionary = await GhostBake.bake(get_tree(), ch)
	check(bool(r["ok"]), "the bake finishes: %s" % r["failure"])
	check(bool(r["fade_null"]) and not GhostBake.fade_live(), "no fade is registered during the bake (R08.14)")
	if shipped and bool(r["ok"]):
		check(int(r["frames"]) == shipped.frames, "host hitstop 0.5: %d frames, shipped %d" % [r["frames"], shipped.frames])
	check(is_equal_approx(Settings.hitstop_scale, 0.5) and Settings.aim_assist == 2 and Settings.jump_hold_mode == 1,
		"the host's settings are back after the bake")
	check(not Challenges.active() and Game.held_profile == null, "the bake leaves no run and no held profile")
