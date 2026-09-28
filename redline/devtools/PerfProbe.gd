extends Node
## Headless CPU cost probe for a room under fight load (Combat Lab default).
##   godot --headless --fixed-fps 60 res://devtools/PerfProbe.tscn
##   ... PerfProbe.tscn -- --room=res://world/rooms/lowlight/NeonRoofs.tscn --at=600:-102,1850:-92
## Measures wall time per frame (with --fixed-fps, frames run back to back,
## so wall time = total CPU work per tick). Note: Performance.TIME_PHYSICS_PROCESS
## is unreliable in this mode and must not be quoted. No GPU cost included.
##
## Presentation budget (overhaul T09):
##   ... PerfProbe.tscn -- --budget [--only=Wake,NeonRoofs] [--frames=600]
## loads the heaviest room of every backdrop kind (BUDGET_ROOMS) one after
## the other, runs the fight script at the player's spawn and prints mean /
## p95 frame ms and the live presentation node counts (CPUParticles2D,
## VfxOneShot, AmbientLife, planes, ambient particles). Exit 1 when a room's
## mean exceeds max(perf_before mean * 1.15, 4.0 ms), its p95 exceeds 8 ms,
## or an ambient / VFX cap is exceeded at any sample. The same run under
## xvfb with a 1920x1080 window (no --headless) is the fill-rate check:
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3
##     --resolution 1920x1080 --fixed-fps 60 res://devtools/PerfProbe.tscn -- --budget --frames=300
## It prints WINDOW lines and judges only the caps: software GL (llvmpipe)
## numbers mean nothing alone; compare the ratio against the pre-overhaul
## tree (M9 gate b578c35) run the same way.
##
## Measured at T09 (mean ms, 600 frames headless; windowed 300 frames at
## 1920x1080 on llvmpipe; 4-core container with other jobs, +-0.3 ms noise).
## "before" is the M9 gate tree b578c35 with this probe's fight script:
##   room              before  after  p95 after | window before -> after
##   Wake              0.75    1.07   2.06      | 27.7 -> 27.8 (1.00x)
##   CollectorBay      0.81    1.32   2.52      | 20.7 -> 21.5 (1.04x)
##   FirstPursuit      0.81    1.46   2.70      |
##   EscapeTunnel      0.86    1.42   2.59      |
##   MaintenanceShaft  0.89    1.46   2.61      |
##   FloodedAlley      1.13    1.50   2.93      | 21.7 -> 23.0 (1.06x)
##   SmugglerRoute     1.05    1.58   2.82      |
##   NeonRoofs         1.11    1.61   2.71      | 21.6 -> 23.7 (1.10x)
##   ApartmentStack    1.13    1.58   2.76      | 21.6 -> 23.0 (1.06x)
##   BellTower         1.23    1.72   3.13      | 23.9 -> 25.2 (1.06x)
##   Relay             0.65    1.21   2.33      | 22.1 -> 23.0 (1.04x)
##   NullFloor         0.71    1.25   2.30      | 20.7 -> 21.5 (1.04x)
##   PulsePit          0.88    1.15   2.19      | 26.8 -> 28.6 (1.07x)
##   CombatLab         0.88    1.50   2.89      | 21.6 -> 21.3 (0.99x)
## At most 2 translucent full-screen layers in any room (BellTower: the
## near plane and the vignette over an opaque sky); every cap held. The
## layer count covers full-height planes, the sky and the vignette only: it
## is not an overdraw budget. Fog bands, light shafts, additive lamp glows
## and ambient particles / rain are partial-height translucent or additive
## overdraw it does not count; real GPU cost is unmeasured (K-OV-11).
## Profiling the CombatLab growth (0.97 -> ~1.7 ms, same session): sprite
## actors (Rook + enemies, AnimatedSprite2D + visual logic) ~0.3-0.4 ms,
## the kit HUD redraw ~0.2 ms, VFX one-shots ~0.1 ms, the rest (juice,
## aura, feedback) ~0.2 ms. SpriteActor now skips _process without a mask.

