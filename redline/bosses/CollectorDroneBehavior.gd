extends EnemyBehavior
## Collector Drone, the Undercity boss and the game's first (bible §23:
## "first boss builds confidence"; D-064). One screen, no summons, no Flow
## Zone. It plays a deck of four cards, one per Undercity skill:
##   Drop Press  - spacing: step out of the spotlight, punish it grounded;
##   Tag Volley  - reading shots: step off the frozen line, hit the vent sag;
##   Claw Dive   - dodging: leave (or dodge through) the floor X;
##   Hook Sweep  - jumping: hop the hook, hit the low hang.
## Every card ends with the drone low enough for a blade attack from the
## floor (feet >= -76 for >= 0.6 s), so the pistol is a reward, never a need.
## Phase 2 (HP <= 50%): shorter tells, a jumpable ground wave after the
## Press, a five-pellet Volley.
##
## Coordinates: lanes and arena limits are absolute room space (x 0 = arena
## left edge, floor y 0), taken relative to the parent node, and never
## relative to the player: a catwalk or airborne player can't drag the drone
## into the ceiling.

const FAMILIES: Dictionary = {
	&"collector_drop_press": &"press", &"collector_drop_press_p2": &"press", &"collector_press_wave": &"press",
	&"collector_tag_volley": &"volley", &"collector_tag_volley_p2": &"volley",
	&"collector_claw_dive": &"dive", &"collector_hook_sweep": &"sweep",
}
const RED := Color("ff3b4f")
const AMBER := Color(1.0, 0.62, 0.2)

@export_group("Lanes (room y)")
@export var cruise_y: float = -144.0
@export var sag_y: float = -76.0
@export var low_y: float = -60.0
## Stalk: hold this far to the player's side, drifting and bobbing.
@export var stalk_offset: float = 200.0
@export var stalk_drift: float = 16.0
@export var stalk_drift_rate: float = 0.7
@export var bob: float = 4.0
@export var bob_rate: float = 2.5
## x limits for every goal the drone flies to. The left limit is 84, not the
## plan's 76: CollectorBay's VentRoof (x 16..64, y -224..-136) blocks the
## 40 px body in the cruise lane anywhere left of x 84, so a goal there could
## never be reached and its card would time out.
@export var arena_x: Vector2 = Vector2(84, 428)
## Lane names for the debug label: feet below floor_lane_y read as "floor";
## the low/cruise split sits low_lane_margin above the low/sag midpoint.
@export var floor_lane_y: float = -12.0
@export var low_lane_margin: float = 20.0

@export_group("Speeds")
@export var stalk_speed: float = 95.0
## Faster than Rook's 150 run, so the Press can always catch up.
@export var setup_speed: float = 200.0
@export var phase2_speed_mult: float = 1.2

@export_group("Cards")
## Dive: horizontal (and vertical) run of the 45 degree path.
@export var dive_run: float = 144.0
@export var press_lock_dx: float = 24.0
@export var sweep_edges: Vector2 = Vector2(80, 424)
## The sweep starts from the other edge if the player stands this close.
@export var sweep_edge_min_gap: float = 60.0
## Setup timeout = distance at commit / setup speed + this.
@export var setup_margin: float = 0.8
## The volley's telegraph line freezes this long before it fires.
@export var aim_freeze: float = 0.3
## Card setup points count as reached within this distance.
@export var in_position_tolerance: float = 6.0
## "On the main floor": the player's last grounded feet y is at least this.
@export var main_floor_min_y: float = -2.0
## Press "in position" also needs the drone this close to cruise height, so
## every drop falls the same distance (a bob is fine, a climb is not).
@export var press_y_tolerance: float = 8.0
## Spotlight under the Press (bible: a 48 px pool Rook steps out of) and, in
## phase 2, the ring where the ground wave will run (px from the centre).
@export var spotlight_width: float = 48.0
@export var wave_ring: Vector2 = Vector2(30, 60)
## Volley vent sag (the punish): sink to sag_y, hold, climb back to cruise.
## sink + hold + climb fits inside the volley's 1.2 s RECOVER.
@export var sag_sink: float = 0.25
@export var sag_hold: float = 0.7
@export var sag_climb: float = 0.25
## After a Dive or Press: fall speed while still above the floor, then a
## small downward press that keeps is_on_floor() true while it skids.
@export var settle_fall_speed: float = 420.0
@export var settle_hold_speed: float = 60.0

