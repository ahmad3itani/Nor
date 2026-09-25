@tool
class_name GridClamp
extends StaticBody2D
## Grid clamp (M7 Warden Krail boss test, D-071): the Lowlight Grid thesis
## turned into a boss punish. A breaker hit on any of its `circuits` starts a
## countdown, then a slab drops to the 24 px slot: a boss under it takes a
## poise-breaking environmental hit (a long punish window), lesser enemies
## die as on spikes, a standing Rook loses a pip and is shoved out, and a low
## Rook (slide or crouch) is safe, the same read as a Power Shutter's slot.
##
## Lifecycle: INERT (dark) until its room's BossArena starts; READY; WARN ->
## DROP -> HOLD -> RISE -> READY (re-trippable `rearm` s after the hit); DONE
## (raised for good, dark) once the boss is defeated.
## Origin: (x, top_y). `raised_bottom` is the room-space y of the slab's
## bottom edge when raised (-120: Rook passes under standing and jumping).

enum State { INERT, READY, WARN, DROP, HOLD, RISE, DONE }

const COLOR_SLAB := Color("26222f")
const COLOR_EDGE := Color("6b6380")
const AMBER := Color("ffb347")
const RED := Color("e8283c")
const LAMP_OFF := Color("3a3030")
const LAMPS := 5

@export var clamp_id: String = ""
@export var circuits: Array[StringName] = []
@export var timing: ClampTiming
@export var width: float = 64.0:
	set(v):
		width = v
		_rebuild()
@export var raised_bottom: float = -120.0:
	set(v):
		raised_bottom = v
		_rebuild()
@export var slot_height: float = 24.0
@export var attack: AttackData
@export var boss_id: String = "warden_krail"
## In-arena teaching line (shown once per profile via hint_<arm_hint_id>).
@export var arm_hint_id: String = ""
@export var arm_hint: String = ""

var state: State = State.INERT
var state_time: float = 0.0
## Seconds until the clamp can be tripped again (counts from the hit).
var rearm_left: float = 0.0
## Current bottom edge, px below the clamp's origin.
var bottom: float = 0.0
var boss: Enemy
var last_staggered: bool = false
var _floor_y: float = 0.0
## The clamp's origin y in room space (raised_bottom and the floor are room
## coordinates; `bottom` is local).
var _origin_y: float = 0.0
var _armed_time: float = 0.0
var _hint_pending: bool = false
var _tripper: Player
## Instance ids of enemies the resting slab ignores until the rise ends. Ids,
## not typed references: one may be freed before then (a typed loop variable
## over a freed instance errors before any validity check can run).
var _excepted: Array[int] = []
var _shape_node: CollisionShape2D
var _rect_shape: RectangleShape2D
var _hazard_attack: AttackData


func _ready() -> void:
	collision_layer = CombatLayers.WORLD
	collision_mask = 0
	_origin_y = position.y
	var room := _room()
	if room and not Engine.is_editor_hint():
		var p := Breaker.room_position(self, room)
		_origin_y = p.y
		var f := Breaker.floor_below(room, p.x, p.x + width, raised_bottom)
		if f != INF:
			_floor_y = f
	bottom = raised_bottom - _origin_y
	_rebuild()
	if Engine.is_editor_hint():
		return
	# Spikes' attack: lesser enemies under the clamp die outright, as on spikes.
	_hazard_attack = load("res://data/combat/hazard_attack.tres") as AttackData
	EventBus.boss_started.connect(_on_boss_started)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.breaker_hit.connect(_on_breaker_hit)
	if Game.has_flag("%s_defeated" % boss_id):
		_set_state(State.DONE)


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _shape_node == null:
		_shape_node = CollisionShape2D.new()
		_rect_shape = RectangleShape2D.new()
		_shape_node.shape = _rect_shape
		add_child(_shape_node)
	if Engine.is_editor_hint():
		bottom = raised_bottom - position.y
		_floor_y = 0.0
	_apply_bottom()


func _apply_bottom() -> void:
	if _rect_shape == null:
		return
	var h := maxf(bottom, 1.0)
	_rect_shape.size = Vector2(width, h)
	_shape_node.position = Vector2(width * 0.5, h * 0.5)
	queue_redraw()


## Room-space y of the slab's bottom when dropped (the 24 px slot).
func dropped_y() -> float:
	return _floor_y - slot_height


## x-range and height of what the clamp hits, in global coordinates: the
## column under the raised slab down to the floor.
func footprint() -> Rect2:
	var room := _room()
	var origin := room.global_position if room else Vector2.ZERO
	return Rect2(Vector2(global_position.x, origin.y + raised_bottom), Vector2(width, _floor_y - raised_bottom))


# --- Lifecycle --------------------------------------------------------------------

func _on_boss_started(b: Node2D, _title: String) -> void:
	if state != State.INERT or not is_instance_valid(b):
		return
	var room := _room()
	if room == null or not room.is_ancestor_of(b):
		return
	boss = b as Enemy
	_set_state(State.READY)
	_armed_time = 0.0
	_hint_pending = arm_hint_id != "" and arm_hint != "" and not Game.has_flag("hint_" + arm_hint_id)


