class_name ScannerData
extends Resource
## Tuning for one kind of ScannerBeam (M7 Security Station, D-072). Every
## number a beam uses lives here so a room only places beams and picks a
## preset from data/level/scanner_*.tres.
##
## The beam's shape tells the player the answer (colour-blind safe, §24):
## LOW = jump it, HIGH = go low under it, FULL = dodge through it.

enum Mode { LOW, HIGH, FULL }

@export var mode: Mode = Mode.FULL
## Beam width in px.
@export var thickness: float = 4.0
## LOW: the beam covers the floor up to this height (px above bottom_y).
@export var low_top: float = 20.0
## HIGH: the gap left open above the floor (px). Rook's low collider is 16 px,
## standing is 34, so a 24 px slot means "slide or crawl".
@export var high_gap: float = 24.0
## Pips per hit. 0 = a calibration beam: a shove back, never a pip.
@export var damage: int = 1
## Applied away from the beam, toward the side Rook came from (x is flipped).
## Calibration presets use (200, -160): the shove decelerates like a hurt
## knockback (air_decel), so it takes that much to land Rook ~30 px back.
@export var knockback: Vector2 = Vector2(140, -200)

@export_group("Pulse")
## Seconds on / off per cycle. pulse_on 0 = always on (no cycle).
@export var pulse_on: float = 0.0
@export var pulse_off: float = 0.0
## The flicker before a pulse comes on: the telegraph (§8: ≥ 0.3 s).
@export var pre_flicker: float = 0.35

@export_group("Sweep")
## Room x the beam travels between. Equal = a static beam at the node's x.
@export var sweep_from: float = 0.0
@export var sweep_to: float = 0.0
@export var sweep_speed: float = 0.0
## Pause at each end: long enough to read where it turns.
@export var end_pause: float = 1.0

@export_group("Rules")
## Rook moving faster than this horizontally reads as a blur (Dash at 400
## passes; falls do not, only |velocity.x| counts).
@export var blur_speed: float = 300.0
## After a trip the beam blinks dark this long, so one mistake is one hit.
@export var rehit_grace: float = 1.0


func pulses() -> bool:
	return pulse_on > 0.0


func sweeps() -> bool:
	return not is_equal_approx(sweep_from, sweep_to) and sweep_speed > 0.0


func validate() -> PackedStringArray:
	var out := PackedStringArray()
	if thickness <= 0.0:
		out.append("scanner thickness must be > 0")
	if pulses() and pre_flicker < 0.35:
		out.append("pulsing scanner needs pre_flicker >= 0.35 s (got %.2f)" % pre_flicker)
	if pulses() and pulse_off < pre_flicker:
		out.append("pulse_off (%.2f) must fit the pre_flicker (%.2f)" % [pulse_off, pre_flicker])
	if sweeps() and end_pause < 1.0:
		out.append("sweeping scanner needs end_pause >= 1.0 s (got %.2f)" % end_pause)
	if not is_equal_approx(sweep_from, sweep_to) and sweep_speed <= 0.0:
		out.append("sweep_from != sweep_to needs a sweep_speed > 0")
	if damage < 0:
		out.append("scanner damage must be >= 0")
	if mode == Mode.LOW and low_top <= 0.0:
		out.append("LOW scanner needs low_top > 0")
	if mode == Mode.HIGH and high_gap <= 0.0:
		out.append("HIGH scanner needs high_gap > 0")
	return out
