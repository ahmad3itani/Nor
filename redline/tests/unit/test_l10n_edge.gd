extends RedlineTestCase
## M9 D5 edge contract (D-162: translate at the edge; D-164: line timing reads
## the displayed text). Under the pseudo-locale en_XA:
## - identity payloads (dialogue_requested.npc_name, boss_started.title) stay
##   English source, so Playtest events and PlaytestAnalyzer keep working;
## - MusicDirector's Relay check (it compares the district name) still picks
##   the hub state;
## - HintTrigger fills {action} after translating, never pseudo-mangled;
## - SeqLine paces on the displayed length, nominal_seconds() stays source;
## - a locale switch rebuilds the open menu in place and keeps its focus.
## The TestRunner puts the locale back to en after every test.

const H := preload("res://tests/fixtures/challenges/ChallengeHarness.gd")
const PROPS := "res://tests/fixtures/props_flow.tscn"
const COLLECTOR_BAY := "res://world/rooms/undercity/CollectorBay.tscn"
const RELAY := "res://world/rooms/lowlight/Relay.tscn"
const PSEUDO := "en_XA"

var h: H
var _saved_recording: bool
var _saved_variant: String


## A SequencePlayer stand-in: records pace_line and ends the step at once.
class PaceProbe extends SequencePlayer:
	var calls: Array = []

	func overlay() -> CinematicOverlay:
		return null

	func pace_line(length: int, hold: float, wait_for_tap: bool) -> void:
		calls.append([length, hold, wait_for_tap])

	func aborted() -> bool:
		return true


func before_each() -> void:
	h = H.new(self, "l10n_edge")
	h.setup()
	_saved_recording = Settings.playtest_recording
	_saved_variant = Settings.playtest_variant


func after_each() -> void:
	Playtest.end_session("test_done")
	Playtest.allow_headless = false
	Playtest.dir = Playtest.DIR
	Settings.playtest_recording = _saved_recording
	Settings.playtest_variant = _saved_variant
	MusicDirector.clear_override()
	await h.teardown()


func _pseudo() -> void:
	Loc.set_locale(PSEUDO)
	check(Loc.locale() == PSEUDO and Loc.t("Resume") != "Resume", "the pseudo-locale is active")


func _record() -> void:
	Settings.playtest_recording = true
	Settings.playtest_variant = "baseline"
	Playtest.dir = h.save_dir + "_playtest"
	Playtest.allow_headless = true
	Playtest.begin_session("new")


func _events(type: String) -> Array:
	return Playtest.session.events_of(type) if Playtest.session else []


func test_playtest_payloads_stay_source() -> void:
	_pseudo()
	_record()
	check(Playtest.session != null, "a session records")
	var room := await h.goto(PROPS, &"start")
	await physics_frames(4)
	var radio := room.find_child("NPC_props_radio", true, false) as NPC
	check(radio != null, "the fixture radio is there")
	if radio:
		# The fixture radio has no lines: give it the real Orr radio's.
		radio.profile = load("res://data/npcs/orr_radio.tres") as NpcProfile
		check(radio.profile.display_name == "Radio" and radio.profile.pick_dialogue() != null, "Orr's radio has a line to play")
		# The prompt is display text (translated); the payload is identity.
		check(radio.prompt_text().contains(Loc.t("Radio")) and not radio.prompt_text().contains("Radio"),
			"the prompt is composed in the current language: %s" % radio.prompt_text())
		var heard: Array = []
		var on_dialogue := func(_d: Resource, npc: String) -> void: heard.append(npc)
		h.listen(EventBus.dialogue_requested, on_dialogue)
		radio.interact(room.player)
		check(heard == ["Radio"], "dialogue_requested carries the source name: %s" % [heard])
		var talks := _events("dialogue")
		check(not talks.is_empty() and String(talks.back().get("npc", "")) == "Radio",
			"the Playtest dialogue event reads Radio: %s" % [talks])
	var bay := await h.goto(COLLECTOR_BAY)
	await physics_frames(4)
	var arena: BossArena = null
	for n in bay.find_children("*", "BossArena", true, false):
		arena = n as BossArena
	check(arena != null, "the bay has its arena")
	if arena == null:
		return
	var titles: Array = []
	h.listen(EventBus.boss_started, func(_b: Node2D, title: String) -> void: titles.append(title))
	arena._on_body_entered(bay.player)
	await physics_frames(2)
	check(titles == ["COLLECTOR DRONE"], "boss_started carries the source title: %s" % [titles])
	var starts := _events("boss_start")
	check(not starts.is_empty() and String(starts.back().get("boss", "")) == "COLLECTOR DRONE",
		"the Playtest boss event reads COLLECTOR DRONE: %s" % [starts])
	if not starts.is_empty():
		check(PlaytestAnalyzer.boss_key(starts.back()) == "collector_drone", "the analyzer still keys the boss")
		var e: Dictionary = starts.back().duplicate()
		e.erase("id")
		check(PlaytestAnalyzer.boss_key(e) == "collector_drone", "even a title-only (pre-M7) event keys it")


