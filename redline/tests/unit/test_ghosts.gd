extends RedlineTestCase
## The ghost engine (M9 D2 §4): the RLGH binary format round-trips and
## rejects bad files (magic, oversize, truncation, a Resource renamed .ghost);
## the recorder samples only counted frames and segments by room; the actor
## follows its samples and hides in other rooms; the PB ghost file is
## written only on a new personal best.

const H := preload("res://tests/fixtures/challenges/ChallengeHarness.gd")

var h: H


func before_each() -> void:
	h = H.new(self, "ghosts")
	h.setup()


func after_each() -> void:
	await h.teardown()


func _ghost(n: int) -> GhostData:
	var g := GhostData.new()
	g.challenge = "fx_trial"
	g.revision = 3
	g.kind = "pb"
	g.profile = 1
	g.segments = [{"room": H.WORLD_A, "start": 0}, {"room": H.WORLD_B, "start": n / 2}]
	g.splits = PackedInt32Array([n / 3, n / 2])
	for i in n:
		g.add_sample(i * 3 - 40, -i, i % 10, i % 16, (i * 37) & 0xFFF)
	g.frames = n
	g.result = ChallengeData.Outcome.FINISHED
	g.date = "2026-09-26T21:04:11"
	return g


func test_codec_roundtrip() -> void:
	var g := _ghost(120)
	var bytes := GhostCodec.encode(g)
	check(bytes.slice(0, 4).get_string_from_ascii() == "RLGH", "magic")
	check(bytes.size() < 120 * 8 + 400, "samples are deflated (%d bytes)" % bytes.size())
	var back := GhostCodec.decode(bytes)
	check(back != null, "decodes")
	if back == null:
		return
	check(back.header() == g.header(), "header round-trips (%s)" % [back.header()])
	check(back.samples == g.samples, "samples round-trip")
	check(back.sample(5)["x"] == -25 and back.sample(5)["y"] == -5 and back.sample(5)["state"] == 5, "sample fields (%s)" % [back.sample(5)])
	var path := h.platform_dir + "/ghosts/rt.ghost"
	check(GhostCodec.save(path, g) == OK and GhostCodec.load_file(path).samples == g.samples, "file round-trip")
	var f := PlayerInputFrame.new()
	f.move_x = -1
	f.jump_held = true
	f.heal_pressed = true
	var d := GhostCodec.decode_input(GhostCodec.encode_input(f))
	check(d.move_x == -1 and d.jump_held and d.heal_pressed and not d.jump_pressed, "input bits round-trip")
	check(GhostCodec.state_index(&"dash") == 6 and GhostCodec.state_index(&"nope") == 255, "state table")


func test_rejects_bad_magic_oversize_and_truncation() -> void:
	var good := GhostCodec.encode(_ghost(60))
	var bad_magic := good.duplicate()
	bad_magic[0] = 88
	check(GhostCodec.decode(bad_magic) == null, "bad magic rejected")
	check(GhostCodec.decode(good.slice(0, good.size() - 6)) == null, "truncated samples rejected")
	check(GhostCodec.decode(good.slice(0, 12)) == null, "truncated header rejected")
	var big := _ghost(2)
	big.frames = GhostCodec.MAX_FRAMES + 1
	var buf := StreamPeerBuffer.new()
	var header := JSON.stringify(big.header()).to_utf8_buffer()
	buf.put_data("RLGH".to_ascii_buffer())
	buf.put_u16(1)
	buf.put_u32(header.size())
	buf.put_data(header)
	buf.put_u32(big.frames * 8)
	check(GhostCodec.decode(buf.data_array) == null, "over the 30-minute cap rejected")
	var mismatch := _ghost(10)
	mismatch.frames = 11
	check(GhostCodec.decode(GhostCodec.encode(mismatch)) == null, "raw_len != frames × 8 rejected")
	var huge := StreamPeerBuffer.new()
	huge.put_data("RLGH".to_ascii_buffer())
	huge.put_u16(1)
	huge.put_u32(GhostCodec.MAX_HEADER + 1)
	huge.put_data(PackedByteArray([0, 0, 0, 0]))
	check(GhostCodec.decode(huge.data_array) == null, "oversized header rejected")
	var wrong_fmt := good.duplicate()
	wrong_fmt.encode_u16(4, 9)
	check(GhostCodec.decode(wrong_fmt) == null, "unknown format rejected")


func test_never_loads_resources_from_user_dir() -> void:
	var path := h.platform_dir + "/ghosts/evil.ghost"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("[gd_resource type=\"Resource\" load_steps=2 format=3]\n\n[ext_resource type=\"Script\" path=\"res://challenges/GhostData.gd\" id=\"1\"]\n\n[resource]\nscript = ExtResource(\"1\")\n")
	f.close()
	check(GhostCodec.load_file(path) == null, "a .tres renamed .ghost is rejected")
	var src := FileAccess.get_file_as_string("res://challenges/GhostCodec.gd")
	check(not src.contains("get_var(") and not src.contains("store_var(") and not src.contains("ResourceLoader.load"), "the codec never uses var or Resource loading")
	var probe: Object = GhostData.new()
	check(not (probe is Resource), "GhostData is not a Resource")


