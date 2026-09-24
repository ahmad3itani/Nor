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
