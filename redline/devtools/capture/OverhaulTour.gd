class_name OverhaulTour
extends RefCounted
## `--tour=overhaul` (presentation overhaul T10): the review frames of the
## art/audio pass, in a TourSandbox with INSTANT cinematics (the same session
## rules as --tour=endgame, CaptureTour.prepare_session).
##   b  one frame per backdrop kind (data/presentation/rooms.tres): the title
##      and one room per kind, at a spawn, after the area banner faded
##   c  combat: a light hit with sparks and the slash smear, an enemy death
##      burst, the Collector and Warden Krail right after their phase-2 switch
##   u  UI: the HUD at 100 % and 150 %, a dialogue with its portrait, the
##      pause menu
##   v  accessibility variants: the ll_street and uc_ward rooms and the combat
##      hit again under flash reduction, high contrast, protan/deutan palette,
##      background dim Strong and ambient motion Off (one setting at a time)
##
## Like the endgame tour it fails: it prints "overhaul tour: N shots" and
## exits 1 when any expected shot of the selected sections is missing.
##   ... res://devtools/CaptureTour.tscn -- --out=/abs/dir --tour=overhaul [--only=b,c,u,v]

const SECTIONS: PackedStringArray = ["b", "c", "u", "v"]
const WAKE := "res://world/rooms/undercity/Wake.tscn"
const FLOODED_ALLEY := "res://world/rooms/lowlight/FloodedAlley.tscn"
const COLLECTOR_BAY := "res://world/rooms/undercity/CollectorBay.tscn"
const WARDEN_TOWER := "res://world/rooms/lowlight/WardenTower.tscn"
const NEEDLE := "res://enemies/variants/Needle.tscn"
## [backdrop kind, room scene, spawn id]: one room per kind, the heaviest of
## its kind where there is a choice (PerfProbe.BUDGET_ROOMS). `title` is the
## title screen over TitleBackdrop (no room load). test_capture_overhaul
## checks this covers every kind rooms.tres uses.
const KIND_ROOMS: Array[Array] = [
	[&"title", "", &""],
	[&"uc_ward", WAKE, &"start"],
	[&"uc_pursuit", "res://world/rooms/undercity/FirstPursuit.tscn", &"from_lift"],
	[&"uc_tunnel", "res://world/rooms/undercity/EscapeTunnel.tscn", &"from_bay"],
	[&"uc_shaft", "res://world/rooms/undercity/MaintenanceShaft.tscn", &"from_medical"],
	[&"uc_boss_bay", COLLECTOR_BAY, &"from_lift"],
	[&"ll_street", FLOODED_ALLEY, &"from_relay"],
	[&"ll_canal", "res://world/rooms/lowlight/SmugglerRoute.tscn", &"smuggler_den"],
	[&"ll_interior", "res://world/rooms/lowlight/ApartmentStack.tscn", &"stack_mid"],
	[&"ll_roof", "res://world/rooms/lowlight/NeonRoofs.tscn", &"from_stack"],
	[&"ll_tower", "res://world/rooms/lowlight/BellTower.tscn", &"bell_top"],
	[&"relay_hub", "res://world/rooms/lowlight/Relay.tscn", &"start"],
	[&"null_rig", "res://world/rooms/challenge/NullFloor.tscn", &"from_breaker"],
	[&"pulse_pit", "res://world/rooms/challenge/PulsePit.tscn", &"start"],
]
const COMBAT_SHOTS: PackedStringArray = ["ov_c_01_hit_sparks", "ov_c_02_death_burst", "ov_c_03_collector_phase2",
	"ov_c_04_krail_phase2"]
## The frame after hit-stop of the hit-sparks shot: at the hit frame the
## smear, flash and sparks cover the struck enemy, so this one shows whether
## it stays readable under hit VFX.
const HIT_LATE_SHOT := "ov_c_01_hit_sparks_late"
const HIT_LATE_FRAMES := 9
const UI_SHOTS: PackedStringArray = ["ov_u_01_hud_100", "ov_u_02_hud_150", "ov_u_03_dialogue_portrait", "ov_u_04_pause"]
## [variant id, {Settings property: value}]: one accessibility setting at a
## time, everything else at its default.
const VARIANTS: Array[Array] = [
	["flash", {"flash_reduction": true}],
	["contrast", {"high_contrast": true}],
	["protan", {"colorblind_mode": 1}],
	["dim", {"background_dim": 2}],
	["still", {"ambient_motion": 2}],
]
## The frames every variant repeats (backdrop kinds or "hit").
const VARIANT_FRAMES: PackedStringArray = ["ll_street", "uc_ward", "hit"]
## Frames a room settles before a backdrop shot: the area banner is gone.
const SETTLE := 210

var tour: Node
var taken: PackedStringArray = []
var _only: PackedStringArray = []


