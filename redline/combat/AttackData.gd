class_name AttackData
extends Resource
## One attack, player or enemy (bible §8 "Attack data"). Timings are seconds
## from the attack's start. Knockback and hitbox are in *facing space*: +x is
## "forward", -y is up, origin at the attacker's feet.

@export var id: StringName

@export_group("Timing")
## Wind-up before the hitbox is live. For enemies this is the telegraph.
@export var startup: float = 0.06
@export var active: float = 0.06
@export var recovery: float = 0.15
## From this time on, the attack may be cancelled into the next attack or a jump.
@export var cancel_time: float = 0.12
## From this time on, the attack may be cancelled into a dodge/dash.
@export var evade_cancel_time: float = 0.0

@export_group("Hit")
@export var damage: float = 10.0
## Poise (stagger) damage. When an enemy's poise hits 0 it staggers.
@export var poise_damage: float = 10.0
@export var knockback: Vector2 = Vector2(80, 0)
## Freeze-frame on hit for attacker and victim, before Settings.hitstop_scale.
@export var hitstop: float = 0.05
@export var hitbox: Rect2 = Rect2(2, -30, 26, 22)
## 0 = unlimited targets per swing.
@export var max_targets: int = 0
## Ignores frontal guards (Shield enemies).
@export var breaks_guard: bool = false
@export var camera_trauma: float = 0.0

@export_group("Style & Reactor")
## Tag used for style variety: repeating the same tag gives diminishing style.
@export var style_tag: StringName = &"light"
@export var style_points: float = 20.0
@export var reactor_gain: float = 1.0

@export_group("Attacker motion")
## Forward speed set on the attacker at the start (ground lunge).
@export var lunge_speed: float = 60.0
## Fraction of existing horizontal speed kept when attacking out of a run/dash.
@export_range(0.0, 1.0) var momentum_keep: float = 0.5
@export var ground_friction: float = 900.0
## If true, airborne attackers get their vertical speed set to air_velocity_y (air hang).
@export var sets_air_velocity: bool = false
@export var air_velocity_y: float = -40.0
@export var air_gravity_scale: float = 0.5

@export_group("Projectile")
## Null for melee. When set, the attack fires projectiles instead of using the hitbox.
@export var projectile: ProjectileData

@export_group("Feedback")
@export var swing_sfx: StringName = &""
@export var hit_sfx: StringName = &"hit"


func total_time() -> float:
	return startup + active + recovery


func is_active_at(t: float) -> bool:
	return t >= startup and t < startup + active


## Hitbox in world space for an attacker at `origin` facing `facing` (+1/-1).
func world_hitbox(origin: Vector2, facing: int) -> Rect2:
	var r := hitbox
	if facing >= 0:
		return Rect2(origin + r.position, r.size)
	return Rect2(Vector2(origin.x - r.end.x, origin.y + r.position.y), r.size)


func world_knockback(facing: int) -> Vector2:
	return Vector2(knockback.x * facing, knockback.y)


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var tag := String(id) if id != &"" else "<unnamed attack>"
	if id == &"":
		errors.append("attack has no id")
	if projectile == null:
		if active <= 0.0:
			errors.append("%s: active must be > 0" % tag)
		if hitbox.size.x <= 0.0 or hitbox.size.y <= 0.0:
			errors.append("%s: hitbox has no area" % tag)
		if cancel_time > total_time():
			errors.append("%s: cancel_time after the attack ends" % tag)
	if startup < 0.0 or recovery < 0.0:
		errors.append("%s: negative timing" % tag)
	if damage < 0.0 or poise_damage < 0.0:
		errors.append("%s: negative damage" % tag)
	if hitstop < 0.0 or hitstop > 0.25:
		errors.append("%s: hitstop should be 0..0.25s" % tag)
	return errors