## One room per backdrop kind a room uses, the heaviest of its kind (most
## planes, life and enemies); the plan's ten rooms plus the chase, tunnel,
## shaft and canal kinds (FloodedAlley is an ll_street room, SmugglerRoute
## the ll_canal one). CombatLab is the graybox reference (no presentation).
const BUDGET_ROOMS: Array[Array] = [
	[&"uc_ward", "res://world/rooms/undercity/Wake.tscn"],
	[&"uc_boss_bay", "res://world/rooms/undercity/CollectorBay.tscn"],
	[&"uc_pursuit", "res://world/rooms/undercity/FirstPursuit.tscn"],
	[&"uc_tunnel", "res://world/rooms/undercity/EscapeTunnel.tscn"],
	[&"uc_shaft", "res://world/rooms/undercity/MaintenanceShaft.tscn"],
	[&"ll_street", "res://world/rooms/lowlight/FloodedAlley.tscn"],
	[&"ll_canal", "res://world/rooms/lowlight/SmugglerRoute.tscn"],
	[&"ll_roof", "res://world/rooms/lowlight/NeonRoofs.tscn"],
	[&"ll_interior", "res://world/rooms/lowlight/ApartmentStack.tscn"],
	[&"ll_tower", "res://world/rooms/lowlight/BellTower.tscn"],
	[&"relay_hub", "res://world/rooms/lowlight/Relay.tscn"],
	[&"null_rig", "res://world/rooms/challenge/NullFloor.tscn"],
	[&"pulse_pit", "res://world/rooms/challenge/PulsePit.tscn"],
	[&"", "res://world/rooms/CombatLab.tscn"],
]
## Headless means of the M9 gate tree b578c35 measured with THIS probe (the
## table above). perf_before.txt's 2.20 / 2.29 / 1.69 came from the old probe,
## which drew 999 HUD pips, and must not be used. max(before * 1.15, 4 ms)
## is still the 4 ms floor for every room: headless mean CPU rose 33-86 %
## over the overhaul (K-OV-13), so only the floor and the 8 ms p95 hold.
const BEFORE_MEAN_MS := {
	&"Wake": 0.75, &"CollectorBay": 0.81, &"FirstPursuit": 0.81, &"EscapeTunnel": 0.86,
	&"MaintenanceShaft": 0.89, &"FloodedAlley": 1.13, &"SmugglerRoute": 1.05, &"NeonRoofs": 1.11,
	&"ApartmentStack": 1.13, &"BellTower": 1.23, &"Relay": 0.65, &"NullFloor": 0.71,
	&"PulsePit": 0.88, &"CombatLab": 0.88,
}
const MEAN_GROWTH := 1.15
const MEAN_FLOOR_MS := 4.0
const P95_MAX_MS := 8.0
## Live CPUParticles2D nodes at once (placeholder sparks and dust, the
## fallback when a sprite cap is full). Each lives <= 0.35 s.
const MAX_CPU_PARTICLE_NODES := 32
const SAMPLE_EVERY := 30
const VIEW := Vector2(480, 270)

@export var frames_per_arena: int = 600
@export var arenas: Array[Vector2] = [Vector2(730, -2), Vector2(1500, -2), Vector2(2000, -2)]


var room_path: String = "res://world/rooms/CombatLab.tscn"
var _budget: bool = false
var _only: PackedStringArray = []
var _exit_code: bool = true


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--room="):
			room_path = arg.trim_prefix("--room=")
		elif arg.begins_with("--at="):
			arenas.clear()
			for pair in arg.trim_prefix("--at=").split(","):
				var xy := pair.split(":")
				arenas.append(Vector2(float(xy[0]), float(xy[1])))
		elif arg == "--budget":
			_budget = true
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",", false)
		elif arg.begins_with("--frames="):
			frames_per_arena = maxi(int(arg.trim_prefix("--frames=")), 30)
		elif arg == "--no-exit-code":
			_exit_code = false
	var main: Node = load("res://Main.tscn").instantiate()
	main.start_room = _budget_rooms()[0][1] if _budget else room_path
	add_child(main)
	if _budget:
		_run_budget.call_deferred()
	else:
		_run.call_deferred()


func _run() -> void:
	for i in 10:
		await get_tree().physics_frame
	var room := SceneRouter.current_room as Room
	var input := _arm(room)
	var frame_ms: Array[float] = []
	var last := Time.get_ticks_usec()
	for arena in arenas:
		room.player.respawn(arena)
		for f in frames_per_arena:
			fight_input(input, f)
			keep_alive(room)
			await get_tree().physics_frame
			var now := Time.get_ticks_usec()
			frame_ms.append((now - last) / 1000.0)
			last = now
	var st := frame_stats(frame_ms)
	print("%s fight load (headless CPU): avg %.2f ms  p95 %.2f ms  p99 %.2f ms  max %.2f ms  over %d frames" % [
		room.name, st["mean"], st["p95"], st["p99"], st["max"], frame_ms.size()])
	get_tree().quit()


