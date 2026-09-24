class_name Player
extends CharacterBody2D
## Rook's movement body: owns timers, collision stance and physics helpers.
## Per-mode behaviour lives in player/states/*; tuning lives in PlayerMovementConfig.
##
## Tick order: sample input -> (hitstop: buffer presses only) -> tick timers
## and combat -> state machine -> forgiveness nudges (corner correction, ledge
## step-up) -> move_and_slide -> post-move bookkeeping (coyote, landing, metrics).
## Combat lives in the PlayerCombat child; this body only exposes hitstop and
## forwards hits it receives.

signal jumped(kind: StringName)
signal landed(impact_speed: float)

const ONE_WAY_LAYER_BIT := 3
const WORLD_LAYER_BIT := 1

@export var config: PlayerMovementConfig
## Leave empty to use the session-wide Game.abilities.
@export var abilities: PlayerAbilities

@onready var standing_shape: CollisionShape2D = $StandingShape
@onready var low_shape: CollisionShape2D = $LowShape
@onready var stand_check: ShapeCast2D = $StandCheck
@onready var visual: Node2D = $Visual
@onready var combat: PlayerCombat = $Combat
@onready var hurtbox_shape: CollisionShape2D = $Hurtbox/Shape

var input_source: PlayerInputSource = PlayerInputSource.new()
var state_machine := PlayerStateMachine.new()
var metrics := MovementMetrics.new()
var last_input := PlayerInputFrame.new()

var facing: int = 1
var last_move_x: int = 0
var is_low: bool = false
## Read by combat (M2) to ignore hits during dodge/dash windows.
var invulnerable: bool = false
var jump_cut_available: bool = false
var air_dodges_left: int = 0

var jump_buffer_timer: float = 0.0
var coyote_timer: float = 0.0
var evade_buffer_timer: float = 0.0
var evade_cooldown: float = 0.0
var slide_cooldown: float = 0.0
## Freeze-frame time remaining (bible §8 hitstop). The body doesn't move, but
## presses are still buffered so nothing typed during a freeze is lost.
var hitstop_timer: float = 0.0
var _drop_through_timer: float = 0.0


func _ready() -> void:
	assert(config != null, "Player requires a PlayerMovementConfig")
	if abilities == null:
		abilities = Game.abilities
	apply_config(config)
	_register_states()
	state_machine.state_changed.connect(_on_state_changed)
	state_machine.start(&"idle")


func _register_states() -> void:
	var defs := {
		&"idle": preload("res://player/states/IdleState.gd"),
		&"run": preload("res://player/states/RunState.gd"),
		&"crouch": preload("res://player/states/CrouchState.gd"),
		&"slide": preload("res://player/states/SlideState.gd"),
		&"air": preload("res://player/states/AirState.gd"),
		&"dodge": preload("res://player/states/DodgeState.gd"),
		&"dash": preload("res://player/states/DashState.gd"),
		&"melee": preload("res://player/states/MeleeState.gd"),
		&"hurt": preload("res://player/states/HurtState.gd"),
	}
	for id: StringName in defs:
		state_machine.add_state(defs[id].new(self, id))


## Rebuilds collision stances from config. Safe to call at runtime (hot reload).
func apply_config(new_config: PlayerMovementConfig) -> void:
	config = new_config
	var stand := RectangleShape2D.new()
	stand.size = config.standing_size
	standing_shape.shape = stand
	standing_shape.position = Vector2(0, -config.standing_size.y * 0.5)
	var low := RectangleShape2D.new()
	low.size = config.low_size
	low_shape.shape = low
	low_shape.position = Vector2(0, -config.low_size.y * 0.5)
	# The stand check covers only the head room above the low stance, slightly
	# inset so touching walls or the floor never reports "blocked".
	var head := RectangleShape2D.new()
	head.size = Vector2(config.standing_size.x - 2.0, config.standing_size.y - config.low_size.y - 1.0)
	stand_check.shape = head
	stand_check.position = Vector2(0, -config.low_size.y - head.size.y * 0.5 - 0.5)
	stand_check.target_position = Vector2.ZERO
	_apply_stance()


