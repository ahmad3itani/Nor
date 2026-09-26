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


# --- M9 T14: cross-area rules (CrossRules X-1..X-10) and DM-4 -------------------------

func test_real_content_has_no_m9_errors() -> void:
	var v := _shipped_run()
	var m9 := Array(v.errors).filter(func(e: String) -> bool: return e.begins_with("["))
	check(m9.is_empty(), "no M9 rule errors on shipped content: %s" % [m9])
	var dm4 := Array(v.warnings).filter(func(w: String) -> bool: return w.begins_with("[DM-4]"))
	check(dm4.is_empty(), "demo.tres lists every achievement the demo can earn: %s" % [dm4])
	var demo := BuildInfo.config()
	check(demo != null and demo.achievements.size() >= 8, "the demo lists its Undercity achievements")
	for id in demo.achievements:
		check(String(DemoRules.last_earnable.get(id, "?")) == "", "%s is earnable in the demo" % id)
	check(not demo.achievements.has("top_marks"), "top_marks needs the training rig, which a demo never opens")


## Every M9 rule module prefixes its findings with the rule id.
func test_modules_prefix_rule_ids() -> void:
	var v := ContentValidator.new()
	var re := RegEx.create_from_string("^\\[[A-Z0-9]+-[0-9]+\\] ")
	v.validate_m9()
	for line in Array(v.errors) + Array(v.warnings):
		check(re.search(String(line)) != null, "prefixed with its rule id: %s" % line)
	var shipped := _shipped_run()
	for line in Array(shipped.errors) + Array(shipped.warnings):
		var s := String(line)
		if s.begins_with("["):
			check(re.search(s) != null, "prefixed with its rule id: %s" % s)


func _ach(id: String, conditions: PackedStringArray = PackedStringArray(), api := "") -> AchievementData:
	var a := AchievementData.new()
	a.id = id
	a.title = id
	a.conditions = conditions
	a.api_name = api
	return a


func test_x1_ids_and_api_names_unique_across_kinds() -> void:
	var st := StatDef.new()
	st.id = &"dup_stat"
	st.api_name = "SHARED_API"
	var out := CrossRules.id_errors_for([_ach("dup"), _ach("dup"), _ach("other", PackedStringArray(), "SHARED_API")], [st], [])
	check(_has(out, ["achievement id 'dup'"]), "a duplicate achievement id: %s" % out)
	check(_has(out, ["SHARED_API"]), "an api name shared by an achievement and a stat: %s" % out)
	check(CrossRules.id_errors().is_empty(), "shipped ids are unique: %s" % CrossRules.id_errors())


func test_x2_menu_ids_match() -> void:
	var main := FileAccess.get_file_as_string(CrossRules.MAIN_SCENE)
	check(CrossRules.menu_errors(MenuHost.IDS, ContentValidator.MENU_IDS, main).is_empty(), "shipped menu ids match")
	var extra := PackedStringArray(MenuHost.IDS)
	extra.append("ghost_menu")
	var out := CrossRules.menu_errors(extra, ContentValidator.MENU_IDS, main)
	check(_has(out, ["ghost_menu", "not ContentValidator.MENU_IDS"]) and _has(out, ["ghost_menu", "no screen"]), "%s" % out)
	check(_has(CrossRules.menu_errors(MenuHost.IDS, ContentValidator.MENU_IDS, ""), ["Main.tscn has no Menus/PauseMenu"]), "a missing Menus node")


func test_x3_unrecorded_signal_fails() -> void:
	var bus := "signal a_done(x: int)\nsignal b_seen\nsignal c_quiet\n"
	var pt := "EventBus.a_done.connect(_on_a)\n"
	var out := CrossRules.unrecorded_signals(bus, pt, {"c_quiet": "presentation only"})
	check(out.size() == 1 and out[0].contains("EventBus.b_seen"), "only the unlisted, unrecorded signal: %s" % out)
	check(_has(CrossRules.unrecorded_signals(bus, pt, {"b_seen": " ", "c_quiet": "x"}), ["needs a one-line reason"]), "an empty reason fails")


func test_x4_network_class_fails() -> void:
	check(not CrossRules.scan_network("var r := HTTPRequest.new()").is_empty(), "HTTPRequest")
	check(not CrossRules.scan_network("\tOS.shell_open(url)").is_empty(), "OS.shell_open")
	check(not CrossRules.scan_network("var s = Engine.get_singleton(\"Steam\")").is_empty(), "the storefront singleton")
	check(not CrossRules.scan_network("JavaScriptBridge.eval(x)").is_empty(), "JavaScriptBridge")
	check(CrossRules.scan_network("# HTTPRequest in a comment\nvar p := [\"HTTPRequest\", \"Steam.\"]").is_empty(), "comments and strings are not calls")
	check(not CrossRules.scan_network("var p := WebRTCPeerConnection.new()").is_empty(), "WebRTC")
	check(not CrossRules.scan_network("var d := PacketPeerDTLS.new()").is_empty(), "DTLS")
	check(not CrossRules.scan_network("OS.execute(\"curl\", [url])").is_empty(), "OS.execute outside tests")
	check(not CrossRules.scan_network("OS.create_process(\"curl\", [])").is_empty(), "OS.create_process")
	check(CrossRules.scan_network("OS.execute(\"sh\", [])", true).is_empty(), "tests may run the generators")
	check(not CrossRules.scan_network("var r = ClassDB.instantiate(\"HTTPRequest\")").is_empty(), "ClassDB.instantiate of a network class")
	check(CrossRules.scan_network("var r = ClassDB.instantiate(\"Node2D\")").is_empty(), "ClassDB.instantiate of a plain class passes")
	check(not CrossRules.scan_network_resource("[node name=\"Net\" type=\"HTTPRequest\" parent=\".\"]").is_empty(), "a network node in a scene")
	check(not CrossRules.scan_network_resource("[sub_resource type=\"GDScript\" id=\"x\"]").is_empty(), "an embedded script")
	check(CrossRules.scan_network_resource("[node name=\"A\" type=\"Area2D\" parent=\".\"]").is_empty(), "a plain node passes")
	check(CrossRules.network_violations().is_empty(), "the whole project is clean: %s" % CrossRules.network_violations())


