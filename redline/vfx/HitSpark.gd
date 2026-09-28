class_name HitSpark
extends CPUParticles2D
## Bright, fast impact sparks (bible §26 "impact sparks"). One-shot, world space.
## Flash reduction (M9 T12, D4 §7.1): half the particles and no white core,
## so a hit never flashes white; the sparks start in their own colour.


static func spawn(parent: Node, at: Vector2, direction_: Vector2, color_: Color, amount_: int = 8,
		speed: float = 140.0) -> HitSpark:
	var s := HitSpark.new()
	var reduced := Settings.flash_reduction
	s.position = at
	s.amount = spark_amount(amount_, reduced)
	s.lifetime = 0.16
	s.one_shot = true
	s.explosiveness = 1.0
	s.direction = direction_.normalized() if direction_ != Vector2.ZERO else Vector2.UP
	s.spread = 55.0
	s.initial_velocity_min = speed * 0.5
	s.initial_velocity_max = speed
	s.damping_min = 300.0
	s.damping_max = 500.0
	s.gravity = Vector2.ZERO
	s.scale_amount_min = 1.0
	s.scale_amount_max = 2.0
	var ramp := Gradient.new()
	ramp.set_color(0, core_color(color_, reduced))
	ramp.set_color(1, Color(color_, 0.0))
	s.color_ramp = ramp
	s.finished.connect(s.queue_free)
	parent.add_child(s)
	s.emitting = true
	return s


## Particle count: halved (at least 1) under flash reduction.
static func spark_amount(amount_: int, reduced: bool) -> int:
	return maxi(floori(amount_ * 0.5) if reduced else amount_, 1)


## The colour a spark starts at: a white core, or the spark colour itself
## under flash reduction.
static func core_color(color_: Color, reduced: bool) -> Color:
	return Color(color_, 1.0) if reduced else Color.WHITE


# --- Sprite sparks (presentation overhaul T06) -------------------------------
# The vfx/hit_sparks sheet replaces the particles when it loads; spawn() above
# stays the placeholder whenever VfxOneShot returns null (missing sheet, cap).

const SHEET := &"hit_sparks"
## Guard/blocked sparks keep the literal guard blue PlayerCombat always used
## (Art Direction "Guard / block"; no palette key holds that hue).
const GUARD_COLOR := Color("7fd7ff")
## AttackData has no heavy flag: an attack this strong reads as heavy.
const HEAVY_DAMAGE := 14.0
const HEAVY_ID_PARTS: Array[String] = ["heavy", "launcher", "spin"]
## Under flash reduction the crit row (the white-cored starburst) swaps for
## the flash-safe heavy row.
const FLASH_SAFE_ROWS := {&"spark_crit": &"spark_heavy"}
## "Keep the sheet's default tint" for play().
const NO_TINT := Color(0, 0, 0, 0)


## The spark row for a landed hit: guard for a block, crit for the finishing
## (killing) hit, heavy for a heavy attack, else small.
static func row_for(attack: AttackData, result: int) -> StringName:
	if result == CombatResult.BLOCKED:
		return &"spark_guard"
	if result == CombatResult.KILLED:
		return &"spark_crit"
	return &"spark_heavy" if is_heavy(attack) else &"spark_small"


static func is_heavy(attack: AttackData) -> bool:
	if attack == null:
		return false
	var id := String(attack.id)
	for part in HEAVY_ID_PARTS:
		if id.contains(part):
			return true
	return attack.damage >= HEAVY_DAMAGE


## The row actually drawn: flash-safe under flash reduction.
static func safe_row(row: StringName, reduced: bool) -> StringName:
	return FLASH_SAFE_ROWS.get(row, row) if reduced else row


## A sprite spark on the impact frame (direction snapped to quarter turns by
## VfxOneShot, tint value scaled under flash reduction), or the placeholder
## particles (`fallback_color`, `amount_`, `speed`) when the sheet is missing.
static func play(parent: Node, at: Vector2, direction_: Vector2, row: StringName, tint: Color = NO_TINT,
		amount_: int = 8, speed: float = 140.0, fallback_color: Color = Color.WHITE) -> Node2D:
	var opts := {"direction": direction_}
	if tint.a > 0.0:
		opts["tint"] = tint
	var fx := VfxOneShot.spawn(parent, SHEET, safe_row(row, Settings.flash_reduction), at, opts)
	if fx:
		return fx
	return spawn(parent, at, direction_, tint if tint.a > 0.0 else fallback_color, amount_, speed)
