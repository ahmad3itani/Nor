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
