@tool
class_name ChaseDirector
extends Node2D
## A chase set piece (M7, D-073; Rainline's Sweeper). Thesis: keep moving;
## slowing down is what gets you caught (bible §41 chase rooms, §2.1), and
## recovery is fast (§2.8). The director owns the rules, a Pursuer node (made
## at runtime) is only the body.
##
## - The path is a polyline of room floor points in travel order; everything
##   is measured as progress (arc length) along it. lead = Rook - pursuer.
## - IDLE: the pursuer is parked at path[0]. The chase arms when Rook's body
##   overlaps start_area and he either spawned inside it this room load or
##   walked into it moving along the path. Walking in backwards (from the far
##   end) never places a pursuer in front of him.
## - WARN: warn_time of lights and siren; the pursuer is still.
## - CHASE: it advances (catch-up past far_lead). A catch or a pit costs a
##   nonlethal pip and returns Rook to the highest checkpoint he has passed,
##   with the pursuer respawn_lead behind it and a regroup grace.
## - Reaching end_area during the chase sets the done flag at once; the
##   pursuer turns harmless, runs out to its derail point and tips off.
## Only the done flag persists; a room load always resets the chase.
##
## Always at (0, 0) so path, areas and checkpoints are room coordinates.
## Numbers live in a PursuerData (data/world/chase/*.tres).

enum State { IDLE, WARN, CHASE, REGROUP, RUNOUT, DERAIL, DONE }
const STATE_NAMES: PackedStringArray = ["IDLE", "WARN", "CHASE", "REGROUP", "RUNOUT", "DERAIL", "DONE"]

## Default-palette values (authoring view and debug use them as-is); the
## player-facing overlay reads Palette &"chase_warning" / &"chase_danger" (T12).
const AMBER := Color(1.0, 0.83, 0.42, 1.0)
const RED := Color(1.0, 0.23, 0.31, 1.0)
## The distance bar's chevron count (always on, D4 §7.3): the danger level is
## a count as well as a colour. 1 = lead in the far half, 2 = closing,
## 3 = inside near_lead.
const METER_CHEVRON := Vector2(3, 5)
## Off-screen chevron: 6x12, inset 8 px from the nearest view edge.
const CHEVRON := Vector2(6, 12)
const EDGE_INSET := 8.0
const CHEVRON_PULSE_HZ := 4.0
const WARN_SHAKE := 0.2
const HINT_SECONDS := 3.0
## The checkpoint lint: a checkpoint needs this much block top on each side.
const CP_MARGIN := 20.0
## start_area must be this close to the point start_lead along the path, so
## the pursuer's clamp at path[0] never has to bind on a fresh start.
const START_SLACK := 160.0

@export var chase_id: String = "":
	set(v):
		chase_id = v
		queue_redraw()
@export var data: PursuerData
@export var path: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(480, 0)]):
	set(v):
		path = v
		_cum = PackedFloat32Array()
		queue_redraw()
## One entry per segment (path.size() - 1), or empty for 1.0 everywhere.
@export var speed_scale: PackedFloat32Array = PackedFloat32Array()
@export var start_area: Rect2 = Rect2(0, -64, 32, 64):
	set(v):
		start_area = v
		queue_redraw()
@export var end_area: Rect2 = Rect2(448, -64, 32, 64):
	set(v):
		end_area = v
		queue_redraw()

var state: State = State.IDLE
var state_time: float = 0.0
## Catches this room load.
var catches: int = 0
## Smallest lead seen while the pursuer was actually moving (CHASE only).
var min_lead_seen: float = INF
## 0-based index of the checkpoint a catch returns Rook to.
var reached_checkpoint: int = 0
var player_progress: float = 0.0
var pursuer_progress: float = 0.0
var lead: float = 0.0
## Seconds since the chase armed (chase_completed reports it).
var elapsed: float = 0.0
var pursuer: Pursuer

var _cum: PackedFloat32Array = PackedFloat32Array()
var _cp_progress: PackedFloat32Array = PackedFloat32Array()
var _spawn_checked: bool = false
var _was_inside: bool = false
var _warn_hint_shown: bool = false
var _repeat_hint_shown: bool = false
var _tick_left: float = 0.0
var _derail_progress: float = 0.0
var _overlay: _Overlay


## Draws the screen-edge telegraphs above everything in the room (the
## director itself sits with the triggers, below the player).
class _Overlay extends Node2D:
	var painter: Callable

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


