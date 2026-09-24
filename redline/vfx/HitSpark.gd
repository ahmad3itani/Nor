class_name HitSpark
extends CPUParticles2D
## Bright, fast impact sparks (bible §26 "impact sparks"). One-shot, world space.


static func spawn(parent: Node, at: Vector2, direction_: Vector2, color_: Color, amount_: int = 8,
		speed: float = 140.0) -> HitSpark:
	var s := HitSpark.new()
	s.position = at
	s.amount = maxi(amount_, 1)
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
	ramp.set_color(0, Color.WHITE)
	ramp.set_color(1, Color(color_, 0.0))
	s.color_ramp = ramp
	s.finished.connect(s.queue_free)
	parent.add_child(s)
	s.emitting = true
	return s
