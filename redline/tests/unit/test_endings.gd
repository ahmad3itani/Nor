extends RedlineTestCase
## M8 endings (T06): EndingData / EndingResolver / EndingDirector, the
## future-flag gate that keeps every ending out of Act I (D-127), the theatre
## sandbox (D-128), the credits roll, the placeholder text rule (D-137) and
## the Act I card (ActData / ActLibrary / SliceEndMenu, D-131).

const IDS := ["sever", "crown", "release", "redline"]
const SAVE_V3 := "res://tests/fixtures/save_v3_slice.json"
const SAVE_DIR := "user://test_endings"
const PLAYTEST_DIR := "user://test_endings_playtest"
const LEDGER_LINE := "Krail's ledger says REDLINE too. Nobody will say what it means."
const FALLBACK_LINE := "The Spire has lost a Warden. It will send someone to ask why."
const HEADER := "ACT I COMPLETE  —  RUN"
const ALLOWED_SPEAKERS := ["", "orr", "mara", "nix", "vell"]
## The binding ending text (plan T06): [speaker, text, only_when] in order.
const TEXT := {
	"sever": [
		["", "You tear the network down.", ""],
		["", "The lights go out district by district, all the way up the Spire.", ""],
		["orr", "Every band's dead. Quietest night Lowlight ever had.", "atleast:arc_orr_stage:1"],
		["mara", "No lights, no Spire. We'll see what people build in the dark.", "atleast:arc_mara_stage:1"],
	],
	"crown": [
		["", "You take hold of the network. Every light in Veyra steadies at once.", ""],
		["", "The city runs through you now.", ""],
		["nix", "The map redraws itself every morning now. I don't touch it.", "atleast:arc_nix_stage:1"],
	],
	"release": [
		["", "You don't pull and you don't hold. You change it.", ""],
		["", "The lights stay on.", ""],
		["", "Three short. Three long. This time the tapping finishes.", "flag:mem_seen_mf_lowlight_04"],
		["mara", "You came back. That's new.", "atleast:arc_mara_stage:1"],
		["vell", "Relay's full. First time I've had to turn the heat up.", "atleast:arc_vell_stage:1"],
	],
	"redline": [
		["", "Static on every band at once.", ""],
		["", "Then everything goes red, and quiet.", ""],
	],
}

var _snap: Dictionary
var _extras: Array[Node] = []
## [id, theatre]
var started: Array = []
## [id, theatre, skipped]
var finished: Array = []
## [index, label]
var steps_seen: Array = []


func before_each() -> void:
	_snap = use_default_m8_settings()
	get_tree().paused = false
	CinematicMode.teardown()
	Cinematics.overlay.clear_all()
	Game.new_game()
	for a: Array in [started, finished, steps_seen]:
		a.clear()
	EventBus.ending_started.connect(_on_started)
	EventBus.ending_finished.connect(_on_finished)
	Cinematics.step_started.connect(_on_step)


func after_each() -> void:
	EventBus.ending_started.disconnect(_on_started)
	EventBus.ending_finished.disconnect(_on_finished)
	Cinematics.step_started.disconnect(_on_step)
	CinematicMode.teardown()
	Cinematics.overlay.clear_all()
	for n in _extras:
		if is_instance_valid(n):
			n.queue_free()
	_extras.clear()
	get_tree().paused = false
	SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR
	_clean(SAVE_DIR)
	restore_m8_settings(_snap)
	Game.new_game()


func _on_started(id: String, theatre: bool) -> void:
	started.append([id, theatre])


func _on_finished(id: String, theatre: bool, skipped: bool) -> void:
	finished.append([id, theatre, skipped])


func _on_step(index: int, label: String) -> void:
	steps_seen.append([index, label])


func _clean(dir: String) -> void:
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute("%s/%s" % [dir, f])


