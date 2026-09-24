@tool
class_name CeilingTracker
extends Node2D
## The Collector eye (D-069): an unkillable ceiling-rail watcher that teaches
## "keep moving" in First Pursuit. It is a prop, not an Enemy: no Hurtbox, no
## EncounterDirector token, nothing to kill. It is slower than a running Rook
## and only fires after he has stood in its cone for lock_time, then telegraphs
## (solid red cone + "!") for windup before one dodgeable bolt.
##
## Coordinates: rail_min/rail_max/wake_x/lost_x are in the parent's space (room
## x, since room groups sit at the origin); the node's y is the rail height.
## Numbers live in a TrackerConfig (data/props/collector_eye.tres).

enum State { DORMANT, EMERGE, TRACK, LOCK, COOLDOWN, RETRACT, GONE }
const STATE_NAMES: PackedStringArray = ["DORMANT", "EMERGE", "TRACK", "LOCK", "COOLDOWN", "RETRACT", "GONE"]

## Chest height above Rook's feet: where the line of sight and the bolt aim.
const CHEST := 20.0
## Lock-timer threshold where the cone starts filling red (readability).
const WARN_AT := 0.5
## How far the eye hangs below its hatch when fully out (px).
const DROP := 12.0
const AMBER := Color(1.0, 0.72, 0.3, 0.12)
const RED := Color(1.0, 0.23, 0.31, 1.0)
const HOUSING := Color(0.12, 0.1, 0.12, 1.0)

@export var rail_min: float = 0.0:
	set(v):
		rail_min = v
		queue_redraw()
@export var rail_max: float = 480.0:
	set(v):
		rail_max = v
		queue_redraw()
## Rook at or past this x (and not past lost_x) wakes the eye.
@export var wake_x: float = 0.0:
	set(v):
		wake_x = v
		queue_redraw()
## Rook past this x has escaped: the eye sweeps once and retracts for good.
@export var lost_x: float = 480.0:
	set(v):
		lost_x = v
		queue_redraw()
@export var config: TrackerConfig
## Game.check_condition expression, checked once at _ready: when false the
## node frees itself (e.g. "!flag:collector_drone_defeated").
@export var visible_when: String = ""
## Telemetry id for EventBus.tracker_locked.
@export var tracker_id: String = "collector_eye"

var state: State = State.DORMANT
var state_time: float = 0.0
## Seconds Rook has been continuously in the cone (resets when he leaves it).
var lock_timer: float = 0.0
## Counters for tests and the debug overlay.
var lock_count: int = 0
var bolts_fired: int = 0
## 0 = inside the hatch, 1 = hanging fully out (visual only).
var _drop: float = 0.0
var _spawn_checked: bool = false
var _sweep_from: float = 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if not Game.check_condition(visible_when):
		queue_free()
		return
	position.x = rail_min
	_set_state(State.DORMANT)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or config == null:
		return
	var p := _player()
	if p == null:
		return
	var px := _local_x(p)
	# Frame 1 of this room load: a player who starts past lost_x (backtracking,
	# or respawned beyond the rail) is never hunted from behind.
	if not _spawn_checked:
		_spawn_checked = true
		if px > lost_x:
			_set_state(State.GONE)
			return
	state_time += delta
	match state:
		State.DORMANT:
			if px >= wake_x and px <= lost_x:
				_set_state(State.EMERGE)
				AudioManager.play_sfx(&"gate")
		State.EMERGE:
			_drop = clampf(state_time / maxf(config.emerge_time, 0.001), 0.0, 1.0)
			if state_time >= config.emerge_time:
				_set_state(State.TRACK)
		State.TRACK, State.LOCK, State.COOLDOWN:
			if px > lost_x:
				_sweep_from = position.x
				_set_state(State.RETRACT)
			else:
				_run_active(p, px, delta)
		State.RETRACT:
			_run_retract()
	queue_redraw()