func test_music_director_relay_under_pseudo() -> void:
	_pseudo()
	var room := await h.goto(RELAY, &"start")
	await physics_frames(3)
	check(room is Room and Loc.t((room as Room).district_name) != (room as Room).district_name,
		"the district name has a pseudo translation (the check below is not trivial)")
	# Only the district check is under test: no boss aftermath or memory from
	# an earlier suite may mask it.
	MusicDirector._aftermath = 0.0
	MusicDirector._memory_active = false
	check(MusicDirector._pick_state() == MusicDirector.State.HUB,
		"the Relay still picks the hub music under en_XA (got %d)" % MusicDirector._pick_state())


func test_hint_trigger_formats_action() -> void:
	_pseudo()
	var room := await h.goto(PROPS, &"start")
	await physics_frames(2)
	var t := HintTrigger.new()
	t.hint_id = "l10n_edge_probe"
	t.text = "Breakers power the shutters. Hit one [{action}]"
	t.action = &"attack_light"
	room.add_child(t)
	var shown: Array = []
	h.listen(EventBus.hint_requested, func(text: String, _s: float) -> void: shown.append(text))
	t._on_body_entered(room.player)
	check(shown.size() == 1, "one hint (%s)" % [shown])
	if shown.is_empty():
		return
	var s: String = shown[0]
	var key := InputGlyphs.label(&"attack_light")
	check(s != t.text and s.begins_with("["), "the hint is translated: %s" % s)
	check(not s.contains("{action}") and not s.contains("{"), "the placeholder is filled, not mangled: %s" % s)
	check(s.contains("[%s]" % key), "the binding shows in brackets (%s): %s" % [key, s])
	check(s == Loc.f(t.text, {"action": key}), "the same text a translator's template gives")


func test_seqline_pacing_uses_displayed_text() -> void:
	var line := SeqLine.new()
	line.text = "Breakers power the shutters. Hit one [{action}]"
	# A real catalogued SeqLine, so en_XA has a translation for it.
	var seq := load("res://data/sequences/uc_opening.tres") as SequenceData
	for s in seq.steps if seq else []:
		if s is SeqLine and (s as SeqLine).seconds <= 0.0:
			line = s as SeqLine
			break
	var p := PaceProbe.new()
	line.run(p)
	check(p.calls.size() == 1 and int(p.calls[0][0]) == line.text.length(), "en: paced on the source length")
	var en_hold: float = p.calls[0][1] if not p.calls.is_empty() else 0.0
	check_near(en_hold, line.nominal_seconds() * SubtitleStyle.time_scale(), 0.0001, "en: the D-135 nominal time, unchanged")
	_pseudo()
	var shown := Loc.t(line.text)
	check(shown != line.text and shown.length() > line.text.length(), "the line has a longer pseudo translation")
	p.calls.clear()
	line.run(p)
	check(p.calls.size() == 1 and int(p.calls[0][0]) == shown.length(),
		"en_XA: paced on the displayed length (%s vs %d)" % [p.calls, shown.length()])
	if not p.calls.is_empty():
		var want := SeqLine.auto_seconds(shown) * Loc.info().reading_scale * SubtitleStyle.time_scale()
		check_near(float(p.calls[0][1]), want, 0.0001, "en_XA: the hold reads the displayed text x reading_scale")
	check_near(line.nominal_seconds(), SeqLine.auto_seconds(line.text), 0.0001, "nominal_seconds() stays on the source")
	p.free()


func test_locale_switch_rebuilds_open_menu_keeps_focus() -> void:
	var host := await h.boot_main(H.WORLD_A)
	check(host != null and host.open(&"pause"), "the pause menu opens")
	var pause := host.screen(&"pause")
	await get_tree().process_frame
	var before := _button_texts(pause)
	check(before.size() >= 3, "pause has rows: %s" % [before])
	pause.focus_index(2)
	await get_tree().process_frame
	check(pause.focused_index() == 2, "row 2 has focus")
	Loc.set_locale(PSEUDO)
	await get_tree().process_frame
	var after := _button_texts(pause)
	check(pause.is_open(), "the menu stays open")
	check(after.size() == before.size(), "the same rows: %s" % [after])
	check(after[0] == Loc.t(before[0]) and after[0] != before[0], "rebuilt in the new language: %s" % [after])
	check(pause.focused_index() == 2, "the focused row is kept (%d)" % pause.focused_index())
	Loc.set_locale("en")
	await get_tree().process_frame
	check(_button_texts(pause) == before, "switching back restores the source rows")
	pause.close_menu()


func _button_texts(m: MenuScreen) -> PackedStringArray:
	var out := PackedStringArray()
	for c in m._body.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append((c as Button).text)
	return out