func done_flag() -> String:
	return "chase_%s_done" % chase_id


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_build()
	if Game.has_flag(done_flag()):
		_set_state(State.DONE)
		return
	pursuer = Pursuer.new()
	pursuer.name = "Pursuer"
	pursuer.data = data
	pursuer.dir = _dir_sign()
	add_child(pursuer)
	pursuer_progress = 0.0
	pursuer.position = point_at(0.0)
	_overlay = _Overlay.new()
	_overlay.z_index = 60
	_overlay.painter = _draw_overlay
	add_child(_overlay)


func _build() -> void:
	_cum = PackedFloat32Array([0.0])
	for i in range(1, path.size()):
		_cum.append(_cum[i - 1] + path[i - 1].distance_to(path[i]))
	_cp_progress = PackedFloat32Array()
	for cp in checkpoints():
		_cp_progress.append(project(cp.position, 0.0, length()))
	_derail_progress = _find_derail_progress()


# --- Path geometry ----------------------------------------------------------------

func length() -> float:
	if _cum.size() != path.size():
		_build_cum_only()
	return _cum[_cum.size() - 1] if not _cum.is_empty() else 0.0


func _build_cum_only() -> void:
	_cum = PackedFloat32Array([0.0])
	for i in range(1, path.size()):
		_cum.append(_cum[i - 1] + path[i - 1].distance_to(path[i]))


## The point on the path at progress s (clamped to the path).
func point_at(s: float) -> Vector2:
	if path.is_empty():
		return Vector2.ZERO
	if _cum.size() != path.size():
		_build_cum_only()
	if s <= 0.0 or path.size() == 1:
		return path[0]
	for i in range(1, path.size()):
		if s <= _cum[i]:
			var seg := _cum[i] - _cum[i - 1]
			var t := 0.0 if seg <= 0.0 else (s - _cum[i - 1]) / seg
			return path[i - 1].lerp(path[i], t)
	return path[path.size() - 1]


## Index of the segment holding progress s.
func segment_at(s: float) -> int:
	if _cum.size() != path.size():
		_build_cum_only()
	for i in range(1, path.size()):
		if s < _cum[i]:
			return i - 1
	return maxi(path.size() - 2, 0)


func scale_at(s: float) -> float:
	var i := segment_at(s)
	return speed_scale[i] if i < speed_scale.size() else 1.0


## Closest-point projection of `point` onto the path, searching only the
## progress window [lo, hi] (so a switchback never snaps to another leg).
func project(point: Vector2, lo: float, hi: float) -> float:
	if _cum.size() != path.size():
		_build_cum_only()
	var best := clampf(lo, 0.0, length())
	var best_d := INF
	for i in range(1, path.size()):
		var s0 := _cum[i - 1]
		var s1 := _cum[i]
		if s1 < lo or s0 > hi or s1 <= s0:
			continue
		var a := path[i - 1]
		var seg := path[i] - a
		var seg_len := s1 - s0
		var t := clampf((point - a).dot(seg) / (seg_len * seg_len), 0.0, 1.0)
		var s := clampf(s0 + t * seg_len, maxf(lo, s0), minf(hi, s1))
		var d := point.distance_squared_to(a + seg * ((s - s0) / seg_len))
		if d < best_d:
			best_d = d
			best = s
	return best


func checkpoints() -> Array[ChaseCheckpoint]:
	var out: Array[ChaseCheckpoint] = []
	for c in get_children():
		if c is ChaseCheckpoint:
			out.append(c as ChaseCheckpoint)
	return out


func checkpoint_progress(index: int) -> float:
	return _cp_progress[index] if index >= 0 and index < _cp_progress.size() else 0.0


## +1 when the path's first segment runs east (-1 west): the direction in
## which walking into start_area arms the chase.
func _dir_sign() -> int:
	if path.size() < 2:
		return 1
	var d := path[1] - path[0]
	if absf(d.x) > 0.0:
		return int(signf(d.x))
	return 1


## The first point, in travel order, where the path's x reaches
## data.derail_x (the buffer stop), else the path end.
func _find_derail_progress() -> float:
	if data == null:
		return length()
	for i in range(1, path.size()):
		var a := path[i - 1].x - data.derail_x
		var b := path[i].x - data.derail_x
		if a == 0.0:
			return _cum[i - 1]
		if a * b <= 0.0:
			var t := a / (a - b)
			return lerpf(_cum[i - 1], _cum[i], t)
	return length()


