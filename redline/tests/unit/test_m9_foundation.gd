extends RedlineTestCase
## M9 foundation seams (T01): the endgame EventBus signals and their Playtest
## records, the save seams (held profile, derived flags, dev taint), the run
## director and demo hooks in Room/SceneRouter, the menu registry, the title,
## pause and dev-console layouts, and the inert stubs later tasks fill.
## Every stub is inert: the game behaves as before M9.

const ROOM_A := "res://tests/fixtures/WorldA.tscn"
const TEST_DIR := "user://test_m9_foundation"
const SAVE_DIR := "user://test_m9_foundation_saves"
const SAVE_V3 := "res://tests/fixtures/save_v3_slice.json"

## signal name -> argument names, exactly as the plan's events table.
const M9_SIGNALS := {
	"achievement_unlocked": ["achievement_id", "retroactive"],
	"challenge_started": ["challenge_id", "attempt"],
	"challenge_finished": ["challenge_id", "outcome", "value", "medal", "new_best"],
	"challenge_reset": ["challenge_id", "reason"],
	"challenge_stage_cleared": ["challenge_id", "stage_id", "frames", "hits", "deaths", "medal"],
	"speedrun_split": ["split_id", "igt_frames", "delta_frames"],
	"ng_plus_started": ["cycle"],
	"input_bindings_changed": ["action"],
	"assist_suggested": ["context", "cause", "deaths"],
	"assist_suggestion_answered": ["context", "answer", "setting_key"],
	"locale_changed": ["locale"],
	"demo_boundary_reached": ["from_room", "target_room"],
}

var root: Node2D
var _extras: Array[Node] = []
var _saved_recording: bool
var _saved_variant: String


func before_each() -> void:
	_saved_recording = Settings.playtest_recording
	_saved_variant = Settings.playtest_variant
	get_tree().paused = false
	root = Node2D.new()
	add_child(root)
	SceneRouter.register_world_root(root)
	SaveManager.save_dir = SAVE_DIR
	Game.new_game()


func after_each() -> void:
	for n in _extras:
		if is_instance_valid(n):
			n.queue_free()
	_extras.clear()
	get_tree().paused = false
	Playtest.end_session("test_done")
	Playtest.allow_headless = false
	Playtest.dir = Playtest.DIR
	Settings.playtest_recording = _saved_recording
	Settings.playtest_variant = _saved_variant
	for dir in [TEST_DIR, SAVE_DIR]:
		AtomicJson.remove_tree(dir)
	SaveManager.save_dir = SaveManager.DEFAULT_SAVE_DIR
	SceneRouter.current_room = null
	SceneRouter.current_room_path = ""
	SceneRouter.world_root = null
	root.queue_free()
	Game.new_game()
	await physics_frames(2)


func _record() -> void:
	Settings.playtest_recording = true
	Settings.playtest_variant = "baseline"
	Playtest.dir = TEST_DIR
	Playtest.allow_headless = true
	Playtest.begin_session("new")


func _events(type: String) -> Array:
	return Playtest.session.events_of(type) if Playtest.session else []


func _extra(n: Node) -> Node:
	add_child(n)
	_extras.append(n)
	return n


# --- EventBus and Playtest (T01b) ---------------------------------------------------

func test_eventbus_m9_signals_typed() -> void:
	var by_name := {}
	for s in (EventBus.get_script() as GDScript).get_script_signal_list():
		by_name[s["name"]] = s
	for sig: String in M9_SIGNALS:
		check(by_name.has(sig), "EventBus.%s exists" % sig)
		if not by_name.has(sig):
			continue
		var args: Array = by_name[sig]["args"]
		var names: Array = args.map(func(a: Dictionary) -> String: return a["name"])
		check(names == M9_SIGNALS[sig], "%s arguments %s" % [sig, names])
		for a: Dictionary in args:
			check(int(a["type"]) != TYPE_NIL, "%s.%s is typed" % [sig, a["name"]])


func test_playtest_records_m9_signals() -> void:
	_record()
	EventBus.achievement_unlocked.emit("first_blood", false)
	EventBus.challenge_started.emit("br_krail", 1)
	EventBus.challenge_finished.emit("br_krail", 0, 3600, 2, true)
	EventBus.challenge_reset.emit("br_krail", &"menu")
	EventBus.challenge_stage_cleared.emit("null_descent", "static_lane", 900, 0, 0, 3)
	EventBus.speedrun_split.emit("collector", 1800, -60)
	EventBus.ng_plus_started.emit(1)
	EventBus.input_bindings_changed.emit(&"jump")
	EventBus.assist_suggested.emit("boss:warden_krail", "boss", 5)
	EventBus.assist_suggestion_answered.emit("boss:warden_krail", &"later", "")
	EventBus.locale_changed.emit("en_XA")
	EventBus.demo_boundary_reached.emit("res://a.tscn", "res://b.tscn")
	for t in ["achievement", "challenge_start", "challenge_end", "challenge_reset", "challenge_stage", "split",
			"ng_plus", "rebind", "assist_suggested", "assist_answered", "locale", "demo_end"]:
		check(_events(t).size() == 1, "one '%s' event (%d)" % [t, _events(t).size()])
	var end: Array = _events("challenge_end")
	if not end.is_empty():
		var e: Dictionary = end[0]
		check(e.get("id") == "br_krail" and int(e.get("medal", -9)) == 2 and e.get("new_best") == true, "challenge_end payload %s" % [e])


## CrossRules X-3 today: every EventBus signal is recorded by Playtest or
## listed in UNRECORDED_SIGNALS with a reason.
func test_x3_scan_clean_today() -> void:
	var src := FileAccess.get_file_as_string("res://autoload/Playtest.gd")
	var unrecorded: Dictionary = Playtest.UNRECORDED_SIGNALS
	for s in (EventBus.get_script() as GDScript).get_script_signal_list():
		var sig: String = s["name"]
		var connected := src.contains("EventBus.%s." % sig)
		var listed := unrecorded.has(sig) and str(unrecorded[sig]).strip_edges() != ""
		check(connected or listed, "EventBus.%s is neither recorded nor listed in UNRECORDED_SIGNALS" % sig)
		check(not (connected and unrecorded.has(sig)), "%s is recorded AND listed as unrecorded" % sig)