# --- shared with tests/unit/test_perf_budget.gd -----------------------------------

## The fight script: one frame of scripted presses (light every 20 frames,
## ranged every 45, jump every 90). Unchanged since M2, so before/after
## numbers compare.
static func fight_input(input: ScriptedInputSource, f: int) -> void:
	if f % 20 == 0:
		input.press_light()
	if f % 45 == 0:
		input.press_ranged()
	if f % 90 == 0:
		input.press_jump()


## A scripted input on the room's player. Until T09 the probe raised
## max_health to 999, which made the kit HUD draw 999 pips (+3.5 ms a frame
## in CombatLab, a probe artefact); the player now keeps the real maximum
## and is healed back to it every frame (keep_alive), so the run is still
## spent fighting and the HUD costs what it costs in play.
static func _arm(room: Room) -> ScriptedInputSource:
	var input := ScriptedInputSource.new()
	room.player.input_source = input
	keep_alive(room)
	return input


## Refills the player's health (call once per frame of the fight script).
static func keep_alive(room: Room) -> void:
	if room and is_instance_valid(room.player) and room.player.combat and not room.player.combat.dead:
		room.player.combat.health = room.player.combat.config.max_health


## mean / p95 / p99 / max of frame times (ms).
static func frame_stats(frame_ms: Array[float]) -> Dictionary:
	var s := frame_ms.duplicate()
	s.sort()
	var total := 0.0
	for v in s:
		total += v
	var n := maxi(s.size(), 1)
	if s.is_empty():
		return {"mean": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0}
	return {"mean": total / n, "p95": s[int(s.size() * 0.95)], "p99": s[int(s.size() * 0.99)], "max": s[s.size() - 1]}


## The headless mean budget of a room (scene root name).
static func mean_budget(room_name: StringName) -> float:
	return maxf(float(BEFORE_MEAN_MS.get(room_name, 0.0)) * MEAN_GROWTH, MEAN_FLOOR_MS)


## Live presentation nodes under `root`.
static func live_counts(root: Node) -> Dictionary:
	var c := {"nodes": 0, "cpu_particles": 0, "vfx": 0, "ambient_life": 0, "critters": 0, "planes": 0,
		"fogs": 0, "ambient_particles": 0}
	_count(root, c)
	return c


static func _count(n: Node, c: Dictionary) -> void:
	c["nodes"] += 1
	if n is CPUParticles2D:
		c["cpu_particles"] += 1
	elif n is VfxOneShot:
		c["vfx"] += 1
	elif n is AmbientLife:
		c["ambient_life"] += 1
		c["critters"] += (n as AmbientLife).critter_sprites().size()
	elif n is FogBand:
		c["fogs"] += 1
	elif n is ParallaxPlane:
		c["planes"] += 1
	elif n is AmbientParticles:
		c["ambient_particles"] += (n as AmbientParticles).live_count()
	for ch in n.get_children():
		_count(ch, c)


