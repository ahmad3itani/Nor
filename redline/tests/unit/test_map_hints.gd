extends RedlineTestCase
## M9 T12 (bible §24 map hint strength, §20, D4 §8.6): Minimal / Standard /
## Guided change what the map offers, but secrets stay lens-gated in every
## mode (the map says that something remains, never where).

var _snap: Dictionary = {}


func before_each() -> void:
	_snap = snapshot_settings()
	Game.new_game()


func after_each() -> void:
	restore_settings(_snap)
	Game.new_game()


func test_map_hints_levels() -> void:
	# Quest notes: off at Minimal, on at Standard and Guided.
	check(not MapView.show_quest_notes(0), "Minimal hides quest notes")
	check(MapView.show_quest_notes(1) and MapView.show_quest_notes(2), "Standard and Guided show quest notes")
	# The setting drives the no-argument form; Standard is the default (M8 map).
	check(int(Settings.defaults()["map_hints"]) == 1, "Standard is the default")
	Settings.map_hints = 0
	check(MapView.hint_level() == 0 and not MapView.show_quest_notes(), "the setting reaches the map")
	Settings.map_hints = 2
	check(MapView.show_quest_notes() and MapView.show_exit_dots(), "Guided adds exit dots")
	check(not MapView.show_exit_dots(1), "Standard has no exit dots")

	# Objective room: Guided only, from the active quest stage.
	check(MapView.objective_room(2) == "", "no active quest, no objective")
	var q: QuestData = load("res://data/quests/dead_air.tres")
	Game.set_flag(q.start_flag)
	var stage_room := q.stages[q.current_stage()].map_room
	check(stage_room != "", "dead_air's first stage names a map room")
	check(MapView.objective_room(2) == stage_room, "Guided outlines the active stage's room (%s)" % MapView.objective_room(2))
	check(MapView.objective_room(1) == "" and MapView.objective_room(0) == "", "Standard and Minimal outline nothing")

	# Secrets: the lens is still required in every mode, and Minimal hides "?".
	for level in 3:
		check(not MapView.show_secret_hints(level), "no lens, no '?' at level %d" % level)
	Game.set_flag("map_lens")
	check(not MapView.show_secret_hints(0), "Minimal hides '?' even with the lens")
	check(MapView.show_secret_hints(1) and MapView.show_secret_hints(2), "the lens shows '?' at Standard and Guided")

	# Guided pulse: slow, and still under flash reduction.
	check(is_equal_approx(MapView.guide_alpha(0.1, true), MapView.guide_alpha(0.9, true)), "the guided outline is static under flash reduction")
	check(MapView.GUIDE_PULSE_RATE / TAU <= 3.0, "the guided pulse stays under 3 Hz")
