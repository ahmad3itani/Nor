@tool
class_name PowerShutter
extends Gate
## Timed power shutter (M7 Lowlight "Grid" thesis, D-071). A Breaker on the
## same `circuit` opens it on a visible countdown; Rook commits at speed, and
## if he is late he goes low under the last 24 px slot. Once he has fully
## crossed it, it latches open for good (return trips are free, no drop can
## soft-lock). It never lowers onto a body: a safety sensor holds it.
##
## States: CLOSED -> OPEN -> WARN (last `warn` s of open) -> DROP -> SLOT ->
## SEAL -> CLOSED; LATCHED is terminal. It manages its own collider height
## (Gate's shape node, resized here); Gate.gd itself is untouched. Origin:
## top-left of the column, like Gate.
##
## The panel always reaches the real floor: if the authored column ends above
## it (the validator allows up to 48 px), the panel extends down over that
## gap, so a closed or sealed shutter can never be crawled or walked under
## and the slot is exactly `slot_height` above the floor. Gate's `open_flag`
## and `closed` have no effect here (the panel follows `gap`); the validator
## rejects an open_flag on a shutter.

enum State { CLOSED, OPEN, WARN, DROP, SLOT, SEAL, LATCHED }

const LAMPS := 5
const COLOR_PANEL := Color("2d2838")
const COLOR_STRIPE := Color("4a4458")
const AMBER := Color("ffb347")
const RED := Color("e8283c")
const LAMP_OFF := Color("3a3030")
## Posts and lamps sit this far above the floor (eye level for Rook).
const LAMP_BASE := 40.0

@export var shutter_id: String = ""
@export var circuit: StringName = &""
@export var timing: ShutterTiming
## Set when Rook has crossed; a latched shutter starts open on load.
@export var latch_flag: String = ""
## The late, low escape: a sliding or crouched Rook (16 px) fits under.
@export var slot_height: float = 24.0

var state: State = State.CLOSED
## Seconds since the last breaker hit (the pass-margin clock).
var t_open: float = 0.0
## Open gap under the panel, px up from the floor (0 = closed,
## full_height() = fully retracted).
var gap: float = 0.0
## Margin of the last pass (seconds; small = a close call). NAN before one.
var last_margin: float = NAN
var _phase_t: float = 0.0
var _gap_from: float = 0.0
var _tick_left: float = 0.0
var _flash: float = 0.0
var _holding: bool = false
## Side of the column Rook was last fully on (-1 west, 1 east, 0 unknown).
var _side: int = 0
## Gap between the authored column's bottom and the floor under it; the
## panel covers it too.
var _floor_gap: float = 0.0
var _rect_shape: RectangleShape2D


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	var room := _room()
	if room:
		var p := Breaker.room_position(self, room)
		var f := Breaker.floor_below(room, p.x, p.x + size.x, p.y + size.y)
		_floor_gap = 0.0 if f == INF else maxf(f - (p.y + size.y), 0.0)
	EventBus.breaker_hit.connect(_on_breaker_hit)
	EventBus.flag_changed.connect(_on_flag_changed)
	if latch_flag != "" and Game.has_flag(latch_flag):
		_latch(false)
	else:
		_set_gap(0.0)


# --- Gate overrides: the collider follows `gap`, not `closed` ----------------------

## Gate's open_flag and closed do nothing on a shutter: keep them out of the
## inspector so an author does not rely on them.
func _validate_property(property: Dictionary) -> void:
	if property.name == "open_flag" or property.name == "closed":
		property.usage = PROPERTY_USAGE_NO_EDITOR


## Panel travel: the column plus the floor gap under it (top to real floor).
func full_height() -> float:
	return size.y + _floor_gap


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _shape_node == null:
		_shape_node = CollisionShape2D.new()
		add_child(_shape_node)
	_apply()


func _apply() -> void:
	if _shape_node == null:
		queue_redraw()
		return
	var h := full_height() - gap
	# Set directly, not deferred: a breaker hit and a teleport in the same
	# tick must see the doorway already open (breaker hits come from hit
	# queries, never from an Area2D overlap callback).
	if h <= 0.5:
		_shape_node.disabled = true
	else:
		if _rect_shape == null:
			_rect_shape = RectangleShape2D.new()
			_shape_node.shape = _rect_shape
		_rect_shape.size = Vector2(size.x, h)
		_shape_node.position = Vector2(size.x * 0.5, h * 0.5)
		_shape_node.disabled = false
	queue_redraw()


func _set_gap(value: float) -> void:
	gap = clampf(value, 0.0, full_height())
	closed = gap < full_height()
	_apply()


## Panel gap while the slot is showing: `slot_height` above the real floor.
func slot_gap() -> float:
	return clampf(slot_height, 0.0, full_height())


# --- Circuit ----------------------------------------------------------------------

