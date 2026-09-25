extends RedlineTestCase
## M6 content validation: the whole game passes, and the checks catch what
## they claim to (broken paths, dangling flags, bad conditions).


func test_all_content_is_valid() -> void:
	var v := ContentValidator.new().run()
	for e in v.errors:
		check(false, e)
	check(int(v.stats["rooms"]) >= 7 and int(v.stats["resources"]) > 50, "validator scanned too little: %s" % v.stats)
	check((v.collectibles["NeonRoofs"] as Array).size() >= 2, "collectible tracker missed Neon Roofs")


func test_reference_scanner_skips_patterns_and_flags_missing() -> void:
	var refs := ContentValidator.references_in('a = "res://data/catalog.tres" b = "res://data/shops/%s.tres" c = "res://nope/missing.tres"')
	check(refs.size() == 2, "format strings must be skipped: %s" % refs)
	check(ContentValidator._exists(refs[0]) and not ContentValidator._exists(refs[1]), "existence check wrong")


func test_flag_lint_catches_dangling_and_bad_conditions() -> void:
	var v := ContentValidator.new()
	v._consume("never_set_anywhere", "fake.tres")
	v._produce("set_but_unread", "fake.tres")
	v._consume_condition("flg:typo", "fake.tres")
	v.validate_flags()
	check(Array(v.errors).any(func(e: String) -> bool: return e.contains("never_set_anywhere")), "dangling flag not reported")
	check(Array(v.errors).any(func(e: String) -> bool: return e.contains("unknown condition")), "bad condition not reported")
	check(Array(v.warnings).any(func(w: String) -> bool: return w.contains("set_but_unread")), "unused flag not warned")


## D6: every stub FlagDeclaration the world skeleton (D0) planted for a flag
## whose producer had not landed yet (got_pulse_blade, collector_drone_defeated,
## lowlight_power_rerouted, chase_rainline_done, shortcut_smuggler_route) is
## gone, replaced by the real producer in its room.
func test_no_stub_declarations_left() -> void:
	var v := ContentValidator.new().run()
	var stubs := Array(v.warnings).filter(func(w: String) -> bool: return w.contains("stub flag declaration"))
	check(stubs.is_empty(), "stub flag declarations left: %s" % str(stubs))
	for path in SliceStats.room_paths():
		var inst := (load(path) as PackedScene).instantiate()
		check(inst.find_children("*", "FlagDeclaration", true, false).is_empty(), "%s still holds a FlagDeclaration" % path.get_file())
		inst.free()


## M8 resource content protocol: a data resource declares its flags through
## content_flags() and lints itself through content_check(); check_resource
## is the per-resource test entry point (nothing written under res://data).
class ProtocolRes extends Resource:
	var produces: Array = ["proto_made"]
	var consumes: Array = ["proto_needed"]
	var conditions: Array = ["flag:proto_cond"]

	func content_flags() -> Dictionary:
		return {"produces": produces, "consumes": consumes, "conditions": conditions}

	func content_check() -> PackedStringArray:
		return PackedStringArray(["broken thing", "WARN: odd thing"])


func test_resource_protocol_registers_flags() -> void:
	var v := ContentValidator.new()
	v.check_resource(ProtocolRes.new(), "res://data/test/x.tres")
	v.validate_flags()
	check(v.produced.get("proto_made") == "x.tres", "content_flags produces not registered: %s" % v.produced)
	check(v.consumed.get("proto_needed") == "x.tres" and v.consumed.get("proto_cond") == "x.tres",
		"content_flags consumes/conditions not registered: %s" % v.consumed)
	check(v.errors.has("x.tres: broken thing"), "content_check error not routed: %s" % v.errors)
	check(v.warnings.has("x.tres: odd thing"), "content_check WARN not routed: %s" % v.warnings)
	check(not v.errors.has("x.tres: WARN: odd thing"), "a WARN line must not be an error")
	check(Array(v.errors).any(func(e: String) -> bool: return e.contains("proto_needed") and e.contains("nothing sets it")),
		"a consumed flag nobody sets must be a dangling-flag error: %s" % v.errors)


func test_count_condition_lint() -> void:
	var v := ContentValidator.new()
	v._consume_condition("count:secrets:5", "res://data/test/x.tres")
	v._consume_condition("!count:fragments:2", "res://data/test/x.tres")
	check(v.errors.is_empty() and v.consumed.is_empty(), "count: conditions are valid and consume no flag: %s %s" % [v.errors, v.consumed])
	v._consume_condition("count:bogus:1", "res://data/test/x.tres")
	check(v.errors.size() == 1 and v.errors[0].contains("unknown count metric"), "count:bogus must be an error: %s" % v.errors)
	check(ContentValidator.is_valid_condition("count:secrets:5") and ContentValidator.is_valid_condition("!flag:a")
		and ContentValidator.is_valid_condition("") and ContentValidator.is_valid_condition("atleast:talks_orr:2"),
		"is_valid_condition rejects valid expressions")
	check(not ContentValidator.is_valid_condition("count:bogus:1") and not ContentValidator.is_valid_condition("flg:typo")
		and not ContentValidator.is_valid_condition("count:shards:x") and not ContentValidator.is_valid_condition("flag:"),
		"is_valid_condition accepts invalid expressions")


func test_producers_multimap() -> void:
	var v := ContentValidator.new()
	v.check_resource(ProtocolRes.new(), "res://data/test/first.tres")
	v.check_resource(ProtocolRes.new(), "res://data/other/second.tres")
	check(v.produced.get("proto_made") == "first.tres", "produced keeps the first producer's file name: %s" % v.produced)
	check(v.producers.get("proto_made") == ["res://data/test/first.tres", "res://data/other/second.tres"],
		"producers must list every full path in order: %s" % v.producers)
	check(v.consumed.get("proto_needed") == "first.tres", "consumed keeps the first consumer's file name")
	check(v.consumers.get("proto_needed") == ["res://data/test/first.tres", "res://data/other/second.tres"],
		"consumers must list every full path in order: %s" % v.consumers)


## M8: a WorldStateSwitch is visual only; hiding it must not leave a wall,
## pickup or talker in play. Fixture: tools/roomgen/fixtures_scaffold.py.
func test_switch_children_visual_only() -> void:
	var v := ContentValidator.new().check_room("res://tests/fixtures/scaffold_m8_switch_bad.tscn", false)
	check(v.errors == PackedStringArray(["room scaffold_m8_switch_bad: BadSwitch: SolidCrate under a WorldStateSwitch (visual only)"]),
		"expected exactly the GrayboxBlock error: %s" % v.errors)
	for path in SliceStats.room_paths():
		var shipped := ContentValidator.new().check_room(path)
		var bad := Array(shipped.errors).filter(func(e: String) -> bool: return e.contains("under a WorldStateSwitch"))
		check(bad.is_empty(), "%s: %s" % [path.get_file(), bad])


## M8: a NOTE map marker never points at a secret (bible §20).
func test_note_marker_secret_guard() -> void:
	var v := ContentValidator.new().check_room("res://tests/fixtures/scaffold_m8_note_bad.tscn", false)
	check(v.errors.size() == 1 and v.errors[0].begins_with("room scaffold_m8_note_bad: MapMarker1: NOTE 'Something here' is within 96 px"),
		"expected exactly one NOTE-near-secret error: %s" % v.errors)
