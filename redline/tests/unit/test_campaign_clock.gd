extends RedlineTestCase
## CampaignClock (M9 D2 §3.6/§7.1, R04.16/R04.17/R04.29): campaign IGT counts
## only in world rooms, never in a run, a pause or a transition; splits fire
## once, in list order; pre-M9 saves (igt_complete false) never post a best;
## a title New Game does; the best posts at act1_end; neutral tags (assists,
## generous checkpoints) union into the profile; per-room splits fire once.

const H := preload("res://tests/fixtures/challenges/ChallengeHarness.gd")
const SPLITS := "res://tests/fixtures/challenges/splits/fx_campaign.tres"

var h: H
var _splits: Array = []


func before_each() -> void:
	h = H.new(self, "campaign_clock")
	h.setup()
	_splits = []
	h.listen(EventBus.speedrun_split, func(id: String, igt: int, delta: int) -> void: _splits.append([id, igt, delta]))
	Challenges.campaign.split_list = (load(SPLITS) as SplitList).duplicate(true)


func after_each() -> void:
	await h.teardown()


func test_igt_counts_world_rooms_only_and_not_in_challenges() -> void:
	var r := await h.goto(H.WORLD_A, &"start")
	var f0 := Game.state.igt_frames
	await physics_frames(10)
	var f1 := Game.state.igt_frames
	check(f1 - f0 >= 9 and f1 - f0 <= 10, "counts in a world room (%d)" % (f1 - f0))
	Challenges.force_active = true
	await physics_frames(5)
	check(Game.state.igt_frames == f1, "never during a run")
	Challenges.force_active = false
	get_tree().paused = true
	await physics_frames(5)
	get_tree().paused = false
	check(Game.state.igt_frames == f1, "never while paused")
	SceneRouter.transitioning = true
	await physics_frames(5)
	SceneRouter.transitioning = false
	check(Game.state.igt_frames == f1, "never in a transition")
	r.world_room = false
	await physics_frames(5)
	check(Game.state.igt_frames == f1, "never in a lab room")
	r.world_room = true
	check(not CampaignClock._off_map(H.WORLD_A) and CampaignClock._off_map("res://world/rooms/challenge/PulsePit.tscn"), "challenge rooms are off the clock")


func test_splits_fire_once_in_order() -> void:
	await h.goto(H.WORLD_A, &"start")
	Challenges.records.submit_campaign(1, 99999, {"fx_a": 5, "fx_b": 10})
	Game.state.igt_frames = 100
	Game.set_flag("fx_split_b")
	check(_splits.size() == 1 and _splits[0][0] == "fx_b" and _splits[0][2] == 0, "out of order: recorded with no delta (%s)" % [_splits])
	Game.state.igt_frames = 200
	Game.set_flag("fx_split_a")
	check(_splits.size() == 2 and _splits[1] == ["fx_a", 200, 195], "in order: delta against the best split (%s)" % [_splits])
	Game.set_flag("fx_split_a", false)
	Game.set_flag("fx_split_a")
	Game.set_flag("fx_split_b", false)
	Game.set_flag("fx_split_b")
	check(_splits.size() == 2, "each split fires once per profile (%s)" % [_splits])
	check(Game.state.igt_splits == {"fx_b": 100, "fx_a": 200}, "recorded in the profile (%s)" % [Game.state.igt_splits])


func _write_v3() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(H.SAVE_V3))
	SaveManager.save_profile(1, d)


func test_v3_fixture_igt_incomplete_never_posts() -> void:
	_write_v3()
	check(Game.load_game(1), "v3 fixture loads")
	check(not Game.state.igt_complete and Game.state.igt_frames == 0 and Game.state.igt_splits.is_empty(), "pre-M9 defaults")
	await h.goto(H.WORLD_A, &"start")
	Game.state.igt_frames = 1234
	Game.set_flag("fx_split_end")
	check(_splits.size() == 1 and _splits[0][0] == "act1_end", "the split still shows")
	check(Challenges.records.campaign_best(1) == -1, "but an incomplete IGT never posts a best")