func _on_breaker_hit(c: StringName) -> void:
	if c != circuit or state == State.LATCHED or timing == null:
		return
	# Start or refresh: a later hit while live restarts the countdown, and a
	# hit after the seal re-opens it.
	var was_down := state != State.OPEN and state != State.WARN
	t_open = 0.0
	_phase_t = 0.0
	_tick_left = 0.0
	_holding = false
	_set_state(State.OPEN)
	_set_gap(full_height())
	if was_down:
		AudioManager.play_sfx(&"gate")
	for b in Breaker.on_circuit(get_tree(), circuit):
		b.show_live(timing.open)


func _on_flag_changed(id: String, _v: Variant) -> void:
	if id == latch_flag and latch_flag != "" and Game.has_flag(latch_flag) and state != State.LATCHED:
		_latch(false)


func _set_state(s: State) -> void:
	state = s
	_phase_t = 0.0
	queue_redraw()


func _latch(announce: bool) -> void:
	state = State.LATCHED
	_holding = false
	_set_gap(full_height())
	if latch_flag != "" and not Game.has_flag(latch_flag):
		Game.set_flag(latch_flag)
	if announce:
		AudioManager.play_sfx(&"gate")


# --- Countdown --------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or timing == null:
		return
	_flash = maxf(_flash - delta, 0.0)
	match state:
		State.OPEN, State.WARN:
			t_open += delta
			var left := timing.open - t_open
			if state == State.OPEN and left <= timing.warn:
				_set_state(State.WARN)
			_tick_left -= delta
			if _tick_left <= 0.0:
				AudioManager.play_sfx(&"ui_tick")
				_tick_left = timing.warn_tick if state == State.WARN else timing.tick
			if left <= 0.0:
				_set_state(State.DROP)
				_gap_from = gap
				_flash = 0.15
				AudioManager.play_sfx(&"gate")
			queue_redraw()
		State.DROP:
			t_open += delta
			if _advance(delta, timing.drop, _gap_from, slot_gap(), full_height() - slot_gap()):
				_set_state(State.SLOT)
		State.SLOT:
			t_open += delta
			_phase_t += delta
			if _phase_t >= timing.slot:
				_set_state(State.SEAL)
				_gap_from = gap
		State.SEAL:
			t_open += delta
			if _advance(delta, timing.seal, _gap_from, 0.0, full_height()):
				_set_state(State.CLOSED)
	_track_pass()


## Moves the panel toward `to` over `duration`. Safety sensor: while a body
## overlaps `sensor_h` px of the column (from its top), the panel holds where
## it is and the phase clock stops. DROP senses the final slot panel (a low
## Rook lets it reach the slot, a standing one holds it at open height);
## SEAL senses the whole column (anyone in the slot holds it at slot height).
## Returns true when the move is complete.
func _advance(delta: float, duration: float, from: float, to: float, sensor_h: float) -> bool:
	_holding = _body_in(sensor_h)
	if _holding:
		queue_redraw()
		return false
	_phase_t = minf(_phase_t + delta, duration)
	_set_gap(lerpf(from, to, _phase_t / maxf(duration, 0.001)))
	return _phase_t >= duration


## True if Rook or a live enemy overlaps the top `h` px of the column.
func _body_in(h: float) -> bool:
	var column := Rect2(global_position, Vector2(size.x, h)).grow(-0.5)
	var p := _player()
	if p and column.intersects(_player_rect(p)):
		return true
	for n in get_tree().get_nodes_in_group(&"enemies"):
		var e := n as Enemy
		if e and not e.is_dead() and column.intersects(e.body_rect()):
			return true
	return false


## Latch and pass margin: Rook's collider has fully crossed the column
## (entered on one side, left on the other) while it was open.
func _track_pass() -> void:
	var p := _player()
	if p == null or state == State.LATCHED:
		return
	var r := _player_rect(p)
	var x0 := global_position.x
	var x1 := x0 + size.x
	if r.end.y <= global_position.y or r.position.y >= global_position.y + full_height():
		_side = 0  # above or below the column: not a crossing
		return
	var side := 0
	if r.end.x <= x0:
		side = -1
	elif r.position.x >= x1:
		side = 1
	if side == 0:
		return
	if _side != 0 and side != _side and state != State.CLOSED:
		_passed()
		if state == State.LATCHED:
			return
	_side = side


func _passed() -> void:
	# Standing pass: time left on the open clock. Low pass: time left before
	# the slot starts to seal (negative = squeezed through a held seal).
	if t_open <= timing.open:
		last_margin = timing.open - t_open
	else:
		last_margin = timing.open + timing.drop + timing.slot - t_open
	EventBus.shutter_passed.emit(shutter_id, last_margin)
	_latch(true)


func pass_margin() -> float:
	return last_margin


## Seconds until the panel next moves (debug, tests).
func time_left() -> float:
	if timing == null:
		return 0.0
	match state:
		State.OPEN, State.WARN:
			return maxf(timing.open - t_open, 0.0)
		State.DROP:
			return maxf(timing.drop - _phase_t, 0.0)
		State.SLOT:
			return maxf(timing.slot - _phase_t, 0.0)
		State.SEAL:
			return maxf(timing.seal - _phase_t, 0.0)
	return 0.0


