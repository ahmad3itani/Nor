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


# --- M8 T10: cross-area story rules, knowledge lint, the Story report ----------

## The full shipped pass, run once for the tests that read it.
static var _shipped: ContentValidator = null


func _shipped_run() -> ContentValidator:
	if _shipped == null:
		_shipped = ContentValidator.new().run()
	return _shipped


func _has(list: PackedStringArray, needles: Array) -> bool:
	return Array(list).any(func(e: String) -> bool: return needles.all(func(n: String) -> bool: return e.contains(n)))


func _knowledge(list: PackedStringArray) -> Array:
	return Array(list).filter(func(w: String) -> bool: return w.begins_with("knowledge lint"))


func _line(text: String) -> DialogueLine:
	var l := DialogueLine.new()
	l.text = text
	return l


func test_future_flag_rules() -> void:
	var v := ContentValidator.new()
	v.check_resource(FutureFlagSet.shared(), FutureFlagSet.PATH)
	# A room switch reading a future flag (Act I content must never read one).
	var room := (load("res://tests/fixtures/WorldA.tscn") as PackedScene).instantiate() as Room
	var sw := WorldStateSwitch.new()
	sw.name = "FutureSwitch"
	sw.visible_when = "flag:act5_finale_reached"
	room.add_child(sw)
	v._check_world_room(room, "res://tests/fixtures/WorldA.tscn", {})
	room.free()
	# Real content producing a future flag: found through `producers`, although
	# `produced` keeps the first producer (future_flags.tres).
	var d := DialogueData.new()
	d.id = "test_future_setter"
	d.lines = [_line("Choose.")] as Array[DialogueLine]
	d.set_flags = PackedStringArray(["finale_choice_sever"])
	v.check_resource(d, "res://data/test/x.tres")
	check(v.produced.get("finale_choice_sever") == "future_flags.tres", "produced keeps the declaration first: %s" % v.produced.get("finale_choice_sever"))
	v.validate_story()
	check(_has(v.errors, ["act5_finale_reached", "WorldA.tscn", "read by"]), "a room reading a future flag is an error: %s" % v.errors)
	check(_has(v.errors, ["finale_choice_sever", "res://data/test/x.tres", "remove it from future_flags.tres"]),
		"a second producer of a future flag is an error: %s" % v.errors)
	# Shipped content: clean, and one summary warning.
	var shipped := _shipped_run()
	check(shipped.errors.is_empty(), "shipped content has errors: %s" % shipped.errors)
	var summary := Array(shipped.warnings).filter(func(w: String) -> bool: return w.contains("future flags declared"))
	check(summary.size() == 1 and String(summary[0]).begins_with("%d future flags declared (Acts II-V/M9)" % FutureFlagSet.shared().flags().size()),
		"exactly one future-flag summary warning: %s" % [summary])


func test_memory_cross_checks() -> void:
	var v := ContentValidator.new()
	var lonely := MemoryFragmentData.new()
	lonely.id = "mf_test_lonely"
	lonely.title = "Lonely"
	lonely.text = "Nobody remembers this one."
	v.check_resource(lonely, "res://data/lore/mf_test_lonely.tres")
	for i in 2:
		var sc := MemorySceneData.new()
		sc.id = "mem_test_slot_%d" % i
		sc.source = MemorySceneData.Source.SURFACED
		sc.title = "Slot %d" % i
		sc.act = 1
		sc.timeline_slot = 9900
		v.check_resource(sc, "res://data/memories/mem_test_slot_%d.tres" % i)
	v.validate_story()
	check(_has(v.errors, ["mf_test_lonely", "0 memory scenes"]), "a fragment without a scene is an error: %s" % v.errors)
	check(_has(v.errors, ["timeline_slot 9900 is already used by mem_test_slot_0"]), "a duplicate timeline_slot is an error: %s" % v.errors)
	# A mem_seen_ read for a scene that does not exist.
	v._consume("mem_seen_nowhere", "res://data/test/y.tres")
	v.validate_story()
	check(_has(v.errors, ["mem_seen_nowhere", "no memory scene"]), "mem_seen_<id> must name a scene: %s" % v.errors)