@export_group("Phases")
@export_range(0.1, 0.9) var phase2_threshold: float = 0.5
@export var phase2_telegraph_scale: float = 0.85
## Seconds of roar (no attacks, ENGAGE only) when phase 2 starts.
@export var phase_pause: float = 1.5
## Where it climbs during the roar (room space).
@export var pause_point: Vector2 = Vector2(252, -176)

@export_group("Deck")
## Teaching order for the first deck; later decks shuffle deck_p1/deck_p2.
@export var first_deck: Array[StringName] = [&"collector_drop_press", &"collector_tag_volley", &"collector_claw_dive", &"collector_hook_sweep"]
@export var deck_p1: Array[StringName] = [&"collector_drop_press", &"collector_tag_volley", &"collector_claw_dive", &"collector_hook_sweep"]
@export var deck_p2: Array[StringName] = [&"collector_drop_press_p2", &"collector_tag_volley_p2", &"collector_claw_dive", &"collector_hook_sweep"]
@export var rng_seed: int = 11

@export_group("Look")
## Rotors and the red eye (look modules only; the drone has no brain).
@export var looks: EnemyBrain

var phase: int = 1
var speed_mult: float = 1.0
## The committed card being set up (empty while stalking or attacking).
var card: StringName = &""
## Every card started, in order (tests and the debug label read it).
var played: Array[StringName] = []
var last_family: StringName = &""
var setup_timer: float = 0.0
var setup_timeout: float = 0.0
var returns_in_row: int = 0

var _rng := RandomNumberGenerator.new()
var _deck: Array[StringName] = []
var _next_deck: Array[StringName] = []
var _card_from_next: bool = false
var _pause: float = 0.0
var _t: float = 0.0
var _origin: Vector2 = Vector2.ZERO
## Player's last grounded feet y (room space).
var _support_y: float = 0.0
## Direction of travel for the dive / sweep.
var _dir: int = -1
var _sweep_x: float = 0.0
## Landing X of the dive (room x).
var _dive_x: float = 0.0
## WINDUP lock point (room space), INF when the card has none.
var _lock: Vector2 = Vector2.INF
## Family of the attack in progress, and whether it has touched the floor.
var _active_family: StringName = &""
var _grounded: bool = false
var _prev_ai: int = -1
var _sag_from: float = 0.0
var _look_host: ModularBehavior


func setup(owner_enemy: Enemy) -> void:
	super.setup(owner_enemy)
	# Pass through one-way catwalks: dives, presses, stagger and death falls
	# always land on the arena floor.
	enemy.collision_mask = CombatLayers.WORLD
	_rng.seed = rng_seed
	var parent := enemy.get_parent()
	_origin = (parent as Node2D).global_position if parent is Node2D else Vector2.ZERO
	_deck = first_deck.duplicate()
	if looks:
		# Look modules draw through a ModularBehavior; a detached one is enough.
		_look_host = ModularBehavior.new()
		_look_host.brain_override = looks
		_look_host.enemy = enemy


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_look_host):
		_look_host.free()


func attack(id: StringName) -> AttackData:
	for a in enemy.data.attacks:
		if a.id == id:
			return a
	return null


static func family_of(id: StringName) -> StringName:
	return FAMILIES.get(id, &"")


## Room-space position of the drone's feet.
func room_pos() -> Vector2:
	return enemy.global_position - _origin


func to_room(global: Vector2) -> Vector2:
	return global - _origin


func to_global(room: Vector2) -> Vector2:
	return room + _origin