## Every condition of `e` made true (flags true, atleast:x:n -> n, !flag:x -> false).
func _satisfy(e: EndingData) -> void:
	for c in e.all_conditions():
		if c.begins_with("!flag:"):
			Game.set_flag(c.get_slice(":", 1), false)
		elif c.begins_with("flag:"):
			Game.set_flag(c.get_slice(":", 1), true)
		elif c.begins_with("atleast:"):
			Game.set_flag(c.get_slice(":", 1), c.get_slice(":", 2).to_int())
		else:
			check(false, "%s: cannot satisfy '%s'" % [e.id, c])


func _ids(list: Array[EndingData]) -> Array:
	return list.map(func(e: EndingData) -> String: return e.id)


func _load_v3() -> void:
	SaveManager.save_dir = SAVE_DIR
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open("%s/profile_1.json" % SAVE_DIR, FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(SAVE_V3))
	f.close()
	check(Game.load_game(1), "the v3 fixture loads")


func _wait_finished(id: String, max_frames: int) -> bool:
	for i in max_frames:
		if finished.any(func(r: Array) -> bool: return r[0] == id):
			return true
		await get_tree().process_frame
	return finished.any(func(r: Array) -> bool: return r[0] == id)


func _labels(m: MenuScreen) -> PackedStringArray:
	var out := PackedStringArray()
	for c in m._body.get_children():
		if c is Label and not c.is_queued_for_deletion():
			out.append((c as Label).text)
	return out


# --- Data ------------------------------------------------------------------------

func test_four_endings_exist() -> void:
	var ids := _ids(EndingResolver.all())
	var sorted := ids.duplicate()
	sorted.sort()
	var want := IDS.duplicate()
	want.sort()
	check(sorted == want, "endings are exactly %s (got %s)" % [want, ids])
	var hidden := EndingResolver.all().filter(func(e: EndingData) -> bool: return e.hidden)
	check(hidden.size() == 1 and hidden[0].id == "redline", "only redline is hidden")
	check(ids == ["redline", "release", "crown", "sever"], "priority order redline > release > crown = sever (by id): %s" % [ids])
	for e in EndingResolver.all():
		check(e.validate().is_empty(), "%s validate: %s" % [e.id, e.validate()])
		check(e.content_check().is_empty(), "%s content_check: %s" % [e.id, e.content_check()])
		check(e.seen_flag() == "ending_seen_%s" % e.id, "%s seen flag" % e.id)


func test_every_ending_needs_a_future_flag() -> void:
	var future := FutureFlagSet.shared()
	# D-154: null_depth_reached is produced by the Deep Rig (data/challenges),
	# so it left the future list; the redline ending still needs Act V.
	check(future.flags().size() == 8, "eight future flags declared (%d)" % future.flags().size())
	check(not future.has_flag("null_depth_reached"), "null_depth_reached is no longer a future flag")
	check(future.validate().is_empty(), "future_flags.tres validates: %s" % future.validate())
	for e in EndingResolver.all():
		var hits := Array(e.all_conditions()).filter(func(c: String) -> bool: return future.is_future_condition(c))
		check(not hits.is_empty(), "%s reads a future flag: %s" % [e.id, e.all_conditions()])
	# The lint catches an ending that loses its gate.
	var bad := EndingResolver.by_id("sever").duplicate() as EndingData
	bad.choice_condition = "flag:warden_krail_defeated"
	bad.requires = PackedStringArray()
	check(Array(bad.content_check()).any(func(m: String) -> bool: return m.contains("reachable in the built acts")),
		"an ending without a future flag is an error: %s" % bad.content_check())
	check(future.planned_memories == 24 and int(future.planned_arc_stages.get("arc_orr_stage", 0)) == 6 \
		and int(future.planned_arc_stages.get("arc_iko_stage", 0)) == 5, "planned bounds (D-129)")