func test_x5_raw_scan_fails_and_datadir_passes() -> void:
	check(not CrossRules.scan_raw("res://ui/Foo.gd", "for f in DirAccess.get_files_at(dir):").is_empty(), "a raw scan in ui/")
	check(CrossRules.scan_raw("res://ui/Foo.gd", "for f in DataDir.list(dir):").is_empty(), "DataDir passes")
	check(CrossRules.scan_raw("res://progression/DataDir.gd", "DirAccess.get_files_at(dir)").is_empty(), "the allowlist passes")
	check(CrossRules.raw_scan_violations().is_empty(), "shipped scripts: %s" % CrossRules.raw_scan_violations())


func test_x6_unscanned_folder_fails() -> void:
	var out := CrossRules.unscanned_dirs(PackedStringArray(["res://ui", "res://locale", "res://newthing"]))
	check(out.size() == 1 and out[0].contains("res://newthing"), "only the unknown folder: %s" % out)
	check(CrossRules.unscanned_dirs(CrossRules.top_level_dirs()).is_empty(), "every shipped folder is scanned or ignored")


func test_x7_readers_registered() -> void:
	var v := ContentValidator.new()
	var out := CrossRules.unregistered_readers(v)
	check(not out.is_empty(), "an empty flag graph has unregistered readers")
	var shipped := _shipped_run()
	check(CrossRules.unregistered_readers(shipped).is_empty(), "shipped readers are registered: %s" % CrossRules.unregistered_readers(shipped))
	check(CrossRules.condition_flags(["flag:a", "!flag:b", "count:secrets:3", ""]) == PackedStringArray(["a", "b"]), "condition flags")


func test_x8_shaming_words_fail() -> void:
	var cat := load(SettingsCatalog.PATH) as SettingsCatalog
	var out := CrossRules.shaming_text([["data/challenges/x.tres", "The easy route for beginners"]], cat)
	check(_has(out, ["'easy'"]), "a forbidden word: %s" % out)
	check(CrossRules.shaming_text([["x", "Assists never lock content."]], cat).is_empty(), "neutral text passes")
	var m9 := CrossRules.m9_catalog_text(PoFile.load_file(CrossRules.POT_PATH))
	check(m9.size() > 100, "the M9 part of the catalog is read (%d)" % m9.size())


func test_x9_knowledge_lint_reads_m9_text() -> void:
	var v := ContentValidator.new()
	var out := CrossRules.knowledge_warnings(v, [["res://data/achievements/fx.tres", "achievement fx title", "Into The Null"],
		["res://world/rooms/challenge/fx.tres", "challenge fx", "The Null"]])
	check(out.size() == 1 and out[0].begins_with("knowledge lint") and out[0].contains("fx.tres"), "one warning, the exempt dir skipped: %s" % out)
	var items := CrossRules.add_m9_shown_text(v)
	check(items.size() > 60 and v.extra_shown_text.size() == items.size(), "achievement, challenge and demo lines registered")


func test_x10_code_flags_known() -> void:
	var v := ContentValidator.new()
	var out := CrossRules.unproduced_code_flags(v)
	check(_has(out, ["ng_cycle"]), "an unproduced NG+ flag: %s" % out)
	for f in ["ng_cycle", "ng_remix", "ng_keep_dash"]:
		v.add_producer(f, "res://data/ngplus/ng_plus.tres")
	check(CrossRules.unproduced_code_flags(v).is_empty(), "produced by data: %s" % CrossRules.unproduced_code_flags(v))


func test_dm4_unearnable_demo_achievement() -> void:
	var c := (BuildInfo.config() as DemoConfig).duplicate(true) as DemoConfig
	var v := ContentValidator.new()
	v.add_producer("warden_krail_defeated", "res://world/rooms/lowlight/WardenTower.tscn")
	v.add_producer("fx_uc_done", "res://world/rooms/undercity/Wake.tscn")
	var krail := _ach("fx_krail", PackedStringArray(["flag:warden_krail_defeated"]))
	var uc := _ach("fx_uc", PackedStringArray(["flag:fx_uc_done"]))
	c.achievements = PackedStringArray(["fx_krail", "fx_missing"])
	var r := DemoRules.achievement_check(c, v, [krail, uc] as Array[AchievementData], DemoRules.scope(c), "fx_demo.tres")
	check(_has(r["errors"], ["[DM-4]", "fx_krail", "cannot be earned"]), "a Lowlight flag is unearnable: %s" % r["errors"])
	check(_has(r["errors"], ["[DM-4]", "fx_missing", "does not exist"]), "an unknown id: %s" % r["errors"])
	check(_has(r["warnings"], ["[DM-4]", "fx_uc", "add it to demo.tres"]), "earnable but unlisted warns: %s" % r["warnings"])
	# A style-rank target without STYLE_EVIDENCE is not promised by a demo.
	var style := _ach("fx_style")
	style.stat_id = AchievementRules.RANK_STAT
	style.stat_target = 99
	c.achievements = PackedStringArray(["fx_style"])
	r = DemoRules.achievement_check(c, v, [style] as Array[AchievementData], DemoRules.scope(c), "fx_demo.tres")
	check(_has(r["errors"], ["[DM-4]", "fx_style", "style rank 99"]), "an unproven style rank is unearnable: %s" % r["errors"])