func player_on_main_floor() -> bool:
	return _support_y >= main_floor_min_y


func is_legal(id: StringName) -> bool:
	var f := family_of(id)
	return player_on_main_floor() if f == &"dive" or f == &"sweep" else true


func paused() -> bool:
	return _pause > 0.0


# --- Per-frame ---------------------------------------------------------------------

func tick(delta: float) -> void:
	_t += delta
	if is_instance_valid(enemy.target) and enemy.target.is_on_floor():
		_support_y = to_room(enemy.target.global_position).y
	_check_phase()
	if enemy.ai != _prev_ai:
		_on_ai_changed()
		_prev_ai = enemy.ai
	match enemy.ai:
		Enemy.AI.ENGAGE:
			_tick_setup(delta)
		Enemy.AI.WINDUP:
			_tick_windup(delta)
		Enemy.AI.ACTIVE:
			_lock = Vector2.INF
			if (_active_family == &"dive" or _active_family == &"press") and enemy.is_on_floor():
				_grounded = true
	_settle(delta)
	_vent_sag(delta)


func _on_ai_changed() -> void:
	if enemy.ai == Enemy.AI.RECOVER:
		_sag_from = room_pos().y


## Commit a card when stalking; time out (or drop an illegal card) back into
## the deck.
func _tick_setup(delta: float) -> void:
	if _pause > 0.0 or not is_instance_valid(enemy.target):
		return
	if card == &"":
		_commit()
		return
	_update_setup()
	setup_timer += delta
	if setup_timer > setup_timeout or not is_legal(card):
		_return_card()


func _tick_windup(_delta: float) -> void:
	if _lock != Vector2.INF:
		# Altitude and x lock: every Dive and Press starts from exactly the
		# lock point, so the lunge lands exactly on the floor.
		enemy.velocity = Vector2.ZERO
		enemy.global_position = enemy.global_position.move_toward(to_global(_lock), 1.0)
	if _active_family == &"volley" and enemy.current_attack and enemy.current_attack.lock_aim:
		# The line tracks Rook, then freezes aim_freeze before the shot.
		if enemy.ai_time < scaled_startup(enemy.current_attack) - aim_freeze:
			enemy.attack_aim = enemy._aim_at_target()


## Dive and Press end on the floor: stay there (belt and braces against a
## touchdown a frame early or late) and skid to a stop. ACTIVE settles only
## once it has touched down (before that the lunge is the motion); RECOVER
## and the phase-2 wave's WINDUP always settle, so a drone knocked a few px
## off its lock point still lands instead of hovering through the punish.
func _settle(delta: float) -> void:
	if _active_family != &"dive" and _active_family != &"press":
		return
	match enemy.ai:
		Enemy.AI.ACTIVE:
			if not _grounded:
				return
		Enemy.AI.RECOVER:
			pass
		Enemy.AI.WINDUP:
			if not _is_follow_up(enemy.current_attack):
				return
		_:
			return
	if not enemy.is_on_floor():
		enemy.velocity.y = settle_fall_speed
		return
	enemy.velocity.y = settle_hold_speed
	if enemy.ai == Enemy.AI.ACTIVE:
		# _run_active skips friction for lunge_vertical attacks.
		enemy.velocity.x = move_toward(enemy.velocity.x, 0.0, enemy.data.friction * delta)


## Volley recovery: sink to sag_y, hang there, climb back (the punish).
func _vent_sag(delta: float) -> void:
	if _active_family != &"volley" or enemy.ai != Enemy.AI.RECOVER:
		return
	var t := enemy.ai_time
	var goal := sag_y
	var climb_at := sag_sink + sag_hold
	if t < sag_sink:
		goal = lerpf(_sag_from, sag_y, t / sag_sink)
	elif t > climb_at:
		goal = lerpf(sag_y, cruise_y, clampf((t - climb_at) / sag_climb, 0.0, 1.0))
	var v := (goal - room_pos().y) / delta
	# Pre-compensate the flyer brake Enemy applies after this tick.
	if not is_zero_approx(v):
		v += signf(v) * enemy.data.friction * delta
	enemy.velocity.y = v


