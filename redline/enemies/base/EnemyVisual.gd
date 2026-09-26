extends Node2D
## Placeholder enemy rendering with readable telegraphs (bible §17, §26):
## hit flash, stagger tint, wind-up warning (hitbox outline for melee, aim
## line for projectiles), health bar once damaged, hitstop shake.
##
## M9 (T12, D4 §7): the telegraph red is Palette &"danger" (this constant is
## its default-palette value). Flash reduction (the 3 Hz rule: with it on,
## nothing here blinks faster than AccessibilityConfig.flash_max_hz and no
## full-white frame covers more than the sprite): the hit flash is a softer
## tint and the wind-up pulse holds still. High contrast: a 1 px white body
## outline and 2 px telegraph lines. Elites always carry corner notches, so
## "elite" is a shape, not only the gold outline.

const TELEGRAPH_COLOR := Color("ff3b4f")
const FLASH_COLOR := Color.WHITE
const ELITE_COLOR := Color("ffcf5a")
## Wind-up pulse in rad/s (about 6.4 Hz): only without flash reduction.
const WINDUP_PULSE_RATE := 40.0

@onready var enemy: Enemy = get_parent()
var actor: SpriteActor


func _ready() -> void:
	if enemy.data and enemy.data.sprite:
		actor = SpriteActor.create(enemy.data.sprite)
		if actor:
			add_child(actor)


func uses_sprite() -> bool:
	return actor != null


func _process(_delta: float) -> void:
	if actor:
		_update_actor()
	queue_redraw()


## AI state -> animation, with fallbacks so partial art sets still play.
func _update_actor() -> void:
	actor.face(enemy.facing)
	var moving := absf(enemy.velocity.x) > 5.0 or (enemy.data.flying and enemy.velocity.length() > 5.0)
	match enemy.ai:
		Enemy.AI.WINDUP:
			actor.play_first([&"windup", &"attack", &"idle"])
		Enemy.AI.ACTIVE:
			actor.play_first([&"attack", &"idle"])
		Enemy.AI.STAGGER, Enemy.AI.LAUNCHED:
			actor.play_first([&"hurt", &"idle"])
		Enemy.AI.DEAD:
			actor.play_first([&"death", &"hurt", &"idle"])
		_:
			actor.play_first([&"move", &"idle"] if moving else [&"idle"])
	var tint := Color.WHITE
	if enemy.flash_timer > 0.0:
		tint = hit_tint(Settings.flash_reduction)
	elif enemy.ai == Enemy.AI.STAGGER or enemy.ai == Enemy.AI.LAUNCHED:
		tint = Color(0.65, 0.65, 0.65)
	actor.self_modulate = tint


func _draw() -> void:
	var data := enemy.data
	var size := data.body_size
	var shake := Vector2.ZERO
	if enemy.hitstop_timer > 0.0:
		shake = Vector2(randf_range(-1, 1), 0).round()
	var body := Rect2(Vector2(-size.x * 0.5, -size.y) + shake, size)

	var color := data.color
	match enemy.ai:
		Enemy.AI.STAGGER, Enemy.AI.LAUNCHED:
			color = color.darkened(0.35)
		Enemy.AI.DEAD:
			color = color.darkened(0.6)
		Enemy.AI.WINDUP:
			var pulse := windup_pulse(enemy.ai_time, Settings.flash_reduction)
			color = color.lerp(Palette.color(&"danger"), 0.35 + 0.35 * pulse)
	if enemy.flash_timer > 0.0:
		color = flash_color(Settings.flash_reduction)
	var hc := UiTheme.high_contrast()
	if actor == null:
		draw_rect(body, color)
		draw_rect(body, body_outline_color(data.elite, hc), false, 1.0)
		var eye_x := 1.0 if enemy.facing > 0 else -4.0
		draw_rect(Rect2(Vector2(eye_x, -size.y + 4.0) + shake, Vector2(3, 2)), Color("1a1320"))
		enemy.behavior.draw_extras(self)
	if data.elite:
		_draw_elite_notches(body)

	if enemy.ai == Enemy.AI.WINDUP and enemy.current_attack:
		_draw_telegraph()
	if enemy.health < data.max_health and not enemy.is_dead():
		var frac := clampf(enemy.health / data.max_health, 0.0, 1.0)
		var bar := Rect2(-size.x * 0.5, -size.y - 6.0, size.x, 2.0)
		draw_rect(bar, Color(0, 0, 0, 0.7))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, 2.0)), Color("e8283c"))


func _draw_telegraph() -> void:
	var attack := enemy.current_attack
	var progress := clampf(enemy.ai_time / maxf(attack.startup, 0.01), 0.0, 1.0)
	var c := Palette.color(&"danger")
	c.a = 0.25 + 0.6 * progress
	var width := telegraph_width(UiTheme.high_contrast())
	# "!" pip above the head at wind-up start.
	var head := Vector2(0, -enemy.data.body_size.y - 12.0)
	draw_rect(Rect2(head + Vector2(-1, 0), Vector2(2, 5)), c)
	draw_rect(Rect2(head + Vector2(-1, 6), Vector2(2, 2)), c)
	if attack.projectile:
		# Ground waves ignore aim (their tell is the behavior's floor glow);
		# lock_aim shots draw the line they will actually fire along.
		if attack.projectile.ground_wave:
			return
		var from := Vector2(0, -enemy.data.body_size.y * 0.5)
		var aim := enemy.attack_aim if attack.lock_aim else enemy._aim_at_target()
		draw_line(from, from + aim * 220.0 * progress, c, width)
	else:
		var r := attack.world_hitbox(enemy.global_position, enemy.facing)
		r.position -= enemy.global_position
		draw_rect(r, c, false, width)


## Elite corner notches (always on, D4 §7.3): a 3 px L outside each corner.
func _draw_elite_notches(body: Rect2) -> void:
	var r := body.grow(2.0)
	for corner in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		var sx := 1.0 if corner.x < body.get_center().x else -1.0
		var sy := 1.0 if corner.y < body.get_center().y else -1.0
		draw_line(corner, corner + Vector2(3.0 * sx, 0), ELITE_COLOR, 1.0)
		draw_line(corner, corner + Vector2(0, 3.0 * sy), ELITE_COLOR, 1.0)


# --- Pure helpers (test_flash_reduction, test_high_contrast) ---------------------

## Sprite tint on a hit: an overbright flash, or a soft one under flash reduction.
static func hit_tint(reduced: bool) -> Color:
	return Color(1.6, 1.6, 1.6) if reduced else Color(3, 3, 3)


## Placeholder body colour on a hit: white, or half-strength white under flash reduction.
static func flash_color(reduced: bool) -> Color:
	return Color(FLASH_COLOR, 0.5) if reduced else FLASH_COLOR


## Wind-up blend 0..1: pulsing at about 6.4 Hz, or held at 0.5 under flash reduction.
static func windup_pulse(t: float, reduced: bool) -> float:
	return 0.5 if reduced else 0.5 + 0.5 * sin(t * WINDUP_PULSE_RATE)


static func body_outline_color(elite: bool, hc: bool) -> Color:
	if elite:
		return ELITE_COLOR
	return Color.WHITE if hc else Color(0, 0, 0, 0.6)


static func telegraph_width(hc: bool) -> float:
	return 2.0 if hc else 1.0
