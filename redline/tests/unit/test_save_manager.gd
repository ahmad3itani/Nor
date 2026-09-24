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
	data["scrap_banked"] = 42
	data["flags"]["woke_up"] = true
	check(SaveManager.save_profile(1, data) == OK, "save failed")
	var loaded := SaveManager.load_profile(1)
	check(int(loaded["scrap_banked"]) == 42, "scrap not persisted")
	check(loaded["flags"].get("woke_up", false) == true, "flag not persisted")
	check(int(loaded["schema_version"]) == SaveManager.CURRENT_SCHEMA_VERSION, "schema version")


func test_second_save_keeps_backup_and_recovers_from_corruption() -> void:
	var data := SaveManager.new_profile_data()
	data["scrap_banked"] = 1
	SaveManager.save_profile(2, data)
	data["scrap_banked"] = 2
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
		check(int(loaded["scrap_banked"]) == 1, "backup should hold previous save")


func test_migrates_v0() -> void:
	var migrated := SaveManager.migrate({"scrap": 7, "flags": {"a": true}})
	check(int(migrated.get("schema_version", -1)) == SaveManager.CURRENT_SCHEMA_VERSION, "not migrated to current")
	check(int(migrated["scrap_banked"]) == 7, "scrap lost in migration")
	check(migrated["flags"].get("a", false) == true, "flags lost in migration")


func test_migrates_v1_skeleton_to_game_state() -> void:
	var v1 := {"schema_version": 1, "story_flags": {"met_orr": true}, "abilities": {"dash": true},
		"currencies": {"scrap": 12}, "statistics": {"play_time_sec": 30.0, "deaths": 2}}
	var state := GameState.from_dict(SaveManager.migrate(v1))
	check(state.scrap_banked == 12 and state.deaths == 2, "v1 currencies/stats lost")
	check(bool(state.flags.get("met_orr", false)) and bool(state.abilities.get("dash", false)), "v1 flags/abilities lost")


func test_game_state_round_trips_through_json() -> void:
	var s := GameState.new()
	s.scrap_banked = 5
	s.scrap_unbanked = 3
	s.flags["quest_stage"] = 2
	s.equipped_circuits.append("scavenger")
	s.memory_fragments.append("mf_lowlight_01")
	s.dropped_scrap = {"room": "res://x.tscn", "x": 10.0, "y": -2.0, "amount": 3}
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	var back := GameState.from_dict(parsed)
	check(back.scrap_banked == 5 and back.scrap_unbanked == 3, "scrap lost")
	check(int(back.flags["quest_stage"]) == 2, "int flag lost")
	check(back.equipped_circuits.size() == 1 and back.equipped_circuits[0] == "scavenger", "circuits lost")
	check(back.memory_fragments.has("mf_lowlight_01"), "fragments lost")
	check(int(back.dropped_scrap["amount"]) == 3, "dropped cache lost")
	check(back.spend_scrap(7) and back.total_scrap() == 1, "spend_scrap should use banked then unbanked")
	check(not back.spend_scrap(5), "overspend should fail")


func test_missing_profile_returns_empty() -> void:
	check(SaveManager.load_profile(99).is_empty(), "expected empty dict")