func test_unreachable_in_act1_max_state() -> void:
	DevActions.unlock_all()
	for f in ["transit_pass", "map_lens", "injector_upgrades"]:
		check(typeof(Game.state.flags.get(f)) == TYPE_INT and Game.flag_int(f) == 1, "unlock_all set %s to int 1" % f)
	FlagSandbox.apply_act1_max_state()
	for f in ["transit_pass", "map_lens", "injector_upgrades"]:
		check(typeof(Game.state.flags.get(f)) == TYPE_INT and Game.flag_int(f) == 1, "%s stays int 1 (%s)" % [f, Game.state.flags.get(f)])
	check(typeof(Game.state.flags.get("memories_remembered")) == TYPE_INT and Game.flag_int("memories_remembered") == 6,
		"memories_remembered == 6 (%s)" % Game.state.flags.get("memories_remembered"))
	for a in Game.arcs.arcs:
		var v: Variant = Game.state.flags.get(a.index_flag())
		check(typeof(v) == TYPE_INT and int(v) == a.stages.size(), "%s at its Act I top %d (%s)" % [a.index_flag(), a.stages.size(), v])
	for s in MemoryLibrary.all_scenes():
		check(MemoryLibrary.is_seen(s.id), "%s remembered" % s.id)
	check(Game.has_flag("act1_complete") and Game.has_flag("read_uc_intake_log") and Game.has_flag("mem_seen_mf_lowlight_03"),
		"the Act I seeds of the endings are set")
	for f in FutureFlagSet.shared().flags():
		check(not Game.state.flags.has(f), "future flag %s untouched" % f)
	check(EndingResolver.offered().is_empty(), "nothing offered: %s" % [_ids(EndingResolver.offered())])
	check(EndingResolver.resolve() == null, "nothing resolves")


func test_unreachable_from_v3_fixture() -> void:
	_load_v3()
	check(Game.has_flag("warden_krail_defeated"), "fixture passed Krail")
	check(EndingResolver.offered().is_empty(), "nothing offered from the M7 save")
	check(EndingResolver.resolve() == null, "nothing resolves from the M7 save")


func test_each_ending_reachable_when_satisfied() -> void:
	for id: String in IDS:
		var e := EndingResolver.by_id(id)
		var restore := FlagSandbox.begin()
		_satisfy(e)
		check(EndingResolver.offered().has(e), "%s offered when satisfied" % id)
		var r := EndingResolver.resolve()
		check(r != null and r.id == id, "%s resolves (got %s)" % [id, r.id if r else "null"])
		restore.call()
		check(EndingResolver.resolve() == null, "after the sandbox restore nothing resolves (%s)" % id)
		check(not Game.has_flag("act5_finale_reached"), "sandbox put the flags back (%s)" % id)


func test_priority_when_several_choices_set() -> void:
	_satisfy(EndingResolver.by_id("release"))
	_satisfy(EndingResolver.by_id("sever"))
	var r := EndingResolver.resolve()
	check(r != null and r.id == "release", "release beats sever (got %s)" % (r.id if r else "null"))
	_satisfy(EndingResolver.by_id("redline"))
	r = EndingResolver.resolve()
	check(r != null and r.id == "redline", "redline beats release (got %s)" % (r.id if r else "null"))


func test_release_needs_memories_and_arcs() -> void:
	var e := EndingResolver.by_id("release")
	_satisfy(e)
	check(EndingResolver.offered().has(e), "release offered when satisfied")
	Game.set_flag("memories_remembered", 23)
	check(not EndingResolver.offered().has(e), "23 memories -> not offered")
	Game.set_flag("memories_remembered", 24)
	check(EndingResolver.offered().has(e), "24 memories -> offered again")
	Game.set_flag("arc_orr_stage", 4)
	check(not EndingResolver.offered().has(e), "arc_orr_stage 4 -> not offered")
	check(EndingResolver.resolve() == null, "and nothing resolves")


func test_hidden_not_offered_without_requirements() -> void:
	Game.set_flag("act5_finale_reached")
	Game.set_flag("finale_choice_redline")
	var ids := _ids(EndingResolver.offered())
	check(not ids.has("redline"), "redline needs more than the choice: %s" % [ids])
	check(ids.has("sever") and ids.has("crown"), "sever and crown are offered at the finale: %s" % [ids])
	check(EndingResolver.resolve() == null, "the redline choice alone resolves nothing")
	var groups := EndingResolver.explain(EndingResolver.by_id("redline")).map(func(d: Dictionary) -> String: return d["group"])
	check(groups.has("Choice") and groups.has("Story") and groups.has("Memories"), "explain groups: %s" % [groups])