func _init(capture_tour: Node) -> void:
	tour = capture_tour


static func kinds() -> PackedStringArray:
	var out := PackedStringArray()
	for r in KIND_ROOMS:
		out.append(String(r[0]))
	return out


static func backdrop_shot(kind: String) -> String:
	return "ov_b_%s" % kind


static func variant_shot(variant: String, frame: String) -> String:
	return "ov_v_%s_%s" % [variant, frame]


## The contract: every shot a section must produce, in order.
static func shots(section: String) -> PackedStringArray:
	var out := PackedStringArray()
	match section:
		"b":
			for k in kinds():
				out.append(backdrop_shot(k))
		"c":
			out = COMBAT_SHOTS.duplicate()
			out.insert(1, HIT_LATE_SHOT)
		"u":
			out = UI_SHOTS.duplicate()
		"v":
			for v in VARIANTS:
				for f in VARIANT_FRAMES:
					out.append(variant_shot(v[0], f))
	return out


## The sections an --only= argument selects (every section without one;
## unknown letters are ignored).
static func parse_only(args: PackedStringArray) -> PackedStringArray:
	for a in args:
		if a.begins_with("--only="):
			var out := PackedStringArray()
			for s in a.trim_prefix("--only=").split(",", false):
				var k := s.strip_edges()
				if SECTIONS.has(k) and not out.has(k):
					out.append(k)
			return out
	return SECTIONS.duplicate()


