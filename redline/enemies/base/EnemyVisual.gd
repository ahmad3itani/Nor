extends Node2D
## Placeholder enemy rendering with readable telegraphs (bible §17, §26):
## hit flash, stagger tint, wind-up warning (hitbox outline for melee, aim
## line for projectiles), health bar once damaged, hitstop shake.

const TELEGRAPH_COLOR := Color("ff3b4f")
const FLASH_COLOR := Color.WHITE

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
		tint = Color(3, 3, 3)
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
			var pulse := 0.5 + 0.5 * sin(enemy.ai_time * 40.0)
			color = color.lerp(TELEGRAPH_COLOR, 0.35 + 0.35 * pulse)
	if enemy.flash_timer > 0.0:
		color = FLASH_COLOR
	if actor == null:
		draw_rect(body, color)
		draw_rect(body, Color("ffcf5a") if data.elite else Color(0, 0, 0, 0.6), false, 1.0)
		var eye_x := 1.0 if enemy.facing > 0 else -4.0
		draw_rect(Rect2(Vector2(eye_x, -size.y + 4.0) + shake, Vector2(3, 2)), Color("1a1320"))
		enemy.behavior.draw_extras(self)

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
	var c := TELEGRAPH_COLOR
	c.a = 0.25 + 0.6 * progress
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
		draw_line(from, from + aim * 220.0 * progress, c, 1.0)
	else:
		var r := attack.world_hitbox(enemy.global_position, enemy.facing)
		r.position -= enemy.global_position
		draw_rect(r, c, false, 1.0)