## Every ambient / VFX cap broken under `root` right now (empty = within).
static func cap_problems(root: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var cpu := [0]
	_caps(root, out, cpu)
	if cpu[0] > MAX_CPU_PARTICLE_NODES:
		out.append("%d CPUParticles2D nodes > %d" % [cpu[0], MAX_CPU_PARTICLE_NODES])
	for id in VfxLibrary.ids():
		var cap := int(VfxLibrary.entry(id).get("cap", 0))
		if cap > 0 and VfxOneShot.live_count(id) > cap:
			out.append("vfx %s: %d live > cap %d" % [id, VfxOneShot.live_count(id), cap])
	return out


static func _caps(n: Node, out: PackedStringArray, cpu: Array) -> void:
	if n is CPUParticles2D:
		cpu[0] += 1
	elif n is AmbientParticles:
		var p := n as AmbientParticles
		if p.live_count() > mini(p.target_count(), AmbientParticles.MAX):
			out.append("ambient particles %d > %d" % [p.live_count(), p.target_count()])
	elif n is AmbientLife:
		var life := n as AmbientLife
		for kind: StringName in AmbientLife.CAPS:
			if life.count(kind) > AmbientLife.cap(kind):
				out.append("ambient life %s: %d > cap %d" % [kind, life.count(kind), AmbientLife.cap(kind)])
	for ch in n.get_children():
		_caps(ch, out, cpu)


## Full-screen layers the backdrop draws right now (fill-rate): visible
## planes that span the view height (or tile vertically), the procedural
## sky while no opaque plane hides it, and the vignette. A layer is
## translucent unless it is an opaque plane (PlaneSpec.opaque, no alpha).
## {"full": int, "translucent": int, "names": PackedStringArray}
static func fullscreen_layers(b: DistrictBackdrop) -> Dictionary:
	var full := 0
	var translucent := 0
	var names := PackedStringArray()
	var sky := b.sky_layer()
	if sky and sky.is_visible_in_tree():
		full += 1
		names.append("sky")
	for p in b.planes():
		if not is_instance_valid(p) or not p.is_visible_in_tree() or p is FogBand:
			continue
		if not (p.tile_y or p.tex_height() >= VIEW.y):
			continue
		full += 1
		var opaque := p.spec != null and p.spec.opaque
		if not opaque:
			translucent += 1
		names.append("%s%s" % [p.name, "" if opaque else "*"])
	var v := b.vignette()
	if v and is_instance_valid(v) and v.is_visible_in_tree():
		full += 1
		translucent += 1
		names.append("vignette*")
	return {"full": full, "translucent": translucent, "names": names}


# --- --budget ----------------------------------------------------------------------

## A windowed run (xvfb fill-rate check): timings are reported, not judged.
static func _windowed() -> bool:
	return DisplayServer.get_name() != "headless"


func _budget_rooms() -> Array[Array]:
	var out: Array[Array] = []
	for r in BUDGET_ROOMS:
		var room_name: String = String(r[1]).get_file().get_basename()
		if _only.is_empty() or _only.has(room_name):
			out.append(r)
	return out


func _run_budget() -> void:
	var rows: Array[Dictionary] = []
	var failures := PackedStringArray()
	var first := true
	for r in _budget_rooms():
		var path: String = r[1]
		if not first:
			SceneRouter.goto_room(path)
		first = false
		for i in 10:
			await get_tree().physics_frame
		var room := SceneRouter.current_room as Room
		if room == null:
			failures.append("%s: did not load" % path)
			continue
		var input := _arm(room)
		var arena := room.player.global_position
		var base := live_counts(get_tree().root)
		var peak := base.duplicate()
		var problems := PackedStringArray()
		var frame_ms: Array[float] = []
		var last := Time.get_ticks_usec()
		for f in frames_per_arena:
			fight_input(input, f)
			keep_alive(room)
			await get_tree().physics_frame
			var now := Time.get_ticks_usec()
			frame_ms.append((now - last) / 1000.0)
			last = now
			if f % SAMPLE_EVERY == 0:
				var c := live_counts(get_tree().root)
				for k: String in c:
					peak[k] = maxi(int(peak[k]), int(c[k]))
				for p in cap_problems(get_tree().root):
					if not problems.has(p):
						problems.append(p)
		var st := frame_stats(frame_ms)
		var budget := mean_budget(room.name)
		var layers := {"full": 0, "translucent": 0, "names": PackedStringArray()}
		for c in room.get_children():
			if c is DistrictBackdrop:
				layers = fullscreen_layers(c)
		var row := {"room": room.name, "kind": r[0], "at": arena, "stats": st, "budget": budget, "peak": peak,
			"layers": layers}
		rows.append(row)
		print(("WINDOW" if _windowed() else "BUDGET") + " %-15s %-12s mean %.2f ms (<= %.2f)  p95 %.2f ms (<= %.1f)  max %.2f  peak nodes %d  cpu_particles %d  vfx %d  life %d/%d critters  planes %d  fogs %d  motes %d  fullscreen %d (%d translucent: %s)  at %d:%d" % [
			room.name, r[0], st["mean"], budget, st["p95"], P95_MAX_MS, st["max"], peak["nodes"], peak["cpu_particles"],
			peak["vfx"], peak["ambient_life"], peak["critters"], peak["planes"], peak["fogs"], peak["ambient_particles"],
			layers["full"], layers["translucent"], ", ".join(layers["names"]), int(arena.x), int(arena.y)])
		if not _windowed() and st["mean"] > budget:
			failures.append("%s: mean %.2f ms > %.2f ms" % [room.name, st["mean"], budget])
		if not _windowed() and st["p95"] > P95_MAX_MS:
			failures.append("%s: p95 %.2f ms > %.1f ms" % [room.name, st["p95"], P95_MAX_MS])
		for p in problems:
			failures.append("%s: %s" % [room.name, p])
	for f in failures:
		print("BUDGET FAIL: " + f)
	if failures.is_empty():
		print("BUDGET OK (%d rooms, %d frames each)" % [rows.size(), frames_per_arena])
	get_tree().quit(1 if failures.size() > 0 and _exit_code else 0)