func test_new_game_igt_complete() -> void:
	Game.start_campaign()
	check(Game.state.igt_complete, "a title New Game counts")
	Game.new_game()
	check(not Game.state.igt_complete, "a bare new_game does not")
	Game.start_campaign()
	var round_trip := GameState.from_dict(JSON.parse_string(JSON.stringify(Game.state.to_dict())))
	check(round_trip.igt_complete, "survives a save")


func test_campaign_best_submitted_at_act1_end() -> void:
	Game.start_campaign()
	await h.goto(H.WORLD_A, &"start")
	Game.state.igt_frames = 100
	Game.set_flag("fx_split_a")
	Game.state.igt_frames = 5000
	Game.set_flag("fx_split_end")
	check(Challenges.records.campaign_best(1) == 5000, "posted at act1_end (%d)" % Challenges.records.campaign_best(1))
	check(Challenges.records.campaign_best_splits(1).get("fx_a") == 100, "with the splits (%s)" % [Challenges.records.campaign_best_splits(1)])
	check(not Challenges.records.submit_campaign(1, 6000, {}), "a slower run keeps the best")
	check(Challenges.records.submit_campaign(1, 4000, {}) and Challenges.records.campaign_best(1) == 4000, "a faster one replaces it")


func test_campaign_tags_union_assists() -> void:
	var tags := ["aim_assist"]
	Challenges.tag_provider = func() -> PackedStringArray: return PackedStringArray(tags)
	await h.goto(H.WORLD_A, &"start")
	EventBus.settings_changed.emit()
	await physics_frames(2)
	check(Array(Game.state.igt_tags) == ["aim_assist"], "unioned while counting (%s)" % [Game.state.igt_tags])
	tags.clear()
	EventBus.settings_changed.emit()
	await physics_frames(2)
	check(Array(Game.state.igt_tags) == ["aim_assist"], "switching it off never removes the tag")
	Settings.hitstop_scale = 0.5
	EventBus.settings_changed.emit()
	await physics_frames(2)
	check(Array(Game.state.igt_tags) == ["aim_assist", "hitstop_reduced"], "timing tag too (%s)" % [Game.state.igt_tags])
	Game.start_campaign()
	check(Game.state.igt_tags.is_empty(), "a new campaign starts untagged")
	Game.state.igt_frames = 10
	Game.state.igt_tags = PackedStringArray(["aim_assist"])
	Game.set_flag("fx_split_end")
	check(Array(Challenges.records.campaign_best_tags(1)) == ["aim_assist"], "the best keeps its tags")


func test_generous_checkpoints_tagged() -> void:
	Challenges.tag_provider = func() -> PackedStringArray: return PackedStringArray()
	await h.goto(H.WORLD_A, &"start")
	Settings.generous_checkpoints = true
	EventBus.settings_changed.emit()
	await physics_frames(2)
	check(Array(Game.state.igt_tags) == ["checkpoints"], "room checkpoints are a timing tag (%s)" % [Game.state.igt_tags])


func test_auto_room_splits_fire_once_per_room() -> void:
	var paths := SliceStats.room_paths()
	check(paths.size() > 2, "district rooms exist")
	Challenges.campaign.note_room(paths[0])
	check(_splits.is_empty(), "no room splits unless the list asks")
	Challenges.campaign.split_list.auto_room_splits = true
	Game.state.igt_frames = 42
	Challenges.campaign.note_room(paths[0])
	Challenges.campaign.note_room(paths[0])
	Challenges.campaign.note_room(paths[1])
	Challenges.campaign.note_room(H.WORLD_A)
	var ids: Array = _splits.map(func(s: Array) -> String: return s[0])
	var want := ["room:" + paths[0].get_file().get_basename(), "room:" + paths[1].get_file().get_basename()]
	check(ids == want, "once per district room, never fixtures (%s)" % [ids])
	check(Game.state.igt_splits.get(want[0]) == 42, "recorded under the same id")
	Challenges.force_active = true
	Challenges.campaign.note_room(paths[2])
	check(_splits.size() == 2, "never during a run")
