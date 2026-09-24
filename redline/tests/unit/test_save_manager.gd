extends RedlineTestCase
## Save serialization, atomic write/backup recovery and migration (bible §29, §35).

const TEST_DIR := "user://test_saves"


func before_each() -> void:
	SaveManager.save_dir = TEST_DIR
	_clean()


func after_each() -> void:
	_clean()
	SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR


func _clean() -> void:
	if not DirAccess.dir_exists_absolute(TEST_DIR):
		return
	for f in DirAccess.get_files_at(TEST_DIR):
		DirAccess.remove_absolute("%s/%s" % [TEST_DIR, f])


func test_roundtrip() -> void:
	var data := SaveManager.new_profile_data()
	data["currencies"]["scrap"] = 42
	data["story_flags"]["woke_up"] = true
	check(SaveManager.save_profile(1, data) == OK, "save failed")
	var loaded := SaveManager.load_profile(1)
	check(int(loaded["currencies"]["scrap"]) == 42, "scrap not persisted")
	check(loaded["story_flags"].get("woke_up", false) == true, "flag not persisted")
	check(int(loaded["schema_version"]) == SaveManager.CURRENT_SCHEMA_VERSION, "schema version")


func test_second_save_keeps_backup_and_recovers_from_corruption() -> void:
	var data := SaveManager.new_profile_data()
	data["currencies"]["scrap"] = 1
	SaveManager.save_profile(2, data)
	data["currencies"]["scrap"] = 2
	SaveManager.save_profile(2, data)
	var path := SaveManager.profile_path(2)
	check(FileAccess.file_exists(path + ".bak"), "backup not written")
	check(not FileAccess.file_exists(path + ".tmp"), "temp file left behind")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ corrupted")
	f.close()
	var loaded := SaveManager.load_profile(2)
	check(not loaded.is_empty(), "did not recover from backup")
	if not loaded.is_empty():
		check(int(loaded["currencies"]["scrap"]) == 1, "backup should hold previous save")


func test_migrates_v0() -> void:
	var migrated := SaveManager.migrate({"scrap": 7, "flags": {"a": true}})
	check(int(migrated.get("schema_version", -1)) == 1, "not migrated to v1")
	check(int(migrated["currencies"]["scrap"]) == 7, "scrap lost in migration")
	check(migrated["story_flags"].get("a", false) == true, "flags lost in migration")


func test_missing_profile_returns_empty() -> void:
	check(SaveManager.load_profile(99).is_empty(), "expected empty dict")