# --- Director ----------------------------------------------------------------------

func test_theatre_leaves_profile_untouched() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.INSTANT)
	Game.set_flag("met_orr")
	var before := Game.state.to_dict()
	var opened := FlagSandbox.begin_count
	var e := EndingResolver.by_id("release")
	var res: SequenceResult = await EndingDirector.new().play(e, true)
	check(not res.refused and not res.aborted(), "theatre play ran")
	check(Game.state.to_dict() == before, "the profile is unchanged after a theatre play")
	check(not Game.has_flag("ending_seen_release"), "ending_seen_release not set by the theatre")
	check(started == [["release", true]], "ending_started(theatre=true): %s" % [started])
	check(finished.size() == 1 and finished[0][0] == "release" and finished[0][1] == true, "ending_finished(theatre=true): %s" % [finished])
	check(not CinematicMode.theatre, "CinematicMode.theatre cleared")
	check(FlagSandbox.begin_count == opened + 1, "the theatre play took one sandbox")
	# A real play takes no snapshot and keeps its seen flag.
	opened = FlagSandbox.begin_count
	res = await EndingDirector.new().play(e, false)
	check(not res.refused and not res.aborted(), "real play ran")
	check(FlagSandbox.begin_count == opened, "a real play takes no sandbox")
	check(Game.has_flag("ending_seen_release"), "a real play marks ending_seen_release")
	check(finished.size() == 2 and finished[1][1] == false, "ending_finished(theatre=false): %s" % [finished])
	check(EndingDirector.running_count() == 0, "no director left running")


func test_real_play_marks_seen_even_when_skipped() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.AUTO)
	CinematicMode.auto_speed = 1.0
	var e := EndingResolver.by_id("crown")
	var results: Array = []
	var run := func() -> void:
		results.append(await EndingDirector.new().play(e, false))
	run.call()
	for i in 10:
		await get_tree().process_frame
	check(Cinematics.is_playing() and Cinematics.locks_input(), "the ending is playing and locking")
	Cinematics.request_skip()
	for i in 30:
		if not results.is_empty():
			break
		await get_tree().process_frame
	check(results.size() == 1, "the play returned after the skip")
	check(Game.has_flag("ending_seen_crown"), "ending_seen_crown set by a skip")
	check(finished.size() == 1 and finished[0] == ["crown", false, true], "ending_finished skipped=true: %s" % [finished])
	for i in 3:
		await get_tree().process_frame
	check(not Cinematics.is_playing(), "nothing playing")
	check(Cinematics.overlay.is_idle(), "the overlay is idle (credits roll freed)")
	check(not CinematicMode.hud_hidden, "the HUD is back")
	check(MusicDirector._override == -1, "the music override is cleared")
	check(not CinematicMode.theatre, "theatre stays off")


func test_ending_sequences_overlay_only_and_budget() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.INSTANT)
	for e in EndingResolver.all():
		var s := e.sequence
		check(s != null and s.id == "ending_%s" % e.id, "%s has its sequence" % e.id)
		if s == null:
			continue
		check(s.content_check().is_empty(), "%s sequence lint: %s" % [e.id, s.content_check()])
		var credits := s.steps.filter(func(st: SequenceStep) -> bool: return st is SeqCredits)
		check(credits.size() == 1 and (credits[0] as SeqCredits).nominal_seconds() <= 60.0,
			"%s: one SeqCredits within 60 s" % e.id)
		check(s.nominal_seconds(true) <= 90.0, "%s within 90 s (%.1f)" % [e.id, s.nominal_seconds(true)])
		var res: SequenceResult = await Cinematics.play(s, SequenceContext.for_overlay(null))
		check(not res.refused and not res.aborted(), "%s plays under for_overlay(null)" % e.id)
	# The lint catches an actor step and a missing credits roll (in-memory
	# resources: the shipped ones are shared and never mutated).
	var sever := EndingResolver.by_id("sever")
	var bad := EndingData.new()
	bad.id = "sever"
	bad.title = "SEVER"
	bad.choice_condition = sever.choice_condition
	bad.requires = sever.requires
	var seq := SequenceData.new()
	seq.id = "ending_bad"
	seq.theatre_only = true
	seq.seen_flag = "ending_seen_sever"
	var steps: Array[SequenceStep] = [sever.sequence.steps[0], SeqCamera.new()]
	seq.steps = steps
	bad.sequence = seq
	var msgs := "\n".join(bad.content_check())
	check(msgs.contains("SeqCamera") and msgs.contains("last blocking step must be SeqCredits"), "overlay-only lint: %s" % msgs)
	var credits_data := load("res://data/endings/credits.tres") as CreditsData
	check(credits_data.validate().is_empty(), "credits validate: %s" % credits_data.validate())
	var no_engine := CreditsData.new()
	var sections: Array[CreditsSection] = [credits_data.sections[0]]
	no_engine.sections = sections
	check(not no_engine.validate().is_empty(), "credits without the ENGINE notice are an error")