func test_recorder_segments_by_room_and_skips_transitions() -> void:
	Game.set_ability(&"dash", true)
	check(await h.start(H.fx(H.STAGED), {}), "staged run started")
	h.drive().move_x = 1
	check(await h.until(func() -> bool: return Challenges.stage_index() == 1 and SceneRouter.current_room_path == H.STAGE_B and not SceneRouter.transitioning, 400), "reached stage B")
	h.drive().move_x = 1
	await physics_frames(10)
	var data := Challenges.recorder.data
	var rooms: Array = data.segments.map(func(s: Dictionary) -> String: return s["room"])
	check(rooms == [H.STAGE_A, H.STAGE_B], "one segment per room (%s)" % [rooms])
	check(data.sample_count() == Challenges.clock.frames, "one sample per counted frame (%d vs %d)" % [data.sample_count(), Challenges.clock.frames])
	check(data.splits.size() == 1 and Challenges.clock.splits.size() == 1, "the stage goal split")
	var seg_b := int(data.segments[1]["start"])
	check(data.room_at(seg_b) == H.STAGE_B and data.room_at(seg_b - 1) == H.STAGE_A, "room_at")


func test_actor_follows_samples_and_hides_in_other_room() -> void:
	var g := GhostData.new()
	g.segments = [{"room": H.WORLD_A, "start": 0}, {"room": H.WORLD_B, "start": 5}]
	for i in 10:
		g.add_sample(i * 10, -i, 1, GhostData.FLAG_RIGHT, 0)
	g.frames = 10
	var actor := GhostActor.new(GhostPlayback.new(g, "dev"), H.WORLD_A)
	add_child(actor)
	actor.show_frame(3)
	check(actor.visible and actor.position == Vector2(30, -3), "follows sample 3 (%s)" % [actor.position])
	actor.show_frame(7)
	check(not actor.visible, "hidden while the ghost is in another room")
	var in_b := GhostActor.new(GhostPlayback.new(g, "pb"), H.WORLD_B)
	add_child(in_b)
	in_b.show_frame(50)
	check(in_b.visible and in_b.position == Vector2(90, -9), "holds its last sample when done")
	check(actor.tag_text() != in_b.tag_text(), "PB and rig ghosts differ by tag text")
	actor.queue_free()
	in_b.queue_free()


func _run_for(frames: int) -> void:
	h.drive().move_x = 1
	await physics_frames(frames)
	Challenges.finish(ChallengeData.Outcome.FINISHED)


func test_pb_ghost_written_only_on_new_best() -> void:
	await h.goto(H.WORLD_A, &"start")
	check(await h.start(H.fx(H.TRIAL), {"room": H.WORLD_A, "entry": &"start"}), "run started")
	await _run_for(20)
	var path := Challenges.records.ghost_path("fx_trial", 1)
	check(Challenges.last_result["new_best"] and FileAccess.file_exists(path), "first finish writes the PB ghost")
	var first := FileAccess.get_file_as_bytes(path)
	var frames1 := GhostCodec.load_file(path).frames
	Challenges.restart(&"menu")
	await h.until(func() -> bool: return Challenges.attempt() == 2 and Challenges.phase() == Challenges.Phase.RUNNING and h.room() != null)
	await physics_frames(1)
	await _run_for(40)
	check(not Challenges.last_result["new_best"] and FileAccess.get_file_as_bytes(path) == first, "a slower run leaves the file alone")
	Challenges.restart(&"menu")
	await h.until(func() -> bool: return Challenges.attempt() == 3 and Challenges.phase() == Challenges.Phase.RUNNING)
	await physics_frames(1)
	await _run_for(8)
	check(Challenges.last_result["new_best"], "faster: new best")
	var g := GhostCodec.load_file(path)
	check(g != null and g.frames < frames1 and g.frames == int(Challenges.last_result["value"]), "rewritten with the faster run (%d < %d)" % [g.frames if g else -1, frames1])


func test_run_spawns_pb_ghost_on_next_attempt() -> void:
	await h.goto(H.WORLD_A, &"start")
	check(await h.start(H.fx(H.TRIAL), {"room": H.WORLD_A, "entry": &"start"}), "run started")
	await _run_for(30)
	var old_id := h.room().get_instance_id()
	Challenges.restart(&"menu")
	await h.until(func() -> bool: return h.room() != null and h.room().get_instance_id() != old_id)
	check(Challenges.ghosts.size() == 1 and Challenges.ghosts[0].kind == "pb", "the PB ghost plays (mode 1)")
	var actor := h.room().find_child("Ghost_pb", true, false) as GhostActor
	check(actor != null, "an actor in the run room")
	h.drive().move_x = 1
	await physics_frames(10)
	check(actor != null and actor.visible and actor.position.x > 40.0, "it follows the clock (%s)" % [actor.position if actor else Vector2.ZERO])
	check(Challenges.ghost_mode_label() == "Personal best", "mode label from data")
	Settings.challenge_ghost = 0
	Challenges._load_ghosts()
	check(Challenges.ghosts.is_empty(), "mode Off: no ghost")