# --- Runtime ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or data == null or state == State.DONE:
		return
	var room := _room()
	if room == null or not is_instance_valid(room.player):
		return
	var p := room.player
	state_time += delta
	match state:
		State.IDLE:
			_run_idle(p)
		State.WARN:
			elapsed += delta
			_track_player(p)
			if state_time >= data.warn_time:
				_set_state(State.CHASE)
		State.CHASE:
			elapsed += delta
			_advance(delta)
			_track_player(p)
			min_lead_seen = minf(min_lead_seen, lead)
			if not _check_end(p):
				_check_catch(p)
			_tick_proximity(delta)
		State.REGROUP:
			elapsed += delta
			_track_player(p)
			if pursuer != null:
				pursuer.regroup_left = maxf(data.regroup_time - state_time, 0.0)
			if not _check_end(p) and state_time >= data.regroup_time:
				_set_state(State.CHASE)
		State.RUNOUT:
			pursuer_progress = move_toward(pursuer_progress, _derail_progress, data.runout_speed * delta)
			if is_equal_approx(pursuer_progress, _derail_progress):
				_set_state(State.DERAIL)
				AudioManager.play_sfx(&"boss_slam")
		State.DERAIL:
			if state_time >= data.derail_time:
				if is_instance_valid(pursuer):
					pursuer.queue_free()
				pursuer = null
				_set_state(State.DONE)
	if is_instance_valid(pursuer):
		pursuer.position = point_at(pursuer_progress)
		pursuer.danger = lead < data.near_lead
	if is_instance_valid(_overlay):
		_overlay.queue_redraw()


func _run_idle(p: Player) -> void:
	var inside := body_rect(p).intersects(start_area)
	if not _spawn_checked:
		# First frame of this room load: spawning inside (door, Anchor, transit)
		# arms at once.
		_spawn_checked = true
		_was_inside = inside
		if inside and not p.combat.dead:
			_arm(p)
		return
	# Only entering while moving along the path arms it; a player who arrives
	# from the far end and walks back through never meets a pursuer ahead.
	if inside and not _was_inside and p.velocity.x * _dir_sign() > 0.0 and not p.combat.dead:
		_was_inside = true
		_arm(p)
		return
	_was_inside = inside


func _arm(p: Player) -> void:
	player_progress = project(to_local(p.global_position), 0.0, length())
	pursuer_progress = clampf(player_progress - data.start_lead, 0.0, length())
	lead = player_progress - pursuer_progress
	reached_checkpoint = 0
	elapsed = 0.0
	_set_state(State.WARN)
	EventBus.chase_started.emit(chase_id)
	AudioManager.play_sfx(&"boss_roar")
	EventBus.camera_shake_requested.emit(WARN_SHAKE)
	if not _warn_hint_shown and data.warn_hint != "":
		_warn_hint_shown = true
		EventBus.hint_requested.emit(data.warn_hint, HINT_SECONDS)
	var room := _room()
	if room != null:
		room.pit_override = _on_pit


func _advance(delta: float) -> void:
	var speed := data.speed_at(lead, scale_at(pursuer_progress))
	pursuer_progress = clampf(pursuer_progress + speed * delta, 0.0, length())


func _track_player(p: Player) -> void:
	var feet := to_local(p.global_position)
	player_progress = project(feet, player_progress - data.project_back, player_progress + data.project_fwd)
	lead = player_progress - pursuer_progress
	reached_checkpoint = 0
	for i in _cp_progress.size():
		if _cp_progress[i] <= player_progress:
			reached_checkpoint = i


## Rook's body in director (room) coordinates: feet at the origin.
func body_rect(p: Player) -> Rect2:
	var size := p.config.low_size if p.is_low else p.config.standing_size
	var feet := to_local(p.global_position)
	return Rect2(feet.x - size.x * 0.5, feet.y - size.y, size.x, size.y)


## The pursuer's catch rect: centred on its path x, bottom at path y + catch_bottom.
func catch_rect() -> Rect2:
	var at := point_at(pursuer_progress)
	var size := data.catch_size
	return Rect2(at.x - size.x * 0.5, at.y + data.catch_bottom - size.y, size.x, size.y)


func _check_catch(p: Player) -> void:
	if p.combat.dead:
		return
	if catch_rect().intersects(body_rect(p)) or lead < -data.catch_behind:
		_catch(p, "chase/%s" % chase_id)