func _physics_process(delta: float) -> void:
	var input := input_source.sample(config)
	if hitstop_timer > 0.0:
		hitstop_timer -= delta
		_buffer_presses(input)
		combat.buffer_input(input)
		return
	last_input = input
	last_move_x = input.move_x
	_tick_timers(delta, input)
	combat.tick(input, delta)

	var was_on_floor := is_on_floor()
	state_machine.physics_update(input, delta)

	_apply_corner_correction(delta)
	_apply_ledge_forgiveness(delta)
	var pre_move_vy := velocity.y
	move_and_slide()
	_post_move(was_on_floor, pre_move_vy, delta)


func _tick_timers(delta: float, input: PlayerInputFrame) -> void:
	jump_buffer_timer = maxf(jump_buffer_timer - delta, 0.0)
	coyote_timer = maxf(coyote_timer - delta, 0.0)
	evade_buffer_timer = maxf(evade_buffer_timer - delta, 0.0)
	evade_cooldown = maxf(evade_cooldown - delta, 0.0)
	slide_cooldown = maxf(slide_cooldown - delta, 0.0)
	if _drop_through_timer > 0.0:
		_drop_through_timer -= delta
		if _drop_through_timer <= 0.0:
			set_collision_mask_value(ONE_WAY_LAYER_BIT, true)
	_buffer_presses(input)


func _buffer_presses(input: PlayerInputFrame) -> void:
	if input.jump_pressed:
		jump_buffer_timer = config.jump_buffer_time
	if input.dodge_pressed:
		evade_buffer_timer = config.action_buffer_time


func _post_move(was_on_floor: bool, pre_move_vy: float, delta: float) -> void:
	var on_floor := is_on_floor()
	if on_floor:
		air_dodges_left = config.air_dodges
		coyote_timer = 0.0
		if not was_on_floor:
			landed.emit(pre_move_vy)
			EventBus.player_landed.emit(pre_move_vy)
	elif was_on_floor and velocity.y >= 0.0:
		# Walked (or slid/dodged) off a ledge rather than jumping: grant coyote time.
		coyote_timer = config.coyote_time
	metrics.track(global_position, velocity, on_floor, delta)


# --- Motor helpers used by states -------------------------------------------

func apply_gravity(delta: float, input: PlayerInputFrame) -> void:
	var gravity := config.rise_gravity()
	var cap := config.max_fall_speed
	if velocity.y >= 0.0:
		gravity = config.fall_gravity()
	if input.jump_held and is_at_apex():
		gravity = config.rise_gravity() * config.apex_gravity_multiplier
	if velocity.y > 0.0 and input.down_held:
		gravity = config.rise_gravity() * config.fast_fall_gravity_multiplier
		cap = config.fast_fall_speed
	velocity.y = minf(velocity.y + gravity * delta, cap)


## Moves velocity.x toward move_x * speed_cap. Chooses accel/decel/turn/overspeed
## rates so reversing is snappy while momentum above the cap decays gently.
func apply_horizontal(delta: float, move_x: int, grounded: bool,
		speed_cap: float = -1.0, accel_scale: float = 1.0) -> void:
	if speed_cap < 0.0:
		speed_cap = config.max_run_speed
	var vx := velocity.x
	var rate: float
	if move_x != 0 and not is_zero_approx(vx) and signf(vx) != move_x:
		rate = config.ground_turn_accel if grounded else config.air_turn_accel
	elif move_x != 0 and absf(vx) > speed_cap:
		rate = config.ground_overspeed_decel if grounded else config.air_overspeed_decel
	elif move_x != 0:
		rate = (config.ground_accel if grounded else config.air_accel) * accel_scale
	else:
		rate = config.ground_decel if grounded else config.air_decel
	velocity.x = move_toward(vx, move_x * speed_cap, rate * delta)


func is_at_apex() -> bool:
	return not is_on_floor() and absf(velocity.y) < config.apex_speed_threshold


func jump_buffered() -> bool:
	return jump_buffer_timer > 0.0


## height_ratio scales jump height (e.g. the lower slide-jump).
func start_jump(kind: StringName, height_ratio: float = 1.0) -> void:
	jump_buffer_timer = 0.0
	coyote_timer = 0.0
	velocity.y = config.jump_velocity_for_step(get_physics_process_delta_time(), height_ratio)
	jump_cut_available = true
	metrics.jumps += 1
	jumped.emit(kind)


func can_slide() -> bool:
	return slide_cooldown <= 0.0 and absf(velocity.x) >= config.slide_min_entry_speed