static func expected(sections: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for s in sections:
		out.append_array(shots(s))
	return out


static func room_for(kind: String) -> Array:
	for r in KIND_ROOMS:
		if String(r[0]) == kind:
			return r
	return []


func run() -> void:
	_only = parse_only(OS.get_cmdline_user_args())
	var snap := TourSandbox.begin()
	await _frames(30)
	for s in SECTIONS:
		if not _only.has(s):
			continue
		await _reset_world()
		await Callable(self, "_section_" + s).call()
		await _reset_world()
	TourSandbox.end(snap)
	var missing := PackedStringArray()
	for n in expected(_only):
		if not taken.has(n):
			missing.append(n)
	print("overhaul tour: %d shots" % taken.size())
	if not missing.is_empty():
		printerr("overhaul tour: missing shots: %s" % ", ".join(missing))
	tour.call("_quit", 1 if not missing.is_empty() else 0)


# --- Helpers ----------------------------------------------------------------------------

func _frames(n: int) -> void:
	await tour.call("_frames", n)


func _shot(name: String) -> void:
	await tour.call("_shot", name)
	taken.append(name)


func _tree() -> SceneTree:
	return tour.get_tree()


func _host() -> MenuHost:
	return _tree().root.find_child("Menus", true, false) as MenuHost


func _input() -> ScriptedInputSource:
	return tour.get("_input") as ScriptedInputSource


func _close_menus() -> void:
	var h := _host()
	if h:
		h.drop_queued()
		for c in h.get_children():
			if c is MenuScreen and (c as MenuScreen).is_open():
				(c as MenuScreen).close_menu()
	var box := _tree().root.find_child("DialogueBox", true, false)
	if box and box.has_method("is_open"):
		var guard := 0
		while box.call("is_open") and guard < 64:
			box.set("shown_chars", 9999.0)
			box.call("advance")
			guard += 1
	_tree().paused = false


## Every setting a variant touches back at its default, a fresh profile.
func _reset_look() -> void:
	Settings.ui_scale = 0
	Settings.flash_reduction = false
	Settings.high_contrast = false
	Settings.colorblind_mode = 0
	Settings.background_dim = 0
	Settings.ambient_motion = 0
	EventBus.settings_changed.emit()


func _reset_world() -> void:
	_close_menus()
	_reset_look()
	var input := _input()
	input.move_x = 0
	Game.new_game()
	Game.set_flag("core_hud_hidden", false)
	await _frames(5)


func _goto(path: String, entry: StringName, settle: int = SETTLE) -> Room:
	_close_menus()
	SceneRouter.goto_room(path, entry)
	for i in 240:
		await _frames(1)
		if SceneRouter.current_room_path == path and not SceneRouter.transitioning:
			break
	var room := SceneRouter.current_room as Room
	if room and is_instance_valid(room.player):
		room.player.input_source = _input()
		room.player.invulnerable = true
	await _frames(settle)
	return room


func _until(cond: Callable, max_frames: int = 240) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await _frames(1)
	return bool(cond.call())


## Loads the room of `kind` (or opens the title) and shoots it as `name`.
func _backdrop(kind: String, name: String) -> void:
	if kind == "title":
		_close_menus()
		var title := _host().get_node_or_null("TitleMenu") as MenuScreen
		if title == null:
			return
		title.open_menu()
		await _frames(60)
		if title.is_open():
			await _shot(name)
		title.close_menu()
		await _frames(4)
		return
	var r := room_for(kind)
	if r.is_empty() or not ResourceLoader.exists(String(r[1])):
		return
	var room := await _goto(String(r[1]), r[2])
	if room:
		await _shot(name)


## Walks Rook into a Needle standing still in the Flooded Alley and shoots
## the frame after the light hit lands (spark + smear), and with `late` the
## frame after hit-stop too. `lethal` leaves the
## Needle one hit from death and shoots the burst instead.
func _hit(name: String, lethal: bool = false, late: String = "") -> void:
	var room := await _goto(FLOODED_ALLEY, &"from_relay")
	if room == null or not is_instance_valid(room.player):
		return
	var e := DevActions.spawn_enemy(NEEDLE)
	if e == null:
		return
	e.ai_enabled = false
	await _frames(20)
	var player := room.player
	var input := _input()
	input.move_x = 1 if e.global_position.x > player.global_position.x else -1
	await _until(func() -> bool: return not is_instance_valid(e) or absf(e.global_position.x - player.global_position.x) < 34.0, 120)
	input.move_x = 0
	if not is_instance_valid(e):
		return
	if lethal:
		e.health = 0.5
	var start: float = e.health
	input.press_light()
	var landed := await _until(func() -> bool: return not is_instance_valid(e) or e.is_dead() or e.health < start, 40)
	if landed:
		await _frames(5 if lethal else 2)
		await _shot(name)
		if late != "":
			await _frames(HIT_LATE_FRAMES)
			await _shot(late)
	await _frames(30)


## Starts the boss fight of `path`, drops the boss under its phase-2
## threshold and shoots the phase change.
func _boss_phase(path: String, entry: StringName, boss_id: StringName, name: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var room := await _goto(path, entry, 20)
	if room == null:
		return
	var input := _input()
	input.move_x = 1
	await _frames(60)
	input.move_x = 0
	await _frames(150)
	var boss: Enemy = null
	for n in _tree().get_nodes_in_group(&"enemies"):
		var en := n as Enemy
		if en and en.data and en.data.id == boss_id and not en.is_dead():
			boss = en
	if boss == null:
		return
	var phases: Array = []
	var cb := func(_b: Node2D, p: int) -> void: phases.append(p)
	EventBus.boss_phase_changed.connect(cb)
	boss.health = boss.data.max_health * 0.4
	var switched := await _until(func() -> bool: return not phases.is_empty(), 240)
	EventBus.boss_phase_changed.disconnect(cb)
	if switched:
		await _frames(12)
		await _shot(name)


# --- b: backdrops ------------------------------------------------------------------------

func _section_b() -> void:
	for k in kinds():
		await _backdrop(k, backdrop_shot(k))


# --- c: combat ---------------------------------------------------------------------------

func _section_c() -> void:
	await _hit(COMBAT_SHOTS[0], false, HIT_LATE_SHOT)
	await _reset_world()
	await _hit(COMBAT_SHOTS[1], true)
	await _reset_world()
	await _boss_phase(COLLECTOR_BAY, &"from_lift", &"collector_drone", COMBAT_SHOTS[2])
	await _reset_world()
	await _boss_phase(WARDEN_TOWER, &"from_bell", &"warden_krail", COMBAT_SHOTS[3])


# --- u: UI ---------------------------------------------------------------------------------

func _section_u() -> void:
	var room := await _goto(FLOODED_ALLEY, &"from_relay")
	if room == null:
		return
	await _shot(UI_SHOTS[0])
	Settings.ui_scale = 2
	EventBus.settings_changed.emit()
	await _frames(10)
	await _shot(UI_SHOTS[1])
	Settings.ui_scale = 0
	EventBus.settings_changed.emit()
	await _frames(4)
	var orr: NpcProfile = load("res://data/npcs/orr.tres")
	EventBus.dialogue_requested.emit(orr.pick_dialogue(), "Orr")
	await _frames(40)
	await _shot(UI_SHOTS[2])
	_close_menus()
	await _frames(4)
	var h := _host()
	if h and h.open(&"pause"):
		await _frames(6)
		var p := h.screen(&"pause")
		if p and p.is_open():
			await _shot(UI_SHOTS[3])
	_close_menus()


# --- v: accessibility variants ---------------------------------------------------------------

func _section_v() -> void:
	for v in VARIANTS:
		for f in VARIANT_FRAMES:
			await _reset_world()
			var values: Dictionary = v[1]
			for k: String in values:
				Settings.set(k, values[k])
			EventBus.settings_changed.emit()
			var name := variant_shot(v[0], f)
			if f == "hit":
				await _hit(name)
			else:
				await _backdrop(f, name)
