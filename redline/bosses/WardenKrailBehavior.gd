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

var phase: int = 1
var _last_attack: StringName = &""
var _pause: float = 0.0
var _home: Vector2
var _rng := RandomNumberGenerator.new()
## Physics frames since setup (the crackle clock).
var _frame: int = 0


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
	if summon_scene:
		for off in summon_offsets:
			var e := summon_scene.instantiate() as Enemy
			e.position = _home + off
			enemy.get_parent().add_child.call_deferred(e)


func draw_extras(canvas: Node2D) -> void:
	var size := enemy.data.body_size
	# Shock baton on the facing side; crackles in phase 2.
	var x := size.x * 0.5 if enemy.facing > 0 else -size.x * 0.5 - 3.0
	canvas.draw_rect(Rect2(x, -size.y + 12.0, 3, 20), Color("7fd7ff"))
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