func test_knowledge_lint_warns() -> void:
	var v := ContentValidator.new()
	var d := DialogueData.new()
	d.id = "test_lint"
	d.lines = [_line("The Null is down there."), _line("Maybe the Pulse is listening."), _line("Old research notes."),
		_line("Wake up, Rook.")] as Array[DialogueLine]
	v.check_resource(d, "res://data/npcs/test_lint.tres")
	var exempt := d.duplicate(true) as DialogueData
	v.check_resource(exempt, "res://data/endings/test_lint.tres")
	v.validate_story()
	var found := _knowledge(v.warnings)
	for term in ["The Null", "Pulse is", "research", "Rook"]:
		check(found.any(func(w: String) -> bool: return w.contains("test_lint.tres") and w.contains("'%s'" % term)), "'%s' warns: %s" % [term, found])
	check(found.size() == 4, "one warning per hit, none from data/endings: %s" % [found])
	check(not _has(v.errors, ["knowledge"]), "the knowledge lint never errors")
	# Shipped: exactly one, orr.tres 'Rook' (D-109 open; update this test when
	# D-109 decides who names him).
	var shipped := _knowledge(_shipped_run().warnings)
	check(shipped.size() == 1 and String(shipped[0]).contains("orr.tres") and String(shipped[0]).contains("'Rook'"),
		"shipped knowledge warnings must be exactly orr.tres 'Rook': %s" % [shipped])


## Map labels, arc journal notes and speaker labels are shown text too
## (D-132 as built: the lint reads every player-visible Act I string).
func test_knowledge_lint_reads_notes_journal_and_speakers() -> void:
	var v := ContentValidator.new()
	var room := (load("res://tests/fixtures/WorldA.tscn") as PackedScene).instantiate() as Room
	var note := MapMarker.new()
	note.name = "LintNote"
	note.kind = MapMarker.Kind.NOTE
	note.label = "Nix: harvest rumour"
	room.add_child(note)
	v._check_world_room(room, "res://tests/fixtures/WorldA.tscn", {})
	room.free()
	var arc := NpcArc.new()
	arc.npc_id = "lint_arc"
	var st := NpcArcStage.new()
	st.id = "met"
	st.journal_note = "Mechanic. Knows the Architect."
	arc.stages = [st] as Array[NpcArcStage]
	v.check_resource(arc, "res://data/arcs/lint_arc.tres")
	var d := DialogueData.new()
	d.id = "test_lint_speaker"
	var l := _line("Hello.")
	l.speaker = "The Null"
	d.lines = [l] as Array[DialogueLine]
	v.check_resource(d, "res://data/npcs/test_lint_speaker.tres")
	v.validate_story()
	var found := _knowledge(v.warnings)
	check(found.any(func(w: String) -> bool: return w.contains("WorldA.tscn") and w.contains("map note LintNote") and w.contains("'harvest'")),
		"a NOTE label is linted: %s" % [found])
	check(found.any(func(w: String) -> bool: return w.contains("lint_arc.tres") and w.contains("journal note") and w.contains("'Architect'")),
		"an arc journal note is linted: %s" % [found])
	check(found.any(func(w: String) -> bool: return w.contains("test_lint_speaker.tres") and w.contains("speaker") and w.contains("'The Null'")),
		"a speaker label is linted: %s" % [found])


func test_story_report_section() -> void:
	var md := _shipped_run().report()
	check(md.contains("## Story"), "report has a Story section")
	for section in ["### Sequences", "### Memories", "### Arcs", "### Endings", "### Act I card", "### Future flags"]:
		check(md.contains(section), "Story section has %s" % section)
	for id in ContentValidator.ENDING_IDS:
		var rows := Array(md.split("\n")).filter(func(l: String) -> bool: return l.begins_with("| %s |" % id) and l.contains("reachable now: no"))
		check(rows.size() == 1, "ending %s has one 'reachable now: no' row" % id)
	check(md.contains("flag:finale_choice_sever (Act 5)"), "future flags tagged with their act")
	check(md.contains("flag:act5_finale_reached (Act 5)") and not md.contains("(Act 9)"), "a future flag reads with its act")
	check(md.contains("| act5_finale_reached | Act 5 |") and not md.contains("| null_depth_reached |"), "future-flag table shows act5_finale_reached, not null_depth_reached")
	check(_shipped_run().produced.has("null_depth_reached"), "null_depth_reached is produced (the Deep Rig's on_finish_flags, D-154)")
