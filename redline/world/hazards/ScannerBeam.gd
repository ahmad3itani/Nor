@tool
class_name ScannerBeam
extends Node2D
## A security scanner beam (M7 Security Station, D-072). A support hazard
## only: it hurts (or, calibration, shoves) Rook when it sees him, and it
## never raises an alarm or a lockdown.
##
## The beam "sees" Rook's collider (12x34 standing, 12x16 low) and nothing
## else: enemies, launched bodies and projectiles pass through. Unlike spikes
## (D-020: positioning only) a scanner respects dodge i-frames, and Rook
## moving faster than `blur_speed` horizontally reads as a blur, so Dash
## passes but a vertical fall does not.
##
## Shape answers the question (colour-blind safe, bible §24):
##   LOW  amber floor bar with upward chevrons -> jump it.
##   HIGH cyan ceiling curtain + a floor stripe marking the 24 px slot -> slide
##        or crawl under it.
##   FULL red full-height line with a pulsing core -> dodge through it.
##
## Clearance windows with the default movement preset at 60 fps
## (test_security measures them against the real player):
##   LOW, run-jump: the design window is takeoff (Rook's centre) between
##       beam - 80 and beam - 21 (59 px, 0.39 s at run speed), which keeps
##       a few px of air under the feet. The exact pass window, where the
##       collider just clears the 20 px bar, is beam - 87 .. beam - 19.
##   FULL, static, dodge: start the dodge with the collider's front edge
##       10..38 px before the beam's near face (29 px, 0.19 s at run speed),
##       the same span from a standstill. The design estimate was 5..33;
##       i-frames begin at 0.02 s, i.e. on the third dodge frame, which
##       shifts the window by about one frame of dodge travel.
##
## Timing: a pulse cycle is OFF (ending in `pre_flicker` of flicker) then ON;
## a sweep starts paused at sweep_from. `phase` delays both clocks. On
## `EventBus.breaker_hit(circuit)` the beam goes OFFLINE for `offline_open`
## seconds (a re-hit refreshes it), with the last `offline_warn` seconds as
## a lamp-strip countdown, like a power shutter. Pulse and sweep clocks keep
## running while offline, so their rhythm stays readable.

enum State { ON, OFF, FLICKER, DARK, OFFLINE }

const COLOR_LOW := Color("ffcf59")
const COLOR_HIGH := Color("59e0e8")
const COLOR_FULL := Color("e8293d")
const COLOR_RAIL := Color(0.55, 0.55, 0.62, 0.8)
const COLOR_LAMP_ON := Color("ffcf59")
const COLOR_LAMP_OFF := Color(0.25, 0.22, 0.28, 1.0)
const LAMPS := 5
const TRIP_TEXT_TIME := 0.8
const FLASH_TIME := 0.15
const HITSTOP := 0.06

@export var beam_id: String = ""
@export var data: ScannerData:
	set(v):
		data = v
		queue_redraw()
## Room px. bottom_y is the floor under the beam; top_y its emitter/ceiling.
@export var top_y: float = -96.0:
	set(v):
		top_y = v
		queue_redraw()
@export var bottom_y: float = 0.0:
	set(v):
		bottom_y = v
		queue_redraw()
## Breaker circuit that takes this beam offline ("" = none).
@export var circuit: StringName = &""
## Seconds offline per breaker hit, and the countdown at its end. Plain
## floats on purpose (no ShutterTiming dependency, D-072).
@export var offline_open: float = 5.5
@export var offline_warn: float = 1.5
## Seconds of delay added to the pulse and sweep clocks.
@export var phase: float = 0.0

## Seconds since the room started (the pulse/sweep clock).
var clock: float = 0.0
## Seconds left of the post-trip blink.
var grace_left: float = 0.0
## Seconds left offline (breaker).
var offline_left: float = 0.0
var trips: int = 0
var _side: int = 0
var _flash_left: float = 0.0
var _trip_text_left: float = 0.0
var _trip_text_pos: Vector2
var _tick_left: float = 0.0