## Chase rooms own their pits (Room.pit_override): the same as a catch, still
## nonlethal, and never the last-safe teleport. Returns true (handled) only
## while the chase is live.
func _on_pit(p: Player) -> bool:
	if not (state in [State.WARN, State.CHASE, State.REGROUP]) or p.combat.dead:
		return false
	_catch(p, "pit")
	return true


func _catch(p: Player, source: String) -> void:
	p.hitstop(data.catch_hitstop)
	EventBus.camera_shake_requested.emit(data.catch_shake)
	p.combat.take_damage(data.catch_damage, Vector2.ZERO, 0.0, false, source, true)
	var idx := clampi(reached_checkpoint, 0, maxi(_cp_progress.size() - 1, 0))
	var cp_s := checkpoint_progress(idx)
	var cps := checkpoints()
	var at := to_global(cps[idx].position if idx < cps.size() else point_at(cp_s))
	p.teleport(at)
	p.facing = _dir_sign()
	p.last_safe_position = at
	var room := _room()
	if room != null and room.camera != null:
		room.camera.snap_to_target()
	player_progress = cp_s
	pursuer_progress = clampf(cp_s - data.respawn_lead, 0.0, length())
	lead = player_progress - pursuer_progress
	reached_checkpoint = idx
	_set_state(State.REGROUP)
	catches += 1
	EventBus.chase_caught.emit(chase_id, idx)
	if catches == 2 and not _repeat_hint_shown and data.repeat_hint != "":
		_repeat_hint_shown = true
		EventBus.hint_requested.emit(data.repeat_hint, HINT_SECONDS)


## Rook's centre inside end_area while the chase is live: done, at once.
func _check_end(p: Player) -> bool:
	var body := body_rect(p)
	if not end_area.has_point(body.get_center()):
		return false
	Game.set_flag(done_flag())
	var min_lead := min_lead_seen if is_finite(min_lead_seen) else lead
	EventBus.chase_completed.emit(chase_id, elapsed, catches, min_lead)
	var room := _room()
	if room != null and room.pit_override.is_valid() and room.pit_override.get_object() == self:
		room.pit_override = Callable()
	_set_state(State.RUNOUT)
	return true


func _tick_proximity(delta: float) -> void:
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	AudioManager.play_sfx(&"ui_tick")
	_tick_left = lerpf(0.8, 0.25, clampf(1.0 - lead / maxf(data.far_lead, 1.0), 0.0, 1.0))


func _set_state(s: State) -> void:
	state = s
	state_time = 0.0
	if s == State.DONE:
		set_physics_process(false)
	if not is_instance_valid(pursuer):
		return
	match s:
		State.WARN:
			pursuer.set_mode(Pursuer.Mode.WARN)
		State.CHASE:
			pursuer.set_mode(Pursuer.Mode.CHASE)
			_tick_left = 0.0
		State.REGROUP:
			pursuer.regroup_total = data.regroup_time
			pursuer.regroup_left = data.regroup_time
			pursuer.set_mode(Pursuer.Mode.REGROUP)
		State.RUNOUT:
			pursuer.set_mode(Pursuer.Mode.RUNOUT)
		State.DERAIL:
			pursuer.set_mode(Pursuer.Mode.DERAIL)


func is_active() -> bool:
	return state in [State.WARN, State.CHASE, State.REGROUP]


func state_name() -> String:
	return STATE_NAMES[state]


func _room() -> Room:
	var n := get_parent()
	while n != null:
		if n is Room:
			return n as Room
		n = n.get_parent()
	return null


## The camera's view in director coordinates (Rect2() without a camera).
func view_rect() -> Rect2:
	var room := _room()
	if room == null or room.camera == null:
		return Rect2()
	var cam := room.camera
	var size := cam.get_viewport_rect().size / cam.zoom
	var centre := to_local(cam.get_screen_center_position())
	return Rect2(centre - size * 0.5, size)


## The pursuer's drawn body in director coordinates.
func pursuer_rect() -> Rect2:
	var at := point_at(pursuer_progress)
	return Rect2(at.x - Pursuer.BODY_W * 0.5, at.y + data.rail_y, Pursuer.BODY_W, Pursuer.BODY_H)


# --- Telegraph overlay: off-screen chevron and distance bar -----------------------