func _run_active(p: Player, px: float, delta: float) -> void:
	match state:
		State.TRACK:
			_follow(px, delta)
			if _in_cone(p):
				lock_timer += delta
				if lock_timer >= config.lock_time:
					lock_count += 1
					_set_state(State.LOCK)
					AudioManager.play_sfx(&"enemy_telegraph")
			else:
				lock_timer = 0.0
		State.LOCK:
			# The eye plants while it winds up: the cone freezes so the
			# telegraph reads as "this spot", and stepping out is the answer.
			if state_time >= config.windup:
				fire_bolt()
				EventBus.tracker_locked.emit(tracker_id)
				lock_timer = 0.0
				_set_state(State.COOLDOWN)
		State.COOLDOWN:
			_follow(px, delta)
			if state_time >= config.cooldown:
				_set_state(State.TRACK)


## One pass across the rail toward where Rook left, then back into the hatch.
func _run_retract() -> void:
	var sweep := maxf(config.sweep_time, 0.001)
	if state_time < sweep:
		position.x = lerpf(_sweep_from, rail_max, state_time / sweep)
		return
	position.x = rail_max
	var t := (state_time - sweep) / maxf(config.retract_time, 0.001)
	_drop = clampf(1.0 - t, 0.0, 1.0)
	if t >= 1.0:
		_set_state(State.GONE)


func _follow(px: float, delta: float) -> void:
	position.x = clampf(move_toward(position.x, px, config.speed * delta), rail_min, rail_max)


func _set_state(s: State) -> void:
	state = s
	state_time = 0.0
	if s != State.LOCK:
		lock_timer = 0.0
	match s:
		State.DORMANT:
			_drop = 0.0
			visible = false
		State.EMERGE, State.TRACK:
			visible = true
		State.GONE:
			_drop = 0.0
			visible = false
			# Once retracted it never returns this room load.
			set_physics_process(false)
	queue_redraw()


## True when Rook stands in the cone: within cone_half_width of the eye's x
## and nothing solid between the eye and his chest. One-way platforms are not
## on the WORLD layer, so they never block; sealed pipe bundles do.
func _in_cone(p: Player) -> bool:
	if p.combat.dead:
		return false
	if absf(_local_x(p) - position.x) > config.cone_half_width:
		return false
	return has_line_of_sight_to(p.global_position + Vector2(0, -CHEST))


func has_line_of_sight_to(point: Vector2) -> bool:
	if not is_inside_tree():
		return false
	var params := PhysicsRayQueryParameters2D.create(global_position, point, CombatLayers.WORLD)
	return get_world_2d().direct_space_state.intersect_ray(params).is_empty()


## Fires the config's bolt at Rook's chest (aimed at fire time). The tracker is
## the attacker: a perfect dodge reports it, but it is no Enemy, so there is no
## enemy credit and death causes read "unknown/collector_eye_bolt".
func fire_bolt() -> void:
	var p := _player()
	if p == null or config == null or config.attack == null or config.attack.projectile == null:
		return
	var proj := config.attack.projectile
	var aim := (p.global_position + Vector2(0, -CHEST) - global_position).normalized()
	var parent: Node = _room() if _room() != null else get_parent()
	for i in proj.pellets:
		var offset := 0.0 if proj.pellets == 1 else lerpf(-proj.spread_deg * 0.5, proj.spread_deg * 0.5, float(i) / (proj.pellets - 1))
		Projectile.spawn(parent, self, config.attack, global_position, aim.rotated(deg_to_rad(offset)), CombatLayers.PLAYER_HURTBOX)
	bolts_fired += 1
	AudioManager.play_sfx(config.attack.swing_sfx)


func state_name() -> String:
	return STATE_NAMES[state]


func _room() -> Room:
	var n := get_parent()
	while n != null:
		if n is Room:
			return n as Room
		n = n.get_parent()
	return null


func _player() -> Player:
	var room := _room()
	if room != null:
		return room.player if is_instance_valid(room.player) else null
	return get_tree().get_first_node_in_group(&"player") as Player


func _local_x(p: Player) -> float:
	var parent := get_parent() as Node2D
	return parent.to_local(p.global_position).x if parent != null else p.global_position.x


# --- Drawing -------------------------------------------------------------------

func _draw() -> void:
	if Engine.is_editor_hint():
		_draw_editor()
		return
	if state == State.DORMANT or state == State.GONE or config == null:
		return
	var eye := Vector2(0, DROP * _drop)
	# The hatch housing on the ceiling, always visible while the eye is out.
	draw_rect(Rect2(-10, -6, 20, 6), HOUSING)
	if state in [State.TRACK, State.LOCK, State.COOLDOWN, State.RETRACT] and _drop > 0.99:
		_draw_cone(eye)
	draw_line(Vector2(0, -2), eye, HOUSING, 2.0)
	draw_circle(eye, 5.0, HOUSING)
	draw_circle(eye, 2.5, RED)
	if state == State.LOCK:
		var font := ThemeDB.fallback_font
		draw_string(font, eye + Vector2(-3, -10), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, RED)