func test_epilogue_lines_follow_arcs() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.AUTO)
	CinematicMode.auto_speed = 16.0
	var e := EndingResolver.by_id("release")
	var mara := -1
	for i in e.sequence.steps.size():
		var st := e.sequence.steps[i]
		if st is SeqLine and (st as SeqLine).speaker_id == "mara":
			mara = i
	check(mara >= 0, "release has a mara line")
	for stage in [0, 1]:
		Game.set_flag("arc_mara_stage", stage)
		steps_seen.clear()
		finished.clear()
		EndingDirector.new().play(e, true)
		check(await _wait_finished("release", 900), "release finished (arc_mara_stage %d)" % stage)
		var hit := steps_seen.any(func(r: Array) -> bool: return r[0] == mara)
		check(hit == (stage == 1), "mara line started == %s at arc_mara_stage %d" % [stage == 1, stage])
		check(Game.flag_int("arc_mara_stage") == stage, "the theatre kept arc_mara_stage %d" % stage)


func test_ending_text_is_paraphrase_only() -> void:
	for id: String in IDS:
		var seq := load("res://data/sequences/ending_%s.tres" % id) as SequenceData
		var got: Array = []
		for st in seq.steps:
			if st is SeqLine:
				var l := st as SeqLine
				got.append([l.speaker_id, l.text, l.only_when])
				check(ALLOWED_SPEAKERS.has(l.speaker_id), "%s: speaker '%s' not allowed in endings" % [id, l.speaker_id])
			if st is SeqTitleCard:
				check((st as SeqTitleCard).subtitle == "PLACEHOLDER ENDING", "%s title card says PLACEHOLDER ENDING" % id)
		check(got == TEXT[id], "%s lines equal the binding text:\n%s" % [id, got])


func test_fire_and_forget_director_completes() -> void:
	CinematicMode.set_mode(CinematicMode.Mode.AUTO)
	CinematicMode.auto_speed = 8.0
	Game.set_flag("met_nix")
	var before: Dictionary = Game.state.flags.duplicate(true)
	EndingDirector.new().play(EndingResolver.by_id("crown"), true)
	check(EndingDirector.running_count() == 1, "the director retains itself while playing")
	check(await _wait_finished("crown", 900), "ending_finished emitted without a reference or await")
	check(not CinematicMode.theatre, "theatre back to false")
	check(Game.state.flags == before, "flags equal the pre-play snapshot")
	check(EndingDirector.running_count() == 0, "_running is empty afterwards")


# --- Act I card --------------------------------------------------------------------