func _ready() -> void:
	# Run after the player moved this frame, so the check sees his real
	# collider, stance and i-frames for this tick.
	process_physics_priority = 10
	if Engine.is_editor_hint():
		return
	EventBus.breaker_hit.connect(_on_breaker_hit)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or data == null:
		return
	clock += delta
	grace_left = maxf(grace_left - delta, 0.0)
	_flash_left = maxf(_flash_left - delta, 0.0)
	_trip_text_left = maxf(_trip_text_left - delta, 0.0)
	if offline_left > 0.0:
		offline_left = maxf(offline_left - delta, 0.0)
		_tick_countdown(delta)
	_check_player()
	queue_redraw()


# --- Timing (pure functions of the clock, so tests read them from data) ------

## The pulse part of the state at clock time `t`: ON, OFF or FLICKER.
func pulse_state_at(t: float) -> State:
	if data == null or not data.pulses():
		return State.ON
	var cycle := data.pulse_on + data.pulse_off
	var local := fposmod(t - phase, cycle)
	if local >= data.pulse_off:
		return State.ON
	if local >= data.pulse_off - data.pre_flicker:
		return State.FLICKER
	return State.OFF


## The beam's room x at clock time `t` (the node's x when static).
func sweep_x_at(t: float) -> float:
	if data == null or not data.sweeps():
		return position.x
	var leg := absf(data.sweep_to - data.sweep_from) / data.sweep_speed
	var cycle := 2.0 * (leg + data.end_pause)
	var s := fposmod(t - phase, cycle)
	if s < data.end_pause:
		return data.sweep_from
	s -= data.end_pause
	if s < leg:
		return lerpf(data.sweep_from, data.sweep_to, s / leg)
	s -= leg
	if s < data.end_pause:
		return data.sweep_to
	s -= data.end_pause
	return lerpf(data.sweep_to, data.sweep_from, s / leg)


func state() -> State:
	if offline_left > 0.0:
		return State.OFFLINE
	if grace_left > 0.0:
		return State.DARK
	return pulse_state_at(clock)


func state_name() -> String:
	return State.keys()[state()]


func is_live() -> bool:
	return state() == State.ON


## True in the last offline_warn seconds of an offline window.
func is_warning() -> bool:
	return offline_left > 0.0 and offline_left <= offline_warn


func beam_x() -> float:
	return sweep_x_at(clock)


## The lethal rect in room px (the parent's space).
func beam_rect() -> Rect2:
	var th := data.thickness if data else 4.0
	var y0 := top_y
	var y1 := bottom_y
	if data:
		match data.mode:
			ScannerData.Mode.LOW:
				y0 = bottom_y - data.low_top
			ScannerData.Mode.HIGH:
				y1 = bottom_y - data.high_gap
	return Rect2(beam_x() - th * 0.5, y0, th, y1 - y0)


# --- Detection -----------------------------------------------------------------

func _room() -> Room:
	var n := get_parent()
	while n != null and not (n is Room):
		n = n.get_parent()
	return n as Room


func _origin() -> Vector2:
	var p := get_parent() as Node2D
	return p.global_position if p else Vector2.ZERO


## Rook's current collider in room px.
func player_rect(p: Player) -> Rect2:
	var size := p.config.low_size if p.is_low else p.config.standing_size
	var feet := p.global_position - _origin()
	return Rect2(feet - Vector2(size.x * 0.5, size.y), size)


func _check_player() -> void:
	var room := _room()
	if room == null or not is_instance_valid(room.player):
		return
	var p := room.player
	var pr := player_rect(p)
	var br := beam_rect()
	var overlaps_x := pr.position.x < br.end.x and pr.end.x > br.position.x
	if not overlaps_x:
		# Remember the approach side: knockback sends Rook back the way he came.
		_side = 1 if pr.get_center().x > br.get_center().x else -1
	if not is_live() or not pr.intersects(br):
		return
	if p.combat.dead or p.invulnerable or p.combat.hurt_invuln_timer > 0.0:
		return
	if absf(p.velocity.x) > data.blur_speed:
		return
	_trip(p, pr)


