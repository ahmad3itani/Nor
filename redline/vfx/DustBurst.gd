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
