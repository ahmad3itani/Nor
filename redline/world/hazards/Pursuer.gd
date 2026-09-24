class_name Pursuer
extends Node2D
## The body a ChaseDirector moves along its path (M7). Created at runtime by
## the director; it holds no chase logic, only the look and the telegraphs
## that belong on the machine itself:
## - parked: dark, lights off;
## - warn: lights and a beacon come on (the siren beat before it moves);
## - chase: a red headlight cone ahead of it, pulsing at 1.2 Hz;
## - regroup: three lamps that go out one by one (the grace countdown);
## - run-out / derail: harmless, lights off, then it tips off the line.
##
## The origin is the pursuer's point on the path (floor level); the Sweeper
## hangs from its rail at data.rail_y above that point. It is a hazard, not an
## Enemy: no Hurtbox, no health, nothing to kill.

enum Mode { PARKED, WARN, CHASE, REGROUP, RUNOUT, DERAIL }

const BODY := Color(0.16, 0.15, 0.2, 1.0)
const TRIM := Color(0.3, 0.28, 0.36, 1.0)
const RAIL := Color(0.3, 0.3, 0.36, 1.0)
## Telegraph red (Art Bible reserved danger colour).
const RED := Color(1.0, 0.23, 0.31, 1.0)
const LAMP_OFF := Color(0.25, 0.1, 0.12, 1.0)
const BODY_W := 64.0
const BODY_H := 146.0
const HEADLIGHT_HZ := 1.2

var data: PursuerData
## +1 when the path runs east (the machine faces its travel direction).
var dir: int = 1
var mode: Mode = Mode.PARKED
## Regroup countdown: seconds left out of regroup_total.
var regroup_left: float = 0.0
var regroup_total: float = 1.0
## Lead below near_lead: the headlight burns solid.
var danger: bool = false
var _time: float = 0.0
var _derail_t: float = 0.0


func set_mode(m: Mode) -> void:
	mode = m
	_derail_t = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if mode == Mode.DERAIL:
		_derail_t += delta
	queue_redraw()


## 0..1 progress of the derail animation.
func derail_progress() -> float:
	if data == null or data.derail_time <= 0.0:
		return 1.0
	return clampf(_derail_t / data.derail_time, 0.0, 1.0)


func _draw() -> void:
	if data == null:
		return
	var top := data.rail_y
	# Derail: the car tips away from the rail and drops into the street.
	if mode == Mode.DERAIL:
		var t := derail_progress()
		draw_set_transform(Vector2(dir * 40.0 * t, 90.0 * t * t), dir * 0.6 * t, Vector2.ONE)
	var alpha := 1.0
	if mode == Mode.DERAIL:
		alpha = 1.0 - derail_progress()
	elif mode == Mode.REGROUP and not Settings.flash_reduction:
		# The body itself blinks with the countdown so the grace reads at a glance.
		alpha = 0.55 if fmod(regroup_left, regroup_total / 3.0) < regroup_total / 12.0 else 1.0
	# Bogie on the rail, the hanger, then the car.
	draw_rect(Rect2(-20, top - 6, 40, 6), Color(TRIM, alpha))
	draw_line(Vector2(0, top), Vector2(0, top + 10), Color(TRIM, alpha), 3.0)
	var body := Rect2(-BODY_W * 0.5, top + 10, BODY_W, BODY_H - 10)
	draw_rect(body, Color(BODY, alpha))
	draw_rect(body, Color(TRIM, alpha), false, 1.0)
	# Sweeper brushes along the bottom edge (it "sweeps" the line).
	for i in 5:
		var x := -BODY_W * 0.5 + 6.0 + i * 13.0
		draw_line(Vector2(x, top + BODY_H - 6), Vector2(x - dir * 4.0, top + BODY_H), Color(TRIM, alpha), 1.0)
	var lamp := Vector2(dir * (BODY_W * 0.5 - 6.0), top + 40)
	match mode:
		Mode.PARKED:
			draw_circle(lamp, 3.0, LAMP_OFF)
		Mode.WARN:
			draw_circle(lamp, 3.0, RED)
			var on := Settings.flash_reduction or fmod(_time, 0.4) < 0.2
			draw_circle(Vector2(0, top + 16), 3.0, RED if on else LAMP_OFF)
		Mode.CHASE:
			draw_circle(lamp, 3.0, RED)
			_draw_headlight(lamp)
		Mode.REGROUP:
			draw_circle(lamp, 3.0, LAMP_OFF)
			# Three lamps, one goes out per third of the grace.
			var lit := ceili(regroup_left / maxf(regroup_total, 0.001) * 3.0)
			for i in 3:
				draw_circle(Vector2(-12 + i * 12, top + 24), 3.0, RED if i < lit else LAMP_OFF)
		_:
			draw_circle(lamp, 3.0, LAMP_OFF)
	draw_set_transform(Vector2.ZERO)


## A red cone ahead of the car down to the deck: where it is about to be.
func _draw_headlight(from: Vector2) -> void:
	var a := 0.22
	if danger:
		a = 0.4
	elif not Settings.flash_reduction:
		a = 0.14 + 0.12 * (0.5 + 0.5 * sin(_time * TAU * HEADLIGHT_HZ))
	var reach := 120.0
	var cone := PackedVector2Array([from, Vector2(dir * reach, -2), Vector2(from.x, -2)])
	draw_colored_polygon(cone, Color(RED, a))
