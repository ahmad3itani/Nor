class_name PulseMotes
extends Node2D
## Pulse residue streaming into Rook's chest seam (Art Direction §6
## vfx_pulse_motes: "stealing Pulse", the feel of the Core loop). A kill or an
## upgrade throws a few twinkling motes outward, then each eases into the seam
## over HOME_TIME; the last stretch flicks Core red (Palette accent).
##
## Visual only: no collision, no gameplay effect (the Core charge itself is
## ReactorCore's). Each mote is a vfx/pulse_motes `mote` VfxOneShot; a mote
## the sheet cannot spawn (missing sheet, cap) draws as a 1-2 px placeholder
## square, so the stream never disappears. The whole group frees itself after
## DRIFT_TIME + HOME_TIME (0.52 s) whatever happens to the target.

const SHEET := &"pulse_motes"
const ROW := &"mote"
## Rook's chest seam relative to his origin (feet, bottom-centre).
const SEAM_OFFSET := Vector2(0, -24)
const DRIFT_TIME := 0.12
const HOME_TIME := 0.4
## The final fraction of the homing leg drawn in Core red.
const ACCENT_FROM := 0.75
## Pale white-violet (char_rook coat_2) before the red flick.
const TINT := Color("d8d4e0")
## Mote count per ambient motion level (Full, Reduced, Off): decoration only,
## so the stream thins but never vanishes.
const MOTION_SCALES: Array[float] = [1.0, 0.5, 0.25]

var target: Node2D
var tint: Color = TINT
## Each: {node: VfxOneShot or null, from: Vector2, drift: Vector2, pos: Vector2}
var motes: Array[Dictionary] = []
var _age: float = 0.0
var _last_goal: Vector2


## `count` before the motion scale; `rng` is the caller's own presentation RNG.
static func spawn(parent: Node, at: Vector2, p_target: Node2D, count: int, rng: RandomNumberGenerator,
		p_tint: Color = TINT) -> PulseMotes:
	if parent == null or not is_instance_valid(parent):
		return null
	var pm := PulseMotes.new()
	pm.name = "PulseMotes"
	pm.target = p_target
	pm.tint = p_tint
	pm.z_index = 5
	parent.add_child(pm)
	pm._last_goal = pm._goal(at)
	for i in scaled_count(count):
		var a := rng.randf() * TAU
		var drift := Vector2(cos(a), sin(a) * 0.7) * rng.randf_range(6.0, 14.0) + Vector2(0, -4)
		var node := VfxOneShot.spawn(pm, SHEET, ROW, pm.to_local(at),
			{"tint": p_tint, "lifetime": DRIFT_TIME + HOME_TIME + 0.05, "speed_scale": rng.randf_range(0.8, 1.2)})
		pm.motes.append({"node": node, "from": at, "drift": drift, "pos": at})
	pm.queue_redraw()
	return pm


## Motes actually thrown for `count` at the current ambient motion level.
static func scaled_count(count: int) -> int:
	if count <= 0:
		return 0
	return maxi(1, roundi(count * MOTION_SCALES[Motion.level()]))


static func total_time() -> float:
	return DRIFT_TIME + HOME_TIME


func _goal(fallback: Vector2) -> Vector2:
	if is_instance_valid(target) and target.is_inside_tree():
		return target.global_position + SEAM_OFFSET
	return fallback


func _process(delta: float) -> void:
	_age += delta
	if _age >= total_time():
		queue_free()
		return
	_last_goal = _goal(_last_goal)
	var red := false
	var home_t := 0.0
	if _age > DRIFT_TIME:
		home_t = clampf((_age - DRIFT_TIME) / HOME_TIME, 0.0, 1.0)
		red = home_t >= ACCENT_FROM
	var drift_t := clampf(_age / DRIFT_TIME, 0.0, 1.0)
	var ease_out := 1.0 - (1.0 - drift_t) * (1.0 - drift_t)
	for m in motes:
		var out: Vector2 = m["from"] + (m["drift"] as Vector2) * ease_out
		var pos := out.lerp(_last_goal, home_t * home_t)
		m["pos"] = pos
		var node: VfxOneShot = m["node"]
		if is_instance_valid(node):
			node.global_position = pos.round()
			if red:
				node.modulate = accent_color()
	queue_redraw()


## Core red, value-scaled under flash reduction like every VfxOneShot tint.
static func accent_color() -> Color:
	var c := Palette.color(&"accent")
	if Settings.flash_reduction:
		c = Color(c.r * VfxOneShot.FLASH_REDUCED_VALUE, c.g * VfxOneShot.FLASH_REDUCED_VALUE,
			c.b * VfxOneShot.FLASH_REDUCED_VALUE, c.a)
	return c


func _draw() -> void:
	var red := _age > DRIFT_TIME + HOME_TIME * ACCENT_FROM
	for m in motes:
		if is_instance_valid(m["node"]):
			continue
		var p := to_local((m["pos"] as Vector2).round())
		draw_rect(Rect2(p - Vector2.ONE, Vector2(2, 2)), accent_color() if red else tint)
