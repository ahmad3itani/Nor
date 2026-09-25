extends RedlineTestCase
## M8 engine contracts (T02): count: conditions, the act1_complete load
## derivation, set_flag type safety, MusicDirector override/MEMORY/hub
## layers, NOTE map markers, story presets, the new sfx ids and the
## export-safe DataDir scans.

const TEST_SAVE_DIR := "user://test_m8_engine"

var _changes: Array = []


func before_each() -> void:
	SaveManager.save_dir = TEST_SAVE_DIR
	Game.new_game()
	_changes.clear()
	EventBus.flag_changed.connect(_on_flag)


func after_each() -> void:
	EventBus.flag_changed.disconnect(_on_flag)
	if DirAccess.dir_exists_absolute(TEST_SAVE_DIR):
		for f in DirAccess.get_files_at(TEST_SAVE_DIR):
			DirAccess.remove_absolute("%s/%s" % [TEST_SAVE_DIR, f])
	SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR
	Game.new_game()


func _on_flag(id: String, value: Variant) -> void:
	_changes.append([id, value])


func _changes_for(id: String) -> int:
	return _changes.filter(func(c: Array) -> bool: return c[0] == id).size()


func test_count_condition() -> void:
	check(not Game.check_condition("count:shards:2"), "count:shards:2 true at 0")
	Game.state.core_shards = 2
	check(Game.check_condition("count:shards:2") and not Game.check_condition("count:shards:3"), "count:shards follows core_shards")
	check(not Game.check_condition("count:circuits:1"), "count:circuits:1 true with none owned")
	Game.state.owned_circuits.append("test_circuit")
	check(Game.check_condition("count:circuits:1"), "count:circuits follows owned_circuits")
	check(not Game.check_condition("count:fragments:1"), "count:fragments:1 true with none")
	Game.state.memory_fragments.append("mf_lowlight_01")
	check(Game.check_condition("count:fragments:1") and Game.check_condition("!count:fragments:2"), "count:fragments follows memory_fragments")
	var ids: Array = SliceStats.totals()["secret_ids"]
	check(ids.size() >= 2, "need at least two secrets in the slice")
	check(not Game.check_condition("count:secrets:1"), "count:secrets:1 true with none found")
	Game.mark_collected(ids[0])
	Game.mark_collected(ids[1])
	check(Game.count_metric("secrets") == 2 and Game.check_condition("count:secrets:2"), "count:secrets follows collected secrets")
	check(Game.count_metric("bogus") == -1, "unknown metric must return -1")
	check(not Game.check_condition("count:bogus:1"), "count:bogus:1 must be false")


func test_load_derives_act1_complete() -> void:
	Game.set_flag("slice_end_seen")
	check(Game.save_game() == OK, "save failed")
	Game.new_game()
	check(Game.load_game(1), "load failed")
	check(Game.has_flag("act1_complete"), "a save past the Act I end must load with act1_complete")
	Game.new_game()
	Game.set_flag("dead_air_complete")
	Game.save_game()
	Game.new_game()
	check(Game.load_game(1), "second load failed")
	check(not Game.has_flag("act1_complete"), "act1_complete derived without slice_end_seen")
	check(SaveManager.profile_path(1).begins_with(TEST_SAVE_DIR), "test must not touch the real save dir")


func test_set_flag_type_change_safe() -> void:
	Game.set_flag("x", 1)
	Game.set_flag("x", true)
	Game.set_flag("x", 2.0)
	check(_changes_for("x") == 3, "each type or value change emits once: %s" % [_changes])
	check(typeof(Game.state.flags["x"]) == TYPE_FLOAT and Game.flag_int("x") == 2, "last value kept")
	Game.set_flag("y", true)
	Game.set_flag("y", true)
	check(_changes_for("y") == 1, "an equal bool must not re-emit")
	Game.state.flags["n"] = 2.0  # as a JSON load returns it
	Game.set_flag("n", 2)
	check(_changes_for("n") == 0, "2 after a loaded 2.0 must be a no-op")
	Game.set_flag("n", 3)
	check(_changes_for("n") == 1, "a real number change emits once")
	Game.set_flag("b", true)
	Game.set_flag("b", 1)
	check(_changes_for("b") == 2, "bool -> int is a type change and emits")


func test_data_dir_remap_names() -> void:
	check(DataDir.load_name("a.tres") == "a.tres", "plain tres")
	check(DataDir.load_name("a.tres.remap") == "a.tres", "remapped tres")
	check(DataDir.load_name("a.gd") == "", "non-tres")
	var loaded: Array[String] = []
	for q in Game.quests.quests:
		loaded.append(q.resource_path)
	loaded.sort()
	var listed := DataDir.list("res://data/quests")
	check(Array(listed) == Array(loaded), "DataDir.list %s != QuestTracker %s" % [listed, loaded])
	for p in listed:
		check(p.ends_with(".tres"), "%s must be a load path" % p)


func test_data_dir_scene_names() -> void:
	check(DataDir.load_name("x.tscn.remap", "tscn") == "x.tscn", "remapped scene")
	check(DataDir.load_name("x.tscn", "tscn") == "x.tscn", "plain scene")
	check(DataDir.load_name("x.tres", "tscn") == "", "a tres is not a scene")
	# The pre-edit rule: every .tscn per WORLD_ROOM_DIRS folder, sorted per folder.
	var expected := PackedStringArray()
	for dir in ContentValidator.WORLD_ROOM_DIRS:
		var files := DirAccess.get_files_at(dir)
		files.sort()
		for f in files:
			if f.ends_with(".tscn"):
				expected.append("%s/%s" % [dir, f])
	check(SliceStats.room_paths() == expected, "room_paths changed: %s" % SliceStats.room_paths())
	check(int(SliceStats.totals()["fragments"]) == 5, "Act I still counts 5 fragments")
