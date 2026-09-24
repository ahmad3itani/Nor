extends Node2D
## Graybox stand-in for Rook's sprite (placeholder art is expected in M0-M2).
## It still sells feel: squash/stretch on jump and land, state tinting,
## a facing "visor", and afterimages during dodge/dash (bible §25 vocabulary).

const STATE_COLORS := {
	&"idle": Color("d8d4e0"),
	&"run": Color("f2eff7"),
	&"crouch": Color("a9a3b8"),
	&"slide": Color("ff9a3c"),
	&"air": Color("c9d6ff"),
	&"dodge": Color("58e0e8"),
	&"dash": Color("e8283c"),
	&"melee": Color("ffd9de"),
	&"hurt": Color("ff5a6a"),
}
const VISOR_COLOR := Color("e8283c")
const IFRAME_COLOR := Color("ffffff")
const GHOST_LIFETIME := 0.18
const GHOST_INTERVAL := 0.03

@export var squash_recovery_rate: float = 14.0

var _scale := Vector2.ONE
var _ghosts: Array = []
var _ghost_timer: float = 0.0

@onready var player: Player = get_parent()


func _ready() -> void:
	player.jumped.connect(func(_kind: StringName) -> void: _scale = Vector2(0.72, 1.3))
	player.landed.connect(_on_landed)


func _on_landed(impact_speed: float) -> void:
	var t := clampf(impact_speed / player.config.hard_land_speed, 0.3, 1.2)
	_scale = Vector2(1.0 + 0.35 * t, 1.0 - 0.3 * t)


func _process(delta: float) -> void:
	_scale = _scale.lerp(Vector2.ONE, 1.0 - exp(-squash_recovery_rate * delta))
	var state := player.current_state_id()
	if state == &"dodge" or state == &"dash" or (state == &"slide" and absf(player.velocity.x) > player.config.max_run_speed):
		_ghost_timer -= delta
		if _ghost_timer <= 0.0:
			_ghost_timer = GHOST_INTERVAL
			_ghosts.append({"pos": player.global_position, "size": _body_size(), "age": 0.0, "color": _body_color()})
	for g in _ghosts:
		g["age"] += delta
	_ghosts = _ghosts.filter(func(g: Dictionary) -> bool: return g["age"] < GHOST_LIFETIME)
	queue_redraw()


func _body_size() -> Vector2:
	return player.config.low_size if player.is_low else player.config.standing_size


func _body_color() -> Color:
	if player.invulnerable:
		return IFRAME_COLOR
	return STATE_COLORS.get(player.current_state_id(), Color.WHITE)


func _draw() -> void:
	for g in _ghosts:
		var local: Vector2 = g["pos"] - player.global_position
		var c: Color = g["color"]
		c.a = 0.35 * (1.0 - g["age"] / GHOST_LIFETIME)
		var s: Vector2 = g["size"]
		draw_rect(Rect2(local + Vector2(-s.x * 0.5, -s.y), s), c)

	# Body anchored at the feet so squash keeps contact with the floor.
	var size := _body_size() * _scale
	var body := Rect2(Vector2(-size.x * 0.5, -size.y), size).abs()
	var body_color := _body_color()
	# Blink while post-hit invulnerable so the grace period is readable.
	if player.combat.hurt_invuln_timer > 0.0 and int(player.combat.hurt_invuln_timer * 20.0) % 2 == 0:
		body_color.a = 0.35
	if player.combat.dead:
		body_color = body_color.darkened(0.5)
	draw_rect(body, body_color)
	draw_rect(body, Color(0, 0, 0, 0.6), false, 1.0)
	# Visor: a 4x2 slit near the head on the facing side reads direction at a glance.
	var visor_y := body.position.y + minf(5.0, size.y * 0.25)
	var visor_x := 1.0 if player.facing > 0 else -5.0
	draw_rect(Rect2(Vector2(visor_x, visor_y), Vector2(4, 2)), VISOR_COLOR)