func _trip(p: Player, pr: Rect2) -> void:
	var side := _side
	if side == 0:
		side = -int(signf(p.velocity.x)) if not is_zero_approx(p.velocity.x) else -p.facing
	var kb := Vector2(side * data.knockback.x, data.knockback.y)
	# The scanner buzz plays on every trip, so calibration sounds like the
	# real thing; only the pip is missing.
	AudioManager.play_sfx(&"block")
	if data.damage > 0:
		p.combat.take_damage(data.damage, kb, HITSTOP, true, "scanner")
	else:
		p.combat.shove(kb)
	grace_left = data.rehit_grace
	trips += 1
	_flash_left = FLASH_TIME
	_trip_text_left = TRIP_TEXT_TIME
	_trip_text_pos = Vector2(pr.get_center().x, pr.position.y) - position
	EventBus.scanner_tripped.emit(beam_id, int(data.mode))


# --- Circuit -------------------------------------------------------------------

func _on_breaker_hit(c: StringName) -> void:
	if circuit == &"" or c != circuit:
		return
	offline_left = offline_open
	_tick_left = 1.0
	# The breaker's lamp is driven by its consumers (Breaker.gd): a circuit
	# that feeds only scanners still shows it live for the offline window.
	for b in Breaker.on_circuit(get_tree(), circuit):
		b.show_live(offline_open)


## Shutter-style ticks: 1 Hz while offline, 4 Hz in the warning.
func _tick_countdown(delta: float) -> void:
	if offline_left <= 0.0:
		return
	_tick_left -= delta
	if is_warning():
		_tick_left = minf(_tick_left, 0.25)
	if _tick_left <= 0.0:
		AudioManager.play_sfx(&"ui_tick")
		_tick_left = 0.25 if is_warning() else 1.0


# --- Content protocol (ContentValidator) --------------------------------------

func content_flags() -> Dictionary:
	if circuit == &"":
		return {}
	return {"consumes": ["circuit:%s" % circuit]}


