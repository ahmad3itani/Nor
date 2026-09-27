extends EnemyBehavior
## Warden Krail, Lowlight's enforcer and the slice's exam (bible §17, §41:
## the boss tests what the district taught). Phase 1 checks spacing and
## dodging: a two-hit baton, a shock lunge across the arena, and an arc
## burst of slow bolts. Phase 2 (at 50% health) speeds up his wind-ups, adds a ground slam whose
## shockwaves you jump, and calls two Needles once. Heavies/launchers break
## his poise for a long punish window. Never repeats the same attack twice:
## up close he alternates the baton combo with a backstep that re-opens
## space, so the fight breathes between close and far pressure.

@export_range(0.1, 0.9) var phase2_threshold: float = 0.5
@export var phase2_telegraph_scale: float = 0.82
@export var close_range: float = 50.0
@export var far_range: float = 140.0
@export var summon_scene: PackedScene
@export var summon_offsets: Array[Vector2] = [Vector2(-170, 0), Vector2(170, 0)]
## Seconds of roar (no attacks) when phase 2 starts.
@export var phase_pause: float = 1.2

## Phase-2 baton crackle: lit on CRACKLE_ON_FRAMES of every
## CRACKLE_PERIOD_FRAMES physics frames (2.5 Hz at 60 fps), under the 3 Hz
## flash rule (D4 §7.1) in both modes, and counted in physics frames rather
## than wall-clock time so tours and tests see the same frames. Under flash
## reduction the arc is drawn steady instead of blinking.
const CRACKLE_PERIOD_FRAMES := 24
const CRACKLE_ON_FRAMES := 2
## Presentation (T05, F4): the baton is a dark steel shaft with a pale tip,
## off the reserved guard blue.
const BATON_SHAFT := Color("3a3f4a")
const BATON_TIP := Color("cfe4f2")
## Sprite mode: where the phase-2 electric_arc crackle sits (from the feet,
## x toward the facing) and its length scale (the arc row spans 48 px).
const ARC_AT := Vector2(8, -34)
const ARC_SCALE := 0.5
## Attack id -> [wind-up pose, strike pose] on the sprite sheet.
const ANIMS := {
	&"krail_baton_1": [&"windup_baton", &"baton_1"],
	&"krail_baton_2": [&"baton_2", &"baton_2"],
	&"krail_shock_lunge": [&"windup_lunge", &"lunge"],
	&"krail_arc_burst": [&"windup_burst", &"burst"],
	&"krail_ground_slam": [&"windup_slam", &"slam"],
	&"krail_backstep": [&"backstep", &"backstep"],
}

var phase: int = 1
var _last_attack: StringName = &""
var _pause: float = 0.0
var _home: Vector2
var _rng := RandomNumberGenerator.new()
## Physics frames since setup (the crackle clock).
var _frame: int = 0
## Presentation only (T05): the phase-2 arc effect and the slam's one wave.
var _arc: VfxOneShot
var _slam_fx: AttackData


func setup(owner_enemy: Enemy) -> void:
	super.setup(owner_enemy)
	_rng.seed = 7
	_home = owner_enemy.global_position


func attack(id: StringName) -> AttackData:
	for a in enemy.data.attacks:
		if a.id == id:
			return a
	return null


func tick(_delta: float) -> void:
	_frame += 1
	_check_phase()
	_tick_vfx()


func engage_velocity(delta: float) -> Vector2:
	face_target()
	if _pause > 0.0:
		_pause -= delta
		return Vector2.ZERO
	var dx := enemy.target.global_position.x - enemy.global_position.x
	if absf(dx) > close_range - 12.0:
		return Vector2(signf(dx) * enemy.data.move_speed * (1.25 if phase == 2 else 1.0), 0.0)
	return Vector2.ZERO


func choose_attack() -> AttackData:
	_check_phase()
	if _pause > 0.0:
		return null
	var d := distance_to_target()
	var options: Array[StringName] = []
	if d <= close_range:
		options = [&"krail_baton_1", &"krail_backstep"]
		if phase == 2:
			options.append(&"krail_ground_slam")
	elif d <= far_range:
		options = [&"krail_arc_burst", &"krail_shock_lunge"]
		if phase == 2:
			options.append(&"krail_ground_slam")
	else:
		options = [&"krail_shock_lunge", &"krail_arc_burst"]
	if options.size() > 1:
		options.erase(_last_attack)
	var pick := options[_rng.randi_range(0, options.size() - 1)]
	_last_attack = pick
	face_target()
	return attack(pick)