func _draw_overlay(canvas: Node2D) -> void:
	if not is_active() or data == null:
		return
	var view := view_rect()
	if view.size == Vector2.ZERO:
		return
	var danger := lead < data.near_lead
	var red := Palette.color(&"chase_danger")
	var colour := Palette.color(&"chase_warning")
	if danger:
		colour = red
		if not Settings.flash_reduction and fmod(elapsed * CHEVRON_PULSE_HZ, 1.0) > 0.5:
			colour = Color(red, 0.35)
	var body := pursuer_rect()
	if not view.intersects(body):
		# Chevron at the nearest view edge, pointing at the pursuer.
		var target := body.get_center()
		var inner := view.grow(-EDGE_INSET)
		var at := Vector2(clampf(target.x, inner.position.x, inner.end.x), clampf(target.y, inner.position.y, inner.end.y))
		var d := (target - at).normalized()
		if d == Vector2.ZERO:
			d = Vector2(-_dir_sign(), 0)
		var side := Vector2(-d.y, d.x)
		var tip := at
		var back := at - d * CHEVRON.x
		canvas.draw_colored_polygon(PackedVector2Array([tip, back + side * CHEVRON.y * 0.5, back - side * CHEVRON.y * 0.5]), colour)
	# Distance bar, bottom-centre: full = far_lead or more.
	var w := 96.0
	var bar := Rect2(view.get_center().x - w * 0.5, view.end.y - 12.0, w, 3.0)
	canvas.draw_rect(bar, Color(0, 0, 0, 0.5))
	var f := clampf(lead / maxf(data.far_lead, 1.0), 0.0, 1.0)
	canvas.draw_rect(Rect2(bar.position, Vector2(w * f, bar.size.y)), colour)
	var near_x := bar.position.x + w * clampf(data.near_lead / maxf(data.far_lead, 1.0), 0.0, 1.0)
	canvas.draw_line(Vector2(near_x, bar.position.y - 1), Vector2(near_x, bar.end.y + 1), red, 1.0)
	# Chevrons right of the bar, one per danger level, in the steady colour
	# (the pulse above never hides the count).
	var solid := red if danger else colour
	for i in meter_level():
		var x := bar.end.x + 4.0 + i * (METER_CHEVRON.x + 2.0)
		var y := bar.get_center().y
		canvas.draw_polyline(PackedVector2Array([Vector2(x, y - METER_CHEVRON.y * 0.5), Vector2(x + METER_CHEVRON.x, y),
			Vector2(x, y + METER_CHEVRON.y * 0.5)]), solid, 1.0)


## The meter's danger level as a chevron count: 3 inside near_lead, 2 in the
## near half of the rest, 1 when the lead is comfortable.
func meter_level() -> int:
	if data == null:
		return 1
	return level_for(lead, data.near_lead, data.far_lead)


static func level_for(p_lead: float, near_lead: float, far_lead: float) -> int:
	if p_lead < near_lead:
		return 3
	if p_lead < (near_lead + far_lead) * 0.5:
		return 2
	return 1


# --- Authoring view and debug ----------------------------------------------------

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	if path.size() >= 2:
		draw_polyline(path, RED, 1.0)
	draw_rect(start_area, Color(0.3, 1.0, 0.4, 0.25))
	draw_rect(end_area, Color(1.0, 0.6, 0.2, 0.25))


## HitboxView hook (dev console): the path with speed scales, numbered
## checkpoints, the start/end rects, the catch rect and lead/min over Rook, in
## global coordinates.
func debug_draw(canvas: CanvasItem) -> void:
	if data == null or path.size() < 2:
		return
	var font := ThemeDB.fallback_font
	var g := PackedVector2Array()
	for pt in path:
		g.append(to_global(pt))
	canvas.draw_polyline(g, RED, 1.0)
	for i in range(1, path.size()):
		var mid := (g[i - 1] + g[i]) * 0.5
		var sc := speed_scale[i - 1] if i - 1 < speed_scale.size() else 1.0
		canvas.draw_string(font, mid + Vector2(0, -4), "x%.2f" % sc, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, RED)
	var cps := checkpoints()
	for i in cps.size():
		var at := to_global(cps[i].position)
		canvas.draw_line(at, at + Vector2(0, -24), AMBER, 1.0)
		canvas.draw_string(font, at + Vector2(2, -26), "CP%d (%d)" % [i + 1, i], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, AMBER)
	canvas.draw_rect(Rect2(to_global(start_area.position), start_area.size), Color.GREEN, false, 1.0)
	canvas.draw_rect(Rect2(to_global(end_area.position), end_area.size), Color.ORANGE, false, 1.0)
	if is_instance_valid(pursuer):
		var c := catch_rect()
		canvas.draw_rect(Rect2(to_global(c.position), c.size), Color.YELLOW if state != State.RUNOUT else Color.GRAY, false, 1.0)
	var room := _room()
	if room != null and is_instance_valid(room.player):
		var over := room.player.global_position + Vector2(-24, -48)
		var min_text := "-" if not is_finite(min_lead_seen) else "%.0f" % min_lead_seen
		canvas.draw_string(font, over, "%s lead %.0f min %s" % [state_name(), lead, min_text], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)