func _draw_cone(apex: Vector2) -> void:
	var floor_local := config.floor_y - position.y
	var w := config.cone_half_width
	var full := PackedVector2Array([apex, Vector2(-w, floor_local), Vector2(w, floor_local)])
	match state:
		State.LOCK:
			var a := 0.45
			if not Settings.flash_reduction:
				a = 0.4 + 0.15 * sin(state_time * TAU * 4.0)
			draw_colored_polygon(full, Color(RED, a))
		State.COOLDOWN, State.RETRACT:
			draw_colored_polygon(full, Color(AMBER, AMBER.a * 0.5))
		_:
			draw_colored_polygon(full, AMBER)
			if lock_timer >= WARN_AT:
				# Red fills down from the apex as the lock builds.
				var f := clampf(lock_timer / config.lock_time, 0.0, 1.0)
				var depth := apex.lerp(Vector2(0, floor_local), f)
				var half := w * f
				draw_colored_polygon(PackedVector2Array([apex, Vector2(-half, depth.y), Vector2(half, depth.y)]), Color(RED, 0.35))


func _draw_editor() -> void:
	# Authoring view: the rail, the wake/lost lines and a cone at rail_min.
	var y0 := 0.0
	draw_line(Vector2(rail_min - position.x, y0), Vector2(rail_max - position.x, y0), RED, 1.0)
	draw_line(Vector2(wake_x - position.x, y0), Vector2(wake_x - position.x, y0 + 64), Color.GREEN, 1.0)
	draw_line(Vector2(lost_x - position.x, y0), Vector2(lost_x - position.x, y0 + 64), Color.ORANGE, 1.0)
	draw_circle(Vector2.ZERO, 5.0, RED)


## HitboxView hook (dev console): state, lock timer, rail, wake/lost lines and
## the cone, in global coordinates.
func debug_draw(canvas: CanvasItem) -> void:
	if config == null:
		return
	var parent := get_parent() as Node2D
	var to_global := func(v: Vector2) -> Vector2: return parent.to_global(v) if parent != null else v
	var y := position.y
	canvas.draw_line(to_global.call(Vector2(rail_min, y)), to_global.call(Vector2(rail_max, y)), RED, 1.0)
	for pair in [[wake_x, Color.GREEN], [lost_x, Color.ORANGE]]:
		canvas.draw_line(to_global.call(Vector2(pair[0], y)), to_global.call(Vector2(pair[0], config.floor_y)), pair[1], 1.0)
	var w := config.cone_half_width
	var apex: Vector2 = to_global.call(position)
	var left: Vector2 = to_global.call(Vector2(position.x - w, config.floor_y))
	var right: Vector2 = to_global.call(Vector2(position.x + w, config.floor_y))
	canvas.draw_polyline(PackedVector2Array([apex, left, right, apex]), RED if state == State.LOCK else Color.YELLOW, 1.0)
	canvas.draw_string(ThemeDB.fallback_font, apex + Vector2(8, 4), "%s %.2f" % [state_name(), lock_timer],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)


# --- Content protocol (ContentValidator._check_protocol) ----------------------

func content_errors(_room_node: Node) -> PackedStringArray:
	var errors := PackedStringArray()
	if rail_min >= rail_max:
		errors.append("rail_min %s must be < rail_max %s" % [rail_min, rail_max])
	if wake_x > rail_min + 64.0:
		errors.append("wake_x %s must be <= rail_min + 64 (the eye must wake near its hatch)" % wake_x)
	if lost_x <= rail_max:
		errors.append("lost_x %s must be > rail_max %s (it retracts only once Rook is past the rail)" % [lost_x, rail_max])
	if config == null:
		errors.append("no TrackerConfig")
	else:
		for e in config.validate():
			errors.append(e)
	return errors


func content_flags() -> Dictionary:
	return {"conditions": [visible_when] if visible_when != "" else []}
