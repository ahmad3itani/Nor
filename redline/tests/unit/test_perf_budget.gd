extends RedlineTestCase
## Presentation overhaul T09: the performance budget. Ambient caps per
## backdrop kind at every ambient motion level, VfxOneShot caps under a spawn
## storm, no presentation node leaks after the PerfProbe fight script, and at
## most 3 translucent full-screen layers per backdrop kind (fill-rate). The
## timing half of the budget is PerfProbe --budget (headless, exit code).

const PROBE := preload("res://devtools/PerfProbe.gd")
const LEAK_ROOM := "res://world/rooms/lowlight/NeonRoofs.tscn"
const FIGHT_FRAMES := 600
const SETTLE_FRAMES := 90
## Nodes the room may still hold after the settle beyond its warm baseline
## (a corpse copy, a projectile in flight, a pending sound player).
const LEAK_SLACK := 12

var _snap: Dictionary = {}


func before_each() -> void:
	_snap = snapshot_settings()
	Settings.ambient_motion = Motion.FULL
	Settings.background_dim = 0
	Settings.high_contrast = false
	Settings.flash_reduction = false


func after_each() -> void:
	restore_settings(_snap)
	EventBus.settings_changed.emit()
	for c in get_children():
		c.free()
	await physics_frames(1)


## A room scene as a lab room (world_room off: no Game.state writes).
func _room(path: String) -> Room:
	var room := (load(path) as PackedScene).instantiate() as Room
	room.world_room = false
	add_child(room)
	return room


func _backdrop_of(room: Node) -> DistrictBackdrop:
	for c in room.get_children():
		if c is DistrictBackdrop:
			return c
	return null


func _set_motion(level: int) -> void:
	Settings.ambient_motion = level
	EventBus.settings_changed.emit()
	await physics_frames(2)


# --- data ------------------------------------------------------------------------

func test_budget_rooms_cover_every_room_backdrop_kind() -> void:
	var kinds := {}
	for r in PROBE.BUDGET_ROOMS:
		check(ResourceLoader.exists(r[1]), "budget room %s exists" % r[1])
		if r[0] != &"":
			kinds[r[0]] = true
			var pres := PresentationIndex.for_room(r[1])
			check(pres != null and pres.backdrop_kind == r[0], "%s is a %s room" % [String(r[1]).get_file(), r[0]])
	# Every kind a room uses is measured (the title has no fight).
	var idx := PresentationIndex.get_index()
	for path: Variant in idx.rooms:
		var pres: RoomPresentation = idx.rooms[path]
		if pres and pres.backdrop_kind != &"" and pres.backdrop_kind != &"title":
			check(kinds.has(pres.backdrop_kind), "budget covers %s (%s)" % [pres.backdrop_kind, String(path).get_file()])


func test_mean_budget_formula() -> void:
	# Like-for-like before numbers (b578c35 with this probe) for every room.
	for row: Array in PROBE.BUDGET_ROOMS:
		var room := StringName(String(row[1]).get_file().get_basename())
		check(PROBE.BEFORE_MEAN_MS.has(room), "%s has a before number" % room)
		check(float(PROBE.BEFORE_MEAN_MS.get(room, 9.0)) < 2.0, "%s before is a like-for-like figure (< 2 ms)" % room)
	check_near(PROBE.mean_budget(&"CombatLab"), 4.0, 0.001, "CombatLab: the 4 ms floor wins over 0.88 * 1.15")
	check_near(PROBE.mean_budget(&"Unknown"), PROBE.MEAN_FLOOR_MS, 0.001, "no before number: the floor")
	var st: Dictionary = PROBE.frame_stats([1.0, 2.0, 3.0, 4.0] as Array[float])
	check_near(st["mean"], 2.5, 0.001, "frame_stats mean")
	check_near(st["max"], 4.0, 0.001, "frame_stats max")


# --- caps ------------------------------------------------------------------------

