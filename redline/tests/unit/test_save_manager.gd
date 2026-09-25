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


# --- M8 save rule (D-116: all M8 state is flags; no key, no schema bump) ---

## The GameState key set is pinned: adding a key means updating this list AND
## reading D-087/D-090 (new optional key -> from_dict default + old-save test).
const GAME_STATE_KEYS := ["abilities", "anchors_rested", "collected", "core_shards", "deaths", "dropped_scrap",
	"equipped_circuits", "flags", "health", "injectors", "last_anchor_id", "last_anchor_room", "last_entry_id",
	"last_entry_room", "map_explored", "map_pins", "melee_weapon", "memory_fragments", "owned_circuits",
	"owned_weapons", "play_time_sec", "ranged_weapon", "reactor_charge", "scrap_banked", "scrap_unbanked",
	"visited_rooms"]
const SAVE_V3 := "res://tests/fixtures/save_v3_slice.json"


func test_m8_adds_no_game_state_keys() -> void:
	var keys: Array = GameState.new().to_dict().keys()
	keys.sort()
	check(keys == GAME_STATE_KEYS, "GameState keys changed (D-090): %s" % [keys])
	check(SaveManager.CURRENT_SCHEMA_VERSION == 3, "M8 needs no schema bump")


func test_v3_fixture_loads_with_m8_defaults() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE_V3))
	var state := GameState.from_dict(SaveManager.migrate(raw))
	check(int(state.flags.get("arc_orr_stage", 0)) == 0, "no arc stage in an M7 save")
	check(int(state.flags.get("memories_remembered", 0)) == 0, "no memories remembered in an M7 save")
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var f := FileAccess.open(SaveManager.profile_path(1), FileAccess.WRITE)
	f.store_string(JSON.stringify(raw))
	f.close()
	check(Game.load_game(1), "the v3 fixture loads")
	check(EndingResolver.resolve() == null, "no ending resolves from an M7 save")
	check(ActLibrary.current_act() == 1, "an M7 save past Krail (no slice_end_seen) is still in Act I")
	# JSON turns ints into floats; flag_int / atleast: still read 2.
	Game.set_flag("memories_remembered", 2)
	check(Game.save_game() == OK, "saved")
	check(Game.load_game(1), "reloaded")
	check(Game.flag_int("memories_remembered") == 2 and Game.check_condition("atleast:memories_remembered:2"),
		"an int flag round-trips through JSON as 2 (%s)" % Game.state.flags.get("memories_remembered"))
	Game.new_game()