## A follow-up (the phase-2 wave) is not one of the drone's openers.
func _is_follow_up(a: AttackData) -> bool:
	return a != null and attack(a.id) == null


## Drop Press tell, part one: the rotors cut for the drop (WINDUP and the
## fall), a silhouette change that reads even over a busy floor.
func rotors_cut() -> bool:
	var a := enemy.current_attack
	return a != null and family_of(a.id) == &"press" and not _is_follow_up(a) \
		and (enemy.ai == Enemy.AI.WINDUP or enemy.ai == Enemy.AI.ACTIVE)


func scaled_startup(a: AttackData) -> float:
	return a.startup * maxf(enemy.telegraph_scale, 0.6)


# --- Phases -------------------------------------------------------------------------

func _check_phase() -> void:
	if phase != 1 or enemy.is_dead() or enemy.health > enemy.data.max_health * phase2_threshold:
		return
	phase = 2
	# Multiply, never assign: a future Boss Assist scale stacks with it.
	enemy.telegraph_scale *= phase2_telegraph_scale
	speed_mult = phase2_speed_mult
	card = &""
	setup_timer = 0.0
	returns_in_row = 0
	_deck = _new_deck()
	_next_deck = []
	_pause = phase_pause
	AudioManager.play_sfx(&"boss_roar")
	EventBus.camera_shake_requested.emit(0.45)
	EventBus.boss_phase_changed.emit(enemy, 2)


# --- Movement -----------------------------------------------------------------------

func engage_velocity(delta: float) -> Vector2:
	face_target()
	if _pause > 0.0:
		# The roar counts down only here (ENGAGE): a staggered or attacking
		# drone finishes that first.
		_pause -= delta
		return _arrive(pause_point, setup_speed * speed_mult)
	if card != &"":
		return _arrive(setup_point(), setup_speed * speed_mult)
	return _arrive(stalk_goal(), stalk_speed * speed_mult)


func _arrive(goal: Vector2, speed: float) -> Vector2:
	var to := to_global(goal) - enemy.global_position
	return to.normalized() * minf(speed, to.length() * 5.0) if to.length() > 0.01 else Vector2.ZERO


## Hold stalk_offset to the player's side at cruise height; the goal ignores
## the player's y. 200 px is off the pistol's 45 degree band (110..178).
func stalk_goal() -> Vector2:
	var px := to_room(enemy.target.global_position).x if is_instance_valid(enemy.target) else room_pos().x
	var side := 1.0 if room_pos().x >= px else -1.0
	var x := clampf(px + side * stalk_offset + stalk_drift * sin(stalk_drift_rate * _t), arena_x.x, arena_x.y)
	return Vector2(x, cruise_y + bob * sin(bob_rate * _t))


func _player_x() -> float:
	return clampf(to_room(enemy.target.global_position).x, arena_x.x, arena_x.y) if is_instance_valid(enemy.target) else room_pos().x


func setup_point() -> Vector2:
	match family_of(card):
		&"press":
			return Vector2(_player_x(), cruise_y)
		&"volley":
			return stalk_goal()
		&"dive":
			return Vector2(_player_x() - _dir * dive_run, cruise_y)
		&"sweep":
			return Vector2(_sweep_x, low_y)
	return stalk_goal()


## Dive side: keep it while its start point fits the arena, else switch.
func _update_setup() -> void:
	if family_of(card) == &"dive":
		var start := _player_x() - _dir * dive_run
		if start < arena_x.x or start > arena_x.y:
			_dir = -_dir


func in_position() -> bool:
	var p := room_pos()
	match family_of(card):
		&"press":
			return absf(p.x - _player_x()) <= press_lock_dx and absf(p.y - cruise_y) <= press_y_tolerance
		&"volley":
			return absf(p.y - cruise_y) <= in_position_tolerance and enemy.has_line_of_sight()
		&"dive", &"sweep":
			return p.distance_to(setup_point()) <= in_position_tolerance
	return false