# --- Content protocol (ContentValidator._check_protocol) ----------------------

func content_errors(room: Node) -> PackedStringArray:
	var errors := PackedStringArray()
	if position != Vector2.ZERO:
		errors.append("must sit at (0, 0) so its path is in room coordinates (at %s)" % position)
	if chase_id == "":
		errors.append("no chase_id")
	if data == null:
		errors.append("no PursuerData")
	if path.size() < 2:
		errors.append("path needs at least 2 points")
		return errors
	_build_cum_only()
	var r := room as Room
	if r != null:
		for pt in path:
			if not r.bounds.has_point(pt):
				errors.append("path point %s is outside the room bounds" % pt)
	if speed_scale.size() != 0 and speed_scale.size() != path.size() - 1:
		errors.append("speed_scale needs 0 or %d entries (has %d)" % [path.size() - 1, speed_scale.size()])
	if data != null:
		var start_point := point_at(data.start_lead)
		if _rect_distance(start_area, start_point) > START_SLACK:
			errors.append("start_area must be within %d px of the point start_lead (%.0f) along the path %s" % [int(START_SLACK), data.start_lead, start_point])
	# Checkpoints: in order along the path, each on a block top with margin.
	var cps := checkpoints()
	if cps.is_empty():
		errors.append("needs at least one ChaseCheckpoint child")
	var blocks: Array[Rect2] = []
	for n in room.find_children("*", "GrayboxBlock", true, false):
		blocks.append(Rect2(_room_pos(n as Node2D, room), (n as GrayboxBlock).size))
	var last := -INF
	for i in cps.size():
		var at := cps[i].position
		var s := project(at, 0.0, length())
		if s <= last:
			errors.append("checkpoint CP%d is not after CP%d along the path" % [i + 1, i])
		last = s
		var standing := false
		for b in blocks:
			if absf(b.position.y - at.y) < 0.5 and at.x >= b.position.x + CP_MARGIN and at.x <= b.end.x - CP_MARGIN:
				standing = true
				break
		if not standing:
			errors.append("checkpoint CP%d at %s must stand on a block top with >= %d px on each side" % [i + 1, at, int(CP_MARGIN)])
	for n in room.find_children("*", "RoomExit", true, false):
		var e := Rect2(_room_pos(n as Node2D, room), (n as RoomExit).size)
		if e.intersects(end_area):
			errors.append("end_area overlaps exit %s (the chase must finish inside the room)" % n.name)
	# The chase lane: the path's box, grown up by the catch height.
	var lane := Rect2(path[0], Vector2.ZERO)
	for pt in path:
		lane = lane.expand(pt)
	lane = lane.grow_individual(0, data.catch_size.y if data != null else 64.0, 0, 1)
	for n in room.find_children("*", "FlowZone", true, false):
		if Rect2(_room_pos(n as Node2D, room), (n as FlowZone).size).intersects(lane):
			errors.append("FlowZone %s overlaps the chase path (no Core drain under pressure)" % n.name)
	for n in room.find_children("*", "Anchor", true, false):
		var ax := _room_pos(n as Node2D, room).x
		if ax >= start_area.position.x:
			errors.append("Anchor %s must be before start_area (x < %.0f), not at %.0f" % [n.name, start_area.position.x, ax])
	return errors


func content_flags() -> Dictionary:
	return {"produces": [done_flag()]}


## Position in the room's coordinates without needing the tree (the validator
## checks rooms that were never added to it).
static func _room_pos(n: Node2D, room: Node) -> Vector2:
	var pos := Vector2.ZERO
	var cur: Node = n
	while cur != null and cur != room:
		if cur is Node2D:
			pos += (cur as Node2D).position
		cur = cur.get_parent()
	return pos


static func _rect_distance(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dy := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return Vector2(dx, dy).length()