func _check_phase() -> void:
	if phase != 1 or enemy.health > enemy.data.max_health * phase2_threshold or enemy.is_dead():
		return
	phase = 2
	_pause = phase_pause
	enemy.telegraph_scale = phase2_telegraph_scale
	AudioManager.play_sfx(&"boss_roar")
	EventBus.camera_shake_requested.emit(0.45)
	EventBus.boss_phase_changed.emit(enemy, 2)
	_spawn_arc()
	if summon_scene:
		for off in summon_offsets:
			var e := summon_scene.instantiate() as Enemy
			e.position = _home + off
			enemy.get_parent().add_child.call_deferred(e)


func draw_extras(canvas: Node2D) -> void:
	if LookModule.sprite_mode(canvas):
		return  # the sheet draws baton and visor; the arc is an effect
	var size := enemy.data.body_size
	# Shock baton on the facing side (steel, pale tip); crackles in phase 2.
	var x := size.x * 0.5 if enemy.facing > 0 else -size.x * 0.5 - 3.0
	canvas.draw_rect(Rect2(x, -size.y + 12.0, 3, 20), BATON_SHAFT)
	canvas.draw_rect(Rect2(x, -size.y + 12.0, 3, 4), BATON_TIP)
	# Warden's visor.
	canvas.draw_rect(Rect2(-size.x * 0.5 + 3, -size.y + 5, size.x - 6, 3), Color("e8283c"))
	if crackle_visible():
		canvas.draw_line(Vector2(x, -size.y + 12.0), Vector2(x + enemy.facing * 6, -size.y + 4.0), Color.WHITE, 1.0)


## Whether the phase-2 crackle arc is drawn this frame.
func crackle_visible() -> bool:
	return phase == 2 and crackle_lit(_frame, Settings.flash_reduction)


## Pure: the crackle at physics frame `frame` (steady when reduced).
static func crackle_lit(frame: int, reduced: bool) -> bool:
	return reduced or posmod(frame, CRACKLE_PERIOD_FRAMES) < CRACKLE_ON_FRAMES


# --- Presentation (T05) ----------------------------------------------------------------

## Sheet rows: the attack's wind-up / strike pose (RECOVER holds the strike's
## last frame), stagger on a poise break or a Grid Clamp, the roar during
## the phase-2 pause, death. [] = EnemyVisual's generic map (idle, move).
func anim_names(ai: int, a: AttackData) -> Array[StringName]:
	match ai:
		Enemy.AI.DEAD:
			return [&"death"]
		Enemy.AI.STAGGER, Enemy.AI.LAUNCHED:
			return [&"stagger", &"hurt"]
		Enemy.AI.WINDUP, Enemy.AI.ACTIVE, Enemy.AI.RECOVER:
			if a and ANIMS.has(a.id):
				var pair: Array = ANIMS[a.id]
				return [pair[0] if ai == Enemy.AI.WINDUP else pair[1]]
	if phase == 2 and _pause > 0.0:
		return [&"phase2_roar"]
	return []


func _visual_uses_sprite() -> bool:
	var v := enemy.get_node_or_null(^"Visual")
	return v != null and v.has_method(&"uses_sprite") and bool(v.call(&"uses_sprite"))


## Phase 2: an electric_arc on the baton in sprite mode (the placeholder
## keeps its code line). Lit by crackle_lit (2.5 Hz), steady on frame 0
## under flash reduction.
func _spawn_arc() -> void:
	if not _visual_uses_sprite() or is_instance_valid(_arc):
		return
	_arc = VfxOneShot.spawn(enemy.get_parent(), &"electric_arc", &"arc", enemy.position, {"facing": enemy.facing})
	if _arc:
		_arc.scale = Vector2(ARC_SCALE, 1.0)
		_arc.z_index = 1


func _tick_vfx() -> void:
	if enemy == null:
		return  # a bare behavior (crackle clock tests)
	if is_instance_valid(_arc):
		if enemy.is_dead():
			_arc.stop()
			_arc = null
		else:
			_arc.position = enemy.position + Vector2(ARC_AT.x * enemy.facing, ARC_AT.y)
			_arc.sprite.flip_h = enemy.facing < 0
			if _arc.spec:
				_arc.sprite.offset = _arc.spec.offset_for(&"arc", enemy.facing < 0)
			_arc.visible = crackle_visible()
			if Settings.flash_reduction:
				_arc.sprite.pause()
				_arc.sprite.frame = 0
			elif not _arc.sprite.is_playing():
				_arc.sprite.play()
	# The ground slam's impact: one shockwave ground wave at his feet.
	var a := enemy.current_attack
	if enemy.ai == Enemy.AI.ACTIVE and a and a.id == &"krail_ground_slam":
		if _slam_fx != a:
			_slam_fx = a
			VfxOneShot.spawn(enemy.get_parent(), &"shockwave", &"ground_wave", enemy.position, {"facing": enemy.facing})
	else:
		_slam_fx = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_arc):
		_arc.stop()