func state_name() -> String:
	return State.keys()[state]


func is_holding() -> bool:
	return _holding


func _room() -> Room:
	var n := get_parent()
	while n and not n is Room:
		n = n.get_parent()
	return n as Room


func _player() -> Player:
	var room := _room()
	if room and is_instance_valid(room.player):
		return room.player
	return null


static func _player_rect(p: Player) -> Rect2:
	var s := p.config.low_size if p.is_low else p.config.standing_size
	return Rect2(p.global_position - Vector2(s.x * 0.5, s.y), s)


# --- Telegraph --------------------------------------------------------------------

func _draw() -> void:
	var floor_y := full_height()
	# Posts: the column frame, so an open shutter still reads as a doorway.
	draw_rect(Rect2(-3, 0, 2, floor_y), COLOR_STRIPE)
	draw_rect(Rect2(size.x + 1, 0, 2, floor_y), COLOR_STRIPE)
	var panel_h := floor_y - gap
	if panel_h > 0.5:
		var col := COLOR_PANEL
		if state == State.SEAL or state == State.CLOSED and t_open > 0.0:
			col = COLOR_PANEL.lerp(RED, 0.35)
		if _flash > 0.0:
			col = AMBER
		draw_rect(Rect2(0, 0, size.x, panel_h), col)
		var y := panel_h - 6.0
		while y > 0.0:
			draw_rect(Rect2(0, y, size.x, 1), COLOR_STRIPE)
			y -= 8.0
		draw_rect(Rect2(0, panel_h - 2.0, size.x, 2), RED if state == State.SEAL else COLOR_STRIPE)
	if state == State.DROP or state == State.SLOT or state == State.WARN:
		# Floor stripe: where the low slot will be.
		var a := 0.9 if state != State.WARN else 0.35
		draw_rect(Rect2(0, floor_y - slot_height, size.x, slot_height), Color(AMBER, 0.12 * a))
		draw_rect(Rect2(-2, floor_y - 1, size.x + 4, 1), Color(AMBER, a))
	# 5-lamp countdown on the left post, bottom lamp = last to go out.
	var lit := 0
	var c := AMBER
	match state:
		State.OPEN:
			lit = ceili(LAMPS * (timing.open - t_open) / timing.open) if timing else 0
		State.WARN:
			lit = ceili(LAMPS * (timing.open - t_open) / timing.open) if timing else 0
			c = AMBER if fmod(t_open, 0.25) < 0.125 else AMBER.darkened(0.5)
		State.DROP, State.SLOT:
			lit = 1
		State.SEAL, State.CLOSED:
			lit = 1 if state == State.SEAL else 0
			c = RED
		State.LATCHED:
			lit = LAMPS
			c = Color("7fd7ff")
	for i in LAMPS:
		var ly := floor_y - LAMP_BASE - i * 5.0
		draw_rect(Rect2(-4, ly, 4, 3), c if i < lit else LAMP_OFF)


## HitboxView hook: collider, state, time left and last margin (global).
func debug_draw(canvas: CanvasItem) -> void:
	canvas.draw_rect(Rect2(global_position, Vector2(size.x, full_height() - gap)), Color(1.0, 0.7, 0.28, 0.9), false, 1.0)
	var m := "-" if is_nan(last_margin) else "%.2f" % last_margin
	var text := "%s %s %.2fs m %s%s" % [shutter_id, state_name(), time_left(), m, " HOLD" if _holding else ""]
	canvas.draw_string(ThemeDB.fallback_font, global_position + Vector2(-8, -4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)


# --- Content protocol (ContentValidator) ------------------------------------------

func content_flags() -> Dictionary:
	var produces: Array = []
	var consumes: Array = []
	if latch_flag != "":
		produces.append(latch_flag)
		consumes.append(latch_flag)
	if circuit != &"":
		consumes.append("circuit:%s" % circuit)
	return {"produces": produces, "consumes": consumes}


func content_errors(room: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if latch_flag == "":
		out.append("shutter %s has no latch_flag (a missed drop could soft-lock)" % shutter_id)
	if circuit == &"":
		out.append("shutter %s has no circuit" % shutter_id)
	if timing == null:
		out.append("shutter %s has no timing" % shutter_id)
	if open_flag != "":
		out.append("shutter %s sets Gate's open_flag, which a shutter ignores (use latch_flag)" % shutter_id)
	var p := Breaker.room_position(self, room)
	var bottom := p.y + size.y
	var f := Breaker.floor_below(room, p.x, p.x + size.x, bottom)
	if f == INF:
		out.append("shutter %s has no solid floor under it" % shutter_id)
	elif f - bottom > 48.0:
		out.append("shutter %s column ends %d px above the floor (max 48)" % [shutter_id, int(f - bottom)])
	return out
