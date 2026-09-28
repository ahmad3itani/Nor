class_name DustBurst
extends CPUParticles2D
## One-shot pixel dust (bible §26 VFX vocabulary: "dust"). Untextured
## particles render as 1px squares, which suits the 480x270 canvas.
## Spawned in world space so it stays put when the player moves on.

const DUST_COLOR := Color(0.78, 0.75, 0.84, 0.9)


static func spawn(parent: Node, at: Vector2, amount_: int, direction_: Vector2,
		spread_deg: float, speed: float, lifetime_: float = 0.35) -> DustBurst:
	var d := DustBurst.new()
	d.position = at
	d.amount = maxi(amount_, 1)
	d.lifetime = lifetime_
	d.one_shot = true
	d.explosiveness = 0.95
	d.direction = direction_.normalized() if direction_ != Vector2.ZERO else Vector2.UP
	d.spread = spread_deg
	d.initial_velocity_min = speed * 0.4
	d.initial_velocity_max = speed
	d.gravity = Vector2(0, 180)
	d.damping_min = 60.0
	d.damping_max = 120.0
	d.scale_amount_min = 1.0
	d.scale_amount_max = 2.0
	var ramp := Gradient.new()
	ramp.set_color(0, DUST_COLOR)
	ramp.set_color(1, Color(DUST_COLOR, 0.0))
	d.color_ramp = ramp
	d.finished.connect(d.queue_free)
	parent.add_child(d)
	d.emitting = true
	return d


# --- Sprite dust (presentation overhaul T06) ---------------------------------
# vfx/dust rows (floor at the origin, drifting toward -x) and, on water, the
# vfx/splash rows. spawn() above stays the placeholder: callers use it when
# puff() returns null (missing sheet or the id's live cap is full).

## dust row -> splash row on water surfaces (&"" = nothing on water).
const WATER_ROWS := {
	&"land": &"land", &"land_hard": &"land", &"run_puff": &"step", &"slide": &"step",
	&"dash_trail": &"step", &"wall_scrape": &"",
}
## Debris chunks fall with this gravity (px/s^2) for DEBRIS_LIFETIME seconds.
const DEBRIS_GRAVITY := 520.0
const DEBRIS_LIFETIME := 0.6


## A dust (or, on water, splash) sprite at `at` (a floor point), flipped by
## `facing`. Null when the sheet is unavailable.
static func puff(parent: Node, row: StringName, at: Vector2, facing: int = 1, water: bool = false) -> VfxOneShot:
	if water:
		var wet: StringName = WATER_ROWS.get(row, &"")
		if wet == &"":
			return null
		return VfxOneShot.spawn(parent, &"splash", wet, at, {"facing": facing})
	return VfxOneShot.spawn(parent, &"dust", row, at, {"facing": facing})


## Tumbling debris sprites (vfx/debris `concrete`/`glass`) thrown from `rect`
## and falling under gravity; visual only (no collision). Returns how many
## spawned (0 = the caller keeps its placeholder). `rng` is the caller's own,
## so gameplay randomness is never consumed.
static func debris(parent: Node, rect: Rect2, row: StringName, count: int, rng: RandomNumberGenerator) -> int:
	var n := 0
	for i in count:
		var at := rect.position + Vector2(rng.randf() * rect.size.x, rng.randf() * rect.size.y)
		var fx := VfxOneShot.spawn(parent, &"debris", row, at,
			{"facing": 1 if rng.randf() < 0.5 else -1, "lifetime": DEBRIS_LIFETIME, "speed_scale": rng.randf_range(0.7, 1.3)})
		if fx == null:
			break
		n += 1
		var v := Vector2(rng.randf_range(-70.0, 70.0), rng.randf_range(-150.0, -60.0))
		var p0 := at
		var tw := fx.create_tween()
		tw.tween_method(func(t: float) -> void:
			fx.position = (p0 + v * t + Vector2(0.0, 0.5 * DEBRIS_GRAVITY * t * t)).round(),
			0.0, DEBRIS_LIFETIME, DEBRIS_LIFETIME)
	return n