func wants_evade() -> bool:
	if evade_buffer_timer <= 0.0 or evade_cooldown > 0.0:
		return false
	return is_on_floor() or air_dodges_left > 0


func evade_state() -> StringName:
	if abilities.dash and (is_on_floor() or abilities.air_dash):
		return &"dash"
	return &"dodge"


func consume_evade_buffer() -> void:
	evade_buffer_timer = 0.0


func can_stand() -> bool:
	if not is_low:
		return true
	stand_check.force_shapecast_update()
	return not stand_check.is_colliding()


## Switches collision stance. Refuses to stand up into a ceiling.
func set_low(low: bool) -> bool:
	if low == is_low:
		return true
	if not low and not can_stand():
		return false
	is_low = low
	_apply_stance()
	return true


func _apply_stance() -> void:
	standing_shape.disabled = is_low
	low_shape.disabled = not is_low
	var size := config.low_size if is_low else config.standing_size
	var box := RectangleShape2D.new()
	box.size = size
	hurtbox_shape.shape = box
	hurtbox_shape.position = Vector2(0, -size.y * 0.5)


func is_on_one_way() -> bool:
	if not is_on_floor():
		return false
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider is CollisionObject2D and (collider as CollisionObject2D).get_collision_layer_value(ONE_WAY_LAYER_BIT):
			return true
	return false


func drop_through() -> void:
	jump_buffer_timer = 0.0
	set_collision_mask_value(ONE_WAY_LAYER_BIT, false)
	_drop_through_timer = 0.2
	global_position.y += 1.0


# --- Forgiveness --------------------------------------------------------------

## Jumping into a ceiling corner by a few pixels slides the player around it
## instead of killing the jump (bible §5 "corner correction").
func _apply_corner_correction(delta: float) -> void:
	if velocity.y >= 0.0 or config.corner_correction_px <= 0:
		return
	var motion := Vector2(0.0, velocity.y * delta)
	if not test_move(global_transform, motion):
		return
	var preferred := int(signf(velocity.x)) if not is_zero_approx(velocity.x) else facing
	for px in range(1, config.corner_correction_px + 1):
		for dir: int in [preferred, -preferred]:
			var shift := Vector2(px * dir, 0.0)
			if test_move(global_transform, shift):
				continue
			if not test_move(global_transform.translated(shift), motion):
				global_position += shift
				return


## Grazing a ledge corner while falling or near the apex steps the player up
## onto it instead of scraping down the wall (bible §5 "ledge forgiveness").
func _apply_ledge_forgiveness(delta: float) -> void:
	if is_on_floor() or config.ledge_forgiveness_px <= 0 or is_zero_approx(velocity.x):
		return
	if velocity.y < -config.apex_speed_threshold:
		return
	var motion := Vector2(velocity.x * delta, 0.0)
	if not test_move(global_transform, motion):
		return
	for px in range(1, config.ledge_forgiveness_px + 1):
		var lift := Vector2(0.0, -px)
		if test_move(global_transform, lift):
			return
		if not test_move(global_transform.translated(lift), motion):
			global_position += lift
			return


# --- Lifecycle ----------------------------------------------------------------

func respawn(at: Vector2, face: int = 1) -> void:
	global_position = at
	velocity = Vector2.ZERO
	facing = face
	jump_buffer_timer = 0.0
	coyote_timer = 0.0
	evade_buffer_timer = 0.0
	evade_cooldown = 0.0
	slide_cooldown = 0.0
	invulnerable = false
	hitstop_timer = 0.0
	is_low = false
	_apply_stance()
	metrics.on_respawn(at)
	combat.reset()
	# Teleports must not be smeared across frames when physics interpolation is on.
	reset_physics_interpolation()
	state_machine.force_state(&"idle")


## Freeze for `seconds` (scaled by the accessibility hitstop setting).
func hitstop(seconds: float) -> void:
	hitstop_timer = maxf(hitstop_timer, seconds * Settings.hitstop_scale)


## Hurtbox entry point (see Hurtbox.receive).
func receive_hit(hit: HitInfo) -> int:
	return combat.receive_hit(hit)


func current_state_id() -> StringName:
	return state_machine.current.id


func current_state_label() -> String:
	return state_machine.current.debug_label()


func _on_state_changed(from_state: StringName, to_state: StringName) -> void:
	EventBus.player_state_changed.emit(from_state, to_state)