func test_ambient_caps_per_kind_at_every_motion_level() -> void:
	for r in PROBE.BUDGET_ROOMS:
		if r[0] == &"":
			continue
		var room := _room(r[1])
		await physics_frames(4)
		var b := _backdrop_of(room)
		check(b != null, "%s has a backdrop" % r[1])
		if b == null:
			room.free()
			continue
		var full := PROBE.live_counts(room)
		for level in [Motion.FULL, Motion.REDUCED, Motion.OFF]:
			await _set_motion(level)
			var probs: PackedStringArray = PROBE.cap_problems(room)
			check(probs.is_empty(), "%s at motion %d: %s" % [r[0], level, ", ".join(probs)])
			var c := PROBE.live_counts(room)
			if level == Motion.REDUCED:
				check(c["ambient_particles"] <= int(full["ambient_particles"]) / 2 + 1,
					"%s Reduced: particles %d of %d" % [r[0], c["ambient_particles"], full["ambient_particles"]])
				check(c["critters"] <= int(full["critters"]) / 2 + 1,
					"%s Reduced: critters %d of %d" % [r[0], c["critters"], full["critters"]])
			elif level == Motion.OFF:
				check(c["ambient_particles"] == 0, "%s Off: no ambient particles (%d)" % [r[0], c["ambient_particles"]])
				check(c["critters"] == 0, "%s Off: no critters (%d)" % [r[0], c["critters"]])
		await _set_motion(Motion.FULL)
		room.free()
		await physics_frames(1)


func test_vfx_caps_hold_under_200_spawns() -> void:
	var host := Node2D.new()
	add_child(host)
	for id in VfxLibrary.ids():
		var frames := VfxLibrary.frames(id)
		if frames == null or frames.get_animation_names().is_empty():
			continue
		var anim := StringName(frames.get_animation_names()[0])
		var cap := int(VfxLibrary.entry(id).get("cap", 0))
		var made := 0
		for i in 200:
			if VfxOneShot.spawn(host, id, anim, Vector2(i, 0), {"lifetime": 5.0}) != null:
				made += 1
		check(made == cap, "%s: %d of 200 spawned (cap %d)" % [id, made, cap])
		check(VfxOneShot.live_count(id) <= cap, "%s: %d live <= cap %d" % [id, VfxOneShot.live_count(id), cap])
		check(PROBE.cap_problems(host).is_empty(), "%s: cap_problems clean" % id)
		for c in host.get_children():
			c.free()
		check(VfxOneShot.live_count(id) == 0, "%s: live count back to 0 once freed" % id)
	host.free()


func test_no_node_leaks_after_the_fight_script() -> void:
	var room := _room(LEAK_ROOM)
	await physics_frames(10)
	var input := ScriptedInputSource.new()
	room.player.input_source = input
	var base := PROBE.live_counts(room)
	for f in FIGHT_FRAMES:
		PROBE.fight_input(input, f)
		PROBE.keep_alive(room)
		await physics_frames(1)
		if f % 60 == 0:
			var probs: PackedStringArray = PROBE.cap_problems(room)
			check(probs.is_empty(), "frame %d: %s" % [f, ", ".join(probs)])
	input.release_jump()
	await physics_frames(SETTLE_FRAMES)
	var after := PROBE.live_counts(room)
	check(after["vfx"] <= base["vfx"], "one-shot VFX back to baseline (%d -> %d)" % [base["vfx"], after["vfx"]])
	check(after["cpu_particles"] <= base["cpu_particles"], "CPUParticles2D back to baseline (%d -> %d)" % [base["cpu_particles"], after["cpu_particles"]])
	check(after["ambient_life"] == base["ambient_life"], "one AmbientLife per room")
	check(after["planes"] == base["planes"] and after["fogs"] == base["fogs"], "planes and fog bands unchanged")
	check(after["nodes"] <= int(base["nodes"]) + LEAK_SLACK, "room nodes %d -> %d (<= +%d)" % [base["nodes"], after["nodes"], LEAK_SLACK])
	var afterimages: Array = room.player.get_node("Visual").afterimages() if room.player.has_node("Visual") and room.player.get_node("Visual").has_method("afterimages") else []
	check(afterimages.is_empty(), "no afterimage copies left (%d)" % afterimages.size())


# --- fill-rate ---------------------------------------------------------------------

func test_at_most_three_translucent_fullscreen_layers_per_kind() -> void:
	for kind in PresentationIndex.BACKDROP_KINDS:
		var cam := Camera2D.new()
		add_child(cam)
		var b := DistrictBackdrop.new()
		b.backdrop_kind = kind
		b.ref_camera_y = 0.0
		b.setup(load("res://data/districts/undercity.tres") as DistrictTheme, cam)
		add_child(b)
		await physics_frames(1)
		var layers: Dictionary = PROBE.fullscreen_layers(b)
		check(int(layers["translucent"]) <= 3, "%s: %d translucent full-screen layers (%s)" % [kind, layers["translucent"], ", ".join(layers["names"])])
		check(int(layers["full"]) >= 1, "%s: something covers the view (%s)" % [kind, ", ".join(layers["names"])])
		b.free()
		cam.free()