func _on_boss_defeated(id: String) -> void:
	if id != boss_id or state == State.DONE:
		return
	_retire()


## Up for good, dark (the fight is over).
func _retire() -> void:
	_clear_exceptions()
	bottom = raised_bottom - _origin_y
	_apply_bottom()
	_hint_pending = false
	_set_state(State.DONE)


func _on_breaker_hit(c: StringName) -> void:
	if not circuits.has(c) or state != State.READY or timing == null:
		return
	if rearm_left > 0.0:
		return
	var room := _room()
	# The credit goes to Rook (whoever struck the breaker): the clamp is his
	# environmental weapon, so Core, style and Demolitionist all apply.
	_tripper = room.player if room and is_instance_valid(room.player) else null
	rearm_left = timing.rearm
	_set_state(State.WARN)
	AudioManager.play_sfx(&"ui_tick")
	for circuit in circuits:
		for b in Breaker.on_circuit(get_tree(), circuit):
			b.show_recharge(timing.rearm)


func _set_state(s: State) -> void:
	state = s
	state_time = 0.0
	queue_redraw()


func state_name() -> String:
	return State.keys()[state]


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if state == State.INERT or state == State.DONE:
		return
	if state != State.READY or rearm_left > 0.0:
		queue_redraw()
	state_time += delta
	# The teaching line counts from the fight start, not from under the intro.
	if not Cinematics.locks_input():
		_armed_time += delta
	rearm_left = maxf(rearm_left - delta, 0.0)
	if boss != null and not is_instance_valid(boss):
		boss = null
	_update_hint()
	if timing == null:
		return
	var raised := raised_bottom - _origin_y
	var dropped := dropped_y() - _origin_y
	match state:
		State.WARN:
			if state_time >= timing.warn:
				_set_state(State.DROP)
		State.DROP:
			# The slab falls visually; its collider joins at the slam, after
			# the hits resolve, so it never grinds into a body mid-fall.
			bottom = lerpf(raised, dropped, minf(state_time / timing.drop, 1.0))
			queue_redraw()
			if state_time >= timing.drop:
				_slam()
				bottom = dropped
				_apply_bottom()
				_set_state(State.HOLD)
		State.HOLD:
			if state_time >= timing.hold:
				_set_state(State.RISE)
		State.RISE:
			bottom = lerpf(dropped, raised, minf(state_time / timing.rise, 1.0))
			_apply_bottom()
			if state_time >= timing.rise:
				_clear_exceptions()
				_set_state(State.READY)


func _update_hint() -> void:
	if not _hint_pending or timing == null:
		return
	# Never during the boss intro card, even if the boss starts under it.
	if _armed_time < timing.hint_min:
		return
	var under := false
	if boss != null and not boss.is_dead():
		var r := boss.body_rect()
		under = r.position.x < global_position.x + width and r.end.x > global_position.x
	if not under and _armed_time < timing.hint_delay:
		return
	_hint_pending = false
	if Game.has_flag("hint_" + arm_hint_id):
		return
	Game.set_flag("hint_" + arm_hint_id)
	EventBus.hint_requested.emit(arm_hint, timing.hint_seconds)
	for circuit in circuits:
		for b in Breaker.on_circuit(get_tree(), circuit):
			b.pulse(timing.hint_seconds)


## The drop lands: resolve everything under the slab.
func _slam() -> void:
	var fp := footprint()
	var staggered := false
	for n in get_tree().get_nodes_in_group(&"enemies"):
		var e := n as Enemy
		if e == null or e.is_dead() or not _room().is_ancestor_of(e):
			continue
		if not fp.intersects(e.body_rect()):
			continue
		var is_boss := e == boss or (e.data != null and String(e.data.id) == boss_id)
		var hit := _hit_for(attack if is_boss else _hazard_attack, e)
		e.receive_hit(hit)
		if is_boss and e.ai == Enemy.AI.STAGGER:
			staggered = true
		# The slab rests on whatever it hit: no physics fight with it.
		if not e.is_dead():
			e.add_collision_exception_with(self)
			_excepted.append(e.get_instance_id())
	_hit_player()
	last_staggered = staggered
	AudioManager.play_sfx(&"boss_slam")
	EventBus.camera_shake_requested.emit(attack.camera_trauma if attack else 0.3)
	EventBus.clamp_dropped.emit(clamp_id, staggered)


func _hit_for(a: AttackData, e: Enemy) -> HitInfo:
	var credited: Node2D = _tripper if is_instance_valid(_tripper) else null
	var hit := HitInfo.create(credited, a, a.knockback, Vector2.DOWN, [&"environmental"] as Array[StringName])
	hit.source_position = Vector2(e.global_position.x, global_position.y + bottom)
	if credited is Player:
		hit.damage_mult = Game.circuit_mult(&"environmental_damage")
	return hit