func test_act1_card_header_and_standing() -> void:
	var act := ActLibrary.act(1)
	check(act != null and act.name == "RUN" and act.complete_flag == "act1_complete" and act.max_standing == 3, "act1.tres")
	check(act.content_check().is_empty(), "act1 lint: %s" % act.content_check())
	check(act.standing[3].text == LEDGER_LINE, "the ledger line: %s" % act.standing[3].text)
	check(act.standing[-1].condition == "" and act.standing[-1].text == FALLBACK_LINE, "the fallback line is last")
	# Nothing passes but the dead_air pair's negative side: that line + fallback.
	var lines := ActLibrary.standing_lines(act)
	check(lines.size() == 2 and lines[0].begins_with("Half of Orr's board") and lines[1] == FALLBACK_LINE, "fresh card: %s" % lines)
	# Everything passes: never more than 3, the fallback always, one side of the pair.
	FlagSandbox.apply_act1_max_state()
	lines = ActLibrary.standing_lines(act)
	check(lines.size() <= 3 and lines[-1] == FALLBACK_LINE, "max card: %s" % lines)
	var pos := Array(lines).filter(func(l: String) -> bool: return l.begins_with("Orr's board hears")).size()
	var neg := Array(lines).filter(func(l: String) -> bool: return l.begins_with("Half of Orr's board")).size()
	check(pos == 1 and neg == 0, "dead_air complete shows only its line: %s" % lines)
	# Written directly: QuestTracker re-derives dead_air_complete from its
	# stage flags on flag_changed, so set_flag(false) would not stick here.
	Game.state.flags["dead_air_complete"] = false
	lines = ActLibrary.standing_lines(act)
	pos = Array(lines).filter(func(l: String) -> bool: return l.begins_with("Orr's board hears")).size()
	neg = Array(lines).filter(func(l: String) -> bool: return l.begins_with("Half of Orr's board")).size()
	check(pos == 0 and neg == 1, "dead_air unfinished shows only its line: %s" % lines)
	Game.state.flags["dead_air_complete"] = true
	# The card with every optional line and Playtest recording on fits 270 px.
	MemoryLibrary.dev_grant_all_fragments()
	var rec_was := Settings.playtest_recording
	Settings.playtest_recording = true
	Playtest.allow_headless = true
	Playtest.dir = PLAYTEST_DIR
	Playtest.begin_session("new")
	check(Playtest.is_recording(), "recording on")
	var card: MenuScreen = load("res://ui/menus/SliceEndMenu.gd").new()
	add_child(card)
	_extras.append(card)
	card.open_menu()
	var labels := _labels(card)
	check(labels.size() > 0 and labels[0] == HEADER, "header '%s' (got %s)" % [HEADER, labels[0] if labels.size() > 0 else ""])
	check(labels.has("Fragments remembered %d / %d" % [MemoryLibrary.remembered_fragment_count(), Game.state.memory_fragments.size()]),
		"fragments remembered line: %s" % labels)
	var at := labels.find("WHERE THINGS STAND")
	check(at >= 0, "WHERE THINGS STAND label")
	var shown := 0
	for i in range(at + 1, labels.size()):
		if labels[i].begins_with("Three ledges"):
			break
		shown += 1
	check(shown >= 1 and shown <= 3, "1..3 standing lines on the card (%d)" % shown)
	check(labels.has(FALLBACK_LINE), "the fallback line is on the card")
	var buttons := card._body.get_children().filter(func(n: Node) -> bool: return n is Button).map(func(b: Button) -> String: return b.text)
	check(buttons.has("Answer the playtest survey") and buttons.has("Keep exploring"), "survey and Keep exploring kept: %s" % [buttons])
	var h: float = await menu_height(card)
	check(h <= 270.0, "the Act I card fits 270 px with recording on (%.0f)" % h)
	card.close_menu()
	Playtest.end_session("test_done")
	Playtest.allow_headless = false
	Playtest.dir = Playtest.DIR
	Settings.playtest_recording = rec_was
	_clean(PLAYTEST_DIR)
	# Only a ledger reader: the ledger line shows.
	Game.new_game()
	Game.set_flag("dead_air_complete")
	Game.set_flag("mem_seen_mf_lowlight_03")
	check(Array(ActLibrary.standing_lines(act)).has(LEDGER_LINE), "the ledger line shows after the Ledger memory")


func test_act_library_current_act() -> void:
	check(ActLibrary.current_act() == 1, "new game: act 1")
	Game.set_flag("act1_complete")
	check(ActLibrary.current_act() == 1, "act1_complete: still 1 (Act II is not built)")
	check(ActLibrary.act(2) == null, "no Act II data")
	check(ActData.roman(1) == "I" and ActData.roman(4) == "IV", "roman numerals")