func content_errors(_room: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if beam_id == "":
		out.append("scanner has no beam_id")
	if data == null:
		out.append("scanner %s has no ScannerData" % beam_id)
		return out
	for e in data.validate():
		out.append("scanner %s: %s" % [beam_id, e])
	if bottom_y <= top_y:
		out.append("scanner %s: bottom_y must be below top_y" % beam_id)
	if data.mode == ScannerData.Mode.HIGH and bottom_y - data.high_gap <= top_y:
		out.append("scanner %s: HIGH beam has no height above its slot" % beam_id)
	if offline_warn > offline_open:
		out.append("scanner %s: offline_warn exceeds offline_open" % beam_id)
	return out


# --- Drawing -------------------------------------------------------------------

func _color() -> Color:
	if data == null:
		return COLOR_FULL
	match data.mode:
		ScannerData.Mode.LOW:
			return COLOR_LOW
		ScannerData.Mode.HIGH:
			return COLOR_HIGH
	return COLOR_FULL


func _flash_reduced() -> bool:
	return not Engine.is_editor_hint() and Settings.flash_reduction


func _draw() -> void:
	if data == null:
		return
	var off := Vector2(-position.x, -position.y)  # room px -> local
	var r := beam_rect()
	r.position += off
	var col := _color()
	var st := State.ON if Engine.is_editor_hint() else state()
	# Emitter housing and, for a sweep, its rail.
	if data.sweeps():
		draw_line(Vector2(data.sweep_from, top_y) + off, Vector2(data.sweep_to, top_y) + off, COLOR_RAIL, 2.0)
	draw_rect(Rect2(r.position.x - 3.0, top_y + off.y - 3.0, r.size.x + 6.0, 4.0), COLOR_RAIL)
	var alpha := 1.0
	match st:
		State.OFF, State.DARK, State.OFFLINE:
			alpha = 0.12
		State.FLICKER:
			alpha = 0.6 if _flash_reduced() else (0.85 if int(clock * 20.0) % 2 == 0 else 0.15)
		State.ON:
			alpha = 0.6 if _flash_reduced() else 0.95
	var c := Color(col, alpha)
	match data.mode:
		ScannerData.Mode.LOW:
			draw_rect(r, c)
			# Upward chevrons along the bar: "go over".
			var cx := r.get_center().x
			var y := r.end.y - 4.0
			while y > r.position.y + 3.0:
				draw_polyline(PackedVector2Array([Vector2(cx - 4, y + 3), Vector2(cx, y), Vector2(cx + 4, y + 3)]), c, 1.0)
				y -= 6.0
		ScannerData.Mode.HIGH:
			draw_rect(r, c)
			# Curtain fringe and the floor stripe marking the open slot.
			draw_rect(Rect2(r.position.x - 4.0, r.end.y - 2.0, r.size.x + 8.0, 2.0), c)
			draw_rect(Rect2(r.position.x - 6.0, bottom_y + off.y - 2.0, r.size.x + 12.0, 2.0), Color(col, 0.7))
			draw_line(Vector2(r.position.x - 6.0, r.end.y), Vector2(r.position.x - 6.0, bottom_y + off.y), Color(col, 0.35), 1.0)
		_:
			draw_rect(r, c)
			if st == State.ON:
				var pulse := 0.5 if _flash_reduced() else 0.5 + 0.5 * sin(clock * 9.0)
				draw_rect(Rect2(r.get_center().x - 0.5, r.position.y, 1.0, r.size.y), Color(1, 1, 1, 0.4 + 0.4 * pulse))
	if st == State.OFFLINE:
		_draw_lamps(r)
	if _flash_left > 0.0:
		var fa := 0.4 if _flash_reduced() else 0.9
		draw_rect(r.grow_individual(3, 0, 3, 0), Color(1, 1, 1, fa * _flash_left / FLASH_TIME))
	if _trip_text_left > 0.0:
		var rise := (1.0 - _trip_text_left / TRIP_TEXT_TIME) * 14.0
		draw_string(ThemeDB.fallback_font, _trip_text_pos + Vector2(-18, -6 - rise), "TRIPPED",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, minf(1.0, _trip_text_left * 3.0)))


## The shutter's 5-lamp countdown on the emitter: lamps go out as the
## offline window runs down; they blink in the warning.
func _draw_lamps(r: Rect2) -> void:
	var lit := int(ceil(offline_left / maxf(offline_open, 0.01) * LAMPS))
	var blink := is_warning() and not _flash_reduced() and int(clock * 8.0) % 2 == 0
	var x0 := r.get_center().x - (LAMPS * 4.0) * 0.5
	var y := top_y - position.y + 3.0
	for i in LAMPS:
		var on := i < lit and not blink
		draw_rect(Rect2(x0 + i * 4.0, y, 3.0, 2.0), COLOR_LAMP_ON if on else COLOR_LAMP_OFF)


## F1 overlay (HitboxView): the lethal rect, state, phase time and sweep x.
func debug_draw(canvas: CanvasItem) -> void:
	if data == null:
		return
	var r := beam_rect()
	r.position += _origin()
	canvas.draw_rect(r, Color(1, 0.3, 0.3, 0.9) if is_live() else Color(0.6, 0.6, 0.6, 0.6), false, 1.0)
	var t := clock - phase
	var label := "%s %s t%.2f" % [beam_id, state_name(), t]
	if data.sweeps():
		label += " x%.0f" % beam_x()
	if offline_left > 0.0:
		label += " off%.1f" % offline_left
	canvas.draw_string(ThemeDB.fallback_font, Vector2(r.position.x - 10, r.position.y - 4), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