## Standing Rook in the press: 1 pip and a shove out sideways, to the side
## nearer his centre unless a wall or block is there (then the other side), so
## he is never placed inside geometry. Low Rook (16 px) fits under the 24 px
## slot and is safe.
func _hit_player() -> void:
	var room := _room()
	if room == null or not is_instance_valid(room.player):
		return
	var p := room.player
	var r := PowerShutter._player_rect(p)
	var press := Rect2(Vector2(global_position.x, room.global_position.y + raised_bottom),
		Vector2(width, dropped_y() - raised_bottom))
	if not press.grow(-0.5).intersects(r):
		return
	var cx := global_position.x + width * 0.5
	var side := -1.0 if p.global_position.x < cx else 1.0
	var half := r.size.x * 0.5
	if not _side_free(p, side, r):
		side = -side
	p.global_position.x = _out_x(side, half)
	if not p.combat.dead and p.combat.hurt_invuln_timer <= 0.0:
		var kb := Vector2(side * p.combat.config.hurt_knockback.x, p.combat.config.hurt_knockback.y)
		p.combat.take_damage(1, kb, attack.hitstop if attack else 0.08, true, "clamp")
	else:
		# Only reached from the slam, which needs timing.
		p.combat.shove(Vector2(side * timing.shove.x, timing.shove.y))


## Where Rook's centre goes when shoved out on `side` (1 px clear).
func _out_x(side: float, half: float) -> float:
	return global_position.x - half - 1.0 if side < 0.0 else global_position.x + width + half + 1.0


## True if Rook's standing body fits just outside the footprint on `side`
## (solid world only: one-way platforms never block a body sideways).
func _side_free(p: Player, side: float, r: Rect2) -> bool:
	var shape := RectangleShape2D.new()
	shape.size = r.size - Vector2(1.0, 1.0)
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, Vector2(_out_x(side, r.size.x * 0.5), r.get_center().y))
	q.collision_mask = CombatLayers.WORLD
	q.exclude = [get_rid(), p.get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


func _clear_exceptions() -> void:
	for id in _excepted:
		var e := instance_from_id(id) as Enemy
		if e != null:
			e.remove_collision_exception_with(self)
	_excepted.clear()


func _room() -> Room:
	var n := get_parent()
	while n and not n is Room:
		n = n.get_parent()
	return n as Room


# --- Telegraph --------------------------------------------------------------------

func _draw() -> void:
	var dark := state == State.INERT or state == State.DONE
	var floor_local := _floor_y - _origin_y
	# Housing and slab.
	draw_rect(Rect2(0, 0, width, bottom), COLOR_SLAB.darkened(0.3) if dark else COLOR_SLAB)
	draw_rect(Rect2(0, bottom - 3.0, width, 3.0), COLOR_EDGE if dark else (RED if state == State.DROP or state == State.HOLD else AMBER.darkened(0.4)))
	var x := 4.0
	while x < width - 2.0:
		draw_line(Vector2(x, 2.0), Vector2(x, bottom - 5.0), Color(0, 0, 0, 0.25), 1.0)
		x += 8.0
	if dark:
		return
	# Lamps on the slab face: count down the warning, then show the recharge.
	var lit := 0
	var c := AMBER
	if state == State.WARN and timing:
		lit = ceili(LAMPS * (1.0 - state_time / timing.warn))
	elif state == State.DROP or state == State.HOLD:
		lit = LAMPS
		c = RED
	elif timing and timing.rearm > 0.0:
		lit = LAMPS - ceili(LAMPS * rearm_left / timing.rearm)
		c = AMBER if rearm_left <= 0.0 else AMBER.darkened(0.45)
	for i in LAMPS:
		draw_rect(Rect2(width * 0.5 - 14.0 + i * 6.0, bottom - 10.0, 4.0, 3.0), c if i < lit else LAMP_OFF)
	# Floor stripe under the footprint; it pulses while the clamp warns.
	var a := 0.35
	if state == State.WARN:
		a = 0.5 + 0.5 * sin(state_time * TAU * 4.0)
	draw_rect(Rect2(0, floor_local - 2.0, width, 2.0), Color(AMBER, a))


## HitboxView hook: footprint, state and timers (global coordinates).
func debug_draw(canvas: CanvasItem) -> void:
	var fp := footprint()
	canvas.draw_rect(fp, Color(1.0, 0.7, 0.28, 0.9), false, 1.0)
	var text := "%s %s t%.2f rearm %.1f" % [clamp_id, state_name(), state_time, rearm_left]
	canvas.draw_string(ThemeDB.fallback_font, fp.position + Vector2(0, -2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)


# --- Content protocol (ContentValidator) ------------------------------------------

func content_flags() -> Dictionary:
	var consumes: Array = []
	for c in circuits:
		consumes.append("circuit:%s" % c)
	var produces: Array = []
	if arm_hint_id != "":
		produces.append("hint_" + arm_hint_id)
	return {"produces": produces, "consumes": consumes}


func content_errors(_room_node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if circuits.is_empty():
		out.append("clamp %s has no circuits" % clamp_id)
	if timing == null:
		out.append("clamp %s has no timing" % clamp_id)
	if attack == null:
		out.append("clamp %s has no attack" % clamp_id)
	if arm_hint_id != "" and arm_hint == "":
		out.append("clamp %s has arm_hint_id but no arm_hint text" % clamp_id)
	return out