# --- Deck -----------------------------------------------------------------------------

func _new_deck() -> Array[StringName]:
	var d: Array[StringName] = (deck_p2 if phase == 2 else deck_p1).duplicate()
	for i in range(d.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := d[i]
		d[i] = d[j]
		d[j] = tmp
	return d


func _qualifies(id: StringName) -> bool:
	return family_of(id) != last_family and is_legal(id)


## Deterministic selection: the first card of the current deck (then the
## next deck) that doesn't repeat the last family and is legal now.
func _commit() -> void:
	if _deck.is_empty():
		_deck = _next_deck if not _next_deck.is_empty() else _new_deck()
		_next_deck = []
	var pick: StringName = &""
	_card_from_next = false
	if returns_in_row >= 2:
		# Two setups in a row timed out: force a card that is always legal.
		pick = &"collector_tag_volley" if last_family == &"press" else &"collector_drop_press"
		if phase == 2:
			pick = StringName(String(pick) + "_p2")
		# Remove the card from whichever deck still holds it, so the forced
		# play doesn't add an extra copy to this cycle or the next.
		if _deck.has(pick):
			_deck.erase(pick)
		else:
			_next_deck.erase(pick)
		returns_in_row = 0
	else:
		for id in _deck:
			if _qualifies(id):
				pick = id
				break
		if pick == &"":
			if _next_deck.is_empty():
				_next_deck = _new_deck()
			for id in _next_deck:
				if _qualifies(id):
					pick = id
					_card_from_next = true
					break
			_next_deck.erase(pick)
		else:
			_deck.erase(pick)
	if pick == &"":
		return
	card = pick
	setup_timer = 0.0
	_prepare_card()
	_update_setup()
	var dist := room_pos().distance_to(setup_point())
	setup_timeout = dist / (setup_speed * speed_mult) + setup_margin


func _prepare_card() -> void:
	var px := _player_x()
	var drone_right := room_pos().x >= px
	match family_of(card):
		&"dive":
			_dir = -1 if drone_right else 1
		&"sweep":
			var edge := sweep_edges.y if drone_right else sweep_edges.x
			if absf(px - edge) < sweep_edge_min_gap:
				edge = sweep_edges.x if drone_right else sweep_edges.y
			_sweep_x = edge
			_dir = -1 if edge == sweep_edges.y else 1


func _return_card() -> void:
	if _card_from_next:
		_next_deck.push_front(card)
	else:
		_deck.push_front(card)
	card = &""
	returns_in_row += 1
	_commit()


func choose_attack() -> AttackData:
	_check_phase()
	if _pause > 0.0 or card == &"" or not is_instance_valid(enemy.target):
		return null
	_update_setup()
	if not in_position():
		return null
	return _start_card()


## Locks the committed card's geometry and hands its attack to Enemy.
func _start_card() -> AttackData:
	var a := attack(card)
	var f := family_of(card)
	_lock = Vector2.INF
	match f:
		&"dive":
			_dive_x = _player_x()
			_lock = Vector2(_dive_x - _dir * dive_run, cruise_y)
			enemy.facing = _dir
		&"sweep":
			_lock = Vector2(_sweep_x, low_y)
			enemy.facing = _dir
		&"press":
			_lock = Vector2(room_pos().x, cruise_y)
			face_target()
		_:
			face_target()
	last_family = f
	played.append(card)
	returns_in_row = 0
	_active_family = f
	_grounded = false
	card = &""
	return a


## Test/dev hook: start `id` now from wherever the drone is (skips the setup
## flight; the WINDUP lock still pulls it to the exact start point).
func force_card(id: StringName) -> void:
	card = id
	_prepare_card()
	_update_setup()
	var a := _start_card()
	enemy.current_attack = a
	enemy._attack_hit_ids.clear()
	enemy.attack_aim = enemy._aim_at_target()
	enemy.set_ai(Enemy.AI.WINDUP)


## The dive's landing X in room space (valid once a dive started).
func dive_landing_x() -> float:
	return _dive_x


func sweep_start_x() -> float:
	return _sweep_x


func lock_point() -> Vector2:
	return _lock


func active_family() -> StringName:
	return _active_family


func lane() -> String:
	var y := room_pos().y
	if y > floor_lane_y:
		return "floor"
	if y > (low_y + sag_y) * 0.5 - low_lane_margin:
		return "low"
	return "cruise"


func debug_text() -> String:
	var shown := card if card != &"" else (enemy.current_attack.id if enemy.current_attack else &"-")
	return "%s [%s] setup %.1f/%.1f %s %s p%d" % [shown, family_of(shown), setup_timer, setup_timeout,
		"legal" if card == &"" or is_legal(card) else "ILLEGAL", lane(), phase]


# --- Drawing ---------------------------------------------------------------------------

func draw_extras(canvas: Node2D) -> void:
	var size := enemy.data.body_size
	var floor_y := -room_pos().y
	# Cargo cage of salvage cells (brighter once phase 2 cracks it open).
	var cage := Rect2(-10, 0, 20, 7)
	canvas.draw_rect(cage, Color(0.12, 0.11, 0.14))
	var cell := Color(0.55, 1.0, 0.75, 0.35 if phase == 1 else 0.8)
	for i in 3:
		canvas.draw_rect(Rect2(-8 + i * 6, 2, 4, 3), cell)
	canvas.draw_rect(cage, Color(0.35, 0.33, 0.3), false, 1.0)
	# Amber lamp; it flashes during the volley tell.
	var lamp := AMBER
	if enemy.ai == Enemy.AI.WINDUP and _active_family == &"volley" and int(enemy.ai_time * 12.0) % 2 == 0:
		lamp = Color.WHITE
	canvas.draw_rect(Rect2(enemy.facing * (size.x * 0.5 - 4) - 2, -size.y + 3, 4, 3), lamp)
	if _look_host:
		var cut := rotors_cut()
		for look in looks.looks:
			if cut and look is LookRotor:
				_draw_cut_rotor(canvas, (look as LookRotor).color)
			else:
				look.draw(_look_host, canvas)
	var attack := enemy.current_attack
	var id := attack.id if attack else &""
	if card != &"" and family_of(card) == &"press":
		_draw_spotlight(canvas, floor_y, false)
	if enemy.ai == Enemy.AI.WINDUP and attack:
		var progress := clampf(enemy.ai_time / maxf(scaled_startup(attack), 0.01), 0.0, 1.0)
		match family_of(id):
			&"dive":
				_draw_dive(canvas, floor_y, progress)
			&"sweep":
				_draw_sweep(canvas, floor_y, progress)
			&"press":
				if id == &"collector_press_wave":
					_draw_crack(canvas, progress)
				else:
					_draw_spotlight(canvas, floor_y, true)
	if _active_family == &"sweep" and (enemy.ai == Enemy.AI.WINDUP or enemy.ai == Enemy.AI.ACTIVE or enemy.ai == Enemy.AI.RECOVER):
		# The hook on its cable (its hitbox is 44..58 px under the drone).
		var drop := 44.0 if enemy.ai != Enemy.AI.RECOVER else maxf(8.0, 44.0 - enemy.ai_time * 40.0)
		canvas.draw_line(Vector2(0, 0), Vector2(0, drop), Color(0.5, 0.48, 0.44), 1.0)
		canvas.draw_rect(Rect2(-24, drop, 48, 4 if enemy.ai != Enemy.AI.RECOVER else 2), Color(0.62, 0.58, 0.5))
	if Settings.show_debug_overlay:
		canvas.draw_string(ThemeDB.fallback_font, Vector2(-size.x, -size.y - 14), debug_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)


## Stopped rotor: two short dim stubs instead of the full bar.
func _draw_cut_rotor(canvas: Node2D, color: Color) -> void:
	var size := enemy.data.body_size
	var c := color.darkened(0.5)
	var y := -size.y - 3.0
	canvas.draw_rect(Rect2(-size.x * 0.5 - 3.0, y, 8, 1), c)
	canvas.draw_rect(Rect2(size.x * 0.5 - 5.0, y, 8, 1), c)


## Dotted 45 degree path to the landing X, which fills as the tell runs.
func _draw_dive(canvas: Node2D, floor_y: float, progress: float) -> void:
	var land := to_global(Vector2(_dive_x, 0)) - enemy.global_position
	var from := Vector2(0, -enemy.data.body_size.y * 0.5)
	var c := RED
	c.a = 0.35 + 0.5 * progress
	for i in 12:
		canvas.draw_rect(Rect2(from.lerp(land, float(i) / 12.0) - Vector2(1, 1), Vector2(2, 2)), c)
	var x := land.x
	canvas.draw_line(Vector2(x - 6, floor_y - 6), Vector2(x + 6, floor_y), c, 2.0)
	canvas.draw_line(Vector2(x - 6, floor_y), Vector2(x + 6, floor_y - 6), c, 2.0)
	canvas.draw_rect(Rect2(x - 10, floor_y - 2, 20.0 * progress, 2), c)


## Dashed floor line over the sweep's whole path.
func _draw_sweep(canvas: Node2D, floor_y: float, progress: float) -> void:
	var start := to_global(Vector2(_sweep_x, 0)).x - enemy.global_position.x
	var length := enemy.current_attack.lunge_speed * enemy.current_attack.active
	var c := RED
	c.a = 0.35 + 0.5 * progress
	var dashes := int(length / 12.0)
	for i in dashes:
		var x0 := start + _dir * i * 12.0
		canvas.draw_line(Vector2(x0, floor_y - 1), Vector2(x0 + _dir * 7.0, floor_y - 1), c, 2.0)


## Spotlight in the Collector eye's cone language: amber while tracking,
## filling red from the centre as the lock nears, solid red once locked.
## Phase 2 adds the ring where the ground wave will run.
func _draw_spotlight(canvas: Node2D, floor_y: float, locked: bool) -> void:
	var w := spotlight_width
	var base := Rect2(-w * 0.5, floor_y - 3, w, 3)
	if locked:
		var progress := clampf(enemy.ai_time / maxf(scaled_startup(enemy.current_attack), 0.01), 0.0, 1.0)
		var c := RED
		c.a = 0.55 + 0.4 * progress
		canvas.draw_rect(base, c)
		if phase == 2:
			var ring := RED
			ring.a = 0.35
			var span := wave_ring.y - wave_ring.x
			canvas.draw_rect(Rect2(-wave_ring.y, floor_y - 2, span, 2), ring)
			canvas.draw_rect(Rect2(wave_ring.x, floor_y - 2, span, 2), ring)
		return
	var amber := AMBER
	amber.a = 0.12
	canvas.draw_rect(base, amber)
	var dx := absf(room_pos().x - _player_x())
	var near := clampf(1.0 - (dx - press_lock_dx) / 96.0, 0.0, 1.0)
	var fill := RED
	fill.a = 0.5
	canvas.draw_rect(Rect2(-w * 0.5 * near, floor_y - 3, w * near, 3), fill)


## Phase 2 press: the floor cracks and glows outward before the wave.
func _draw_crack(canvas: Node2D, progress: float) -> void:
	var c := AMBER
	c.a = 0.4 + 0.5 * progress
	var reach := 20.0 + 40.0 * progress
	canvas.draw_line(Vector2(-reach, -1), Vector2(reach, -1), c, 2.0)
	canvas.draw_line(Vector2(-reach * 0.6, -3), Vector2(reach * 0.6, -3), c, 1.0)
