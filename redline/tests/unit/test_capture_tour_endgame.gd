extends RedlineTestCase
## --tour=endgame (M9 D6 §7.4, T14), headless, no rendering: the shot contract,
## the section methods, the --only parse, the TourSandbox round trip and the
## INSTANT cinematics rule.


func test_shot_names_unique_and_prefixed() -> void:
	var seen := {}
	for s in EndgameTour.SECTIONS:
		check(EndgameTour.SHOTS.has(s), "section %s has a shot list" % s)
		for n: String in EndgameTour.SHOTS.get(s, []):
			check(n.begins_with("eg_%s_" % s), "%s is prefixed eg_%s_" % [n, s])
			check(not seen.has(n), "%s is unique" % n)
			seen[n] = true
	check(seen.size() >= 45, "about 45 shots in total (%d)" % seen.size())


func test_every_section_has_a_method() -> void:
	var t := EndgameTour.new(self)
	for s in EndgameTour.SECTIONS:
		check(t.has_method("_section_" + s), "EndgameTour._section_%s exists" % s)


func test_only_arg_parses() -> void:
	check(EndgameTour.parse_only(PackedStringArray()) == EndgameTour.SECTIONS, "no --only: every section")
	check(EndgameTour.parse_only(PackedStringArray(["--out=/x", "--only=a,d"])) == PackedStringArray(["a", "d"]), "a subset")
	check(EndgameTour.parse_only(PackedStringArray(["--only=d,x,d, v"])) == PackedStringArray(["d", "v"]), "unknown and repeated letters dropped")
	var exp := EndgameTour.expected(PackedStringArray(["v"]))
	check(exp == PackedStringArray(EndgameTour.SHOTS["v"]), "expected() follows the selection")


func _paths() -> Dictionary:
	return {"save_dir": SaveManager.save_dir, "playtest": Playtest.dir, "platform": Platform.store_dir,
		"headless": Platform.allow_headless, "force_demo": BuildInfo.force_demo, "bypass": DemoGate.dev_bypass,
		"draw": DemoBarrier.debug_draw, "locale": Loc.locale(), "flag_missing": Loc.flag_missing,
		"demo_session": DemoDevActions.demo_session_on()}


func test_sandbox_redirects_and_restores_every_path() -> void:
	var before := _paths()
	var root := "user://test_tour_sandbox"
	var snap := TourSandbox.begin(root)
	check(SaveManager.save_dir.begins_with(root) and Playtest.dir.begins_with(root) and Platform.store_dir.begins_with(root),
		"saves, playtests and the platform store live in the sandbox")
	check(not BuildInfo.is_demo() and not DemoGate.dev_bypass and not DemoBarrier.debug_draw, "a full build, no bypass, no debug draw")
	check(Loc.locale() == Loc.SOURCE_LOCALE and not Loc.flag_missing, "English")
	# What the tour does inside: a demo session, pseudo-locale, a save.
	DemoDevActions.set_demo_session(true)
	LocaleDevActions.set_locale("en_XA")
	DemoGate.set_dev_bypass(true)
	Game.new_game()
	Game.save_game()
	TourSandbox.end(snap)
	var after := _paths()
	for k: String in before:
		check(after[k] == before[k], "%s restored (%s -> %s)" % [k, before[k], after[k]])
	Game.new_game()


func test_sandbox_leaves_no_files() -> void:
	var root := "user://test_tour_sandbox_files"
	var snap := TourSandbox.begin(root)
	Game.new_game()
	Game.save_game()
	check(DirAccess.dir_exists_absolute(root + "/saves"), "the save landed in the sandbox")
	TourSandbox.end(snap)
	check(not DirAccess.dir_exists_absolute(root), "the sandbox root is gone")
	Game.new_game()


func test_endgame_forces_instant() -> void:
	check(_capture_mode("endgame") == CinematicMode.Mode.INSTANT, "the endgame tour runs INSTANT cinematics")


func _capture_mode(tour: String) -> int:
	var script := load("res://devtools/CaptureTour.gd") as GDScript
	return int(script.call("tour_cinematic_mode", tour, PackedStringArray()))
