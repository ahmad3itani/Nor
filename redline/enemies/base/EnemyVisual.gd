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
##
## Presentation overhaul (T05), sprite mode (EnemyData.sprite set and found):
## - animation: the behavior's anim_names() first (boss families), then the
##   generic map; wind-up poses are non-looping and hold their last frame for
##   the whole telegraph;
## - hit reactions: a `hurt` one-shot on every damaging hit that does not
##   already stagger, the hit flash tint, a 1-2 px knock of the sprite along
##   the hit direction for 0.08 s; `guard_break` when the guard module
##   reports a break; the stagger tint stays;
## - accessibility: the wind-up tint on the sprite (held still under flash
##   reduction) and, under high contrast, a 1 px flat outline silhouette made
##   of 4 offset copies of the current frame behind the sprite;
## - death: spawn_death_visuals() leaves a detached, darkened corpse that
##   finishes the `death` animation after the body is freed, plus a
##   death_burst tinted by burst_tint(EnemyData.color).
## Telegraphs, the "!", health bars, elite notches and the behaviors' code
## cues (guard rim, eye pupil, boss lamps and floor tells) draw on top. With
## no sprite (or a missing sheet) the placeholder body draws as before.

const TELEGRAPH_COLOR := Color("ff3b4f")
const FLASH_COLOR := Color.WHITE
const ELITE_COLOR := Color("ffcf5a")
## Wind-up pulse in rad/s (about 6.4 Hz): only without flash reduction.
const WINDUP_PULSE_RATE := 40.0
## Hit knock: sprite offset along the hit direction (visual only).
const KNOCK_TIME := 0.08
## Death corpse: held on the last death frame, then faded; darkened like the
## placeholder DEAD body (darkened(0.6)).
const CORPSE_HOLD := 0.6
const CORPSE_FADE := 0.3
const CORPSE_DIM := 0.6
## Death-burst tint: the enemy colour lifted toward this pale neutral until
## its brightest tone (the sheet's 255) reads at L* >= BURST_MIN_LSTAR.
const BURST_PALE := Color("d8d4e0")
const BURST_MIN_LSTAR := 60.0
const OUTLINE_SHADER := "shader_type canvas_item;\nuniform vec4 flat_color : source_color = vec4(1.0);\nvoid fragment() {\n\tCOLOR = vec4(flat_color.rgb, flat_color.a * texture(TEXTURE, UV).a);\n}\n"
const OUTLINE_OFFSETS: Array[Vector2] = [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]

static var _outline_shader: Shader

@onready var enemy: Enemy = get_parent()
var actor: SpriteActor
## High-contrast outline copies (created on first use, sprite mode only).
var outline_nodes: Array[Sprite2D] = []
## [ai, attack, anim] the last pose was asked in (see pose_restarts).
var _anim_key: Array = []
var _knock := Vector2.ZERO
var _knock_t: float = 0.0
## Presentation-only randomness (hitstop shake in sprite mode): never the
## global RNG.
var _rng := RandomNumberGenerator.new()
var _guard: GuardModule


func _ready() -> void:
	_rng.seed = 5
	if enemy.data and enemy.data.sprite:
		actor = SpriteActor.create(enemy.data.sprite)
		if actor:
			actor.name = "Sprite"
			# Telegraphs, bars and code cues (this node's _draw) stay on top.
			actor.show_behind_parent = true
			actor.modulate = enemy.data.sprite_modulate
			add_child(actor)
			EventBus.enemy_damaged.connect(_on_enemy_damaged)
			# The guard is bound on the first update: children are ready before
			# the Enemy sets up its behavior, whose brain() (brain_override
			# first) is the one that guards.


func _exit_tree() -> void:
	# Guard modules are shared resources: never leave a callable behind.
	_bind_guard(null)


## Follows the guard module the behavior actually uses (a brain_override
## may bring its own, or none).
func _bind_guard(guard: GuardModule) -> void:
	if guard == _guard:
		return
	if _guard and _guard.guard_broken.is_connected(_on_guard_broken):
		_guard.guard_broken.disconnect(_on_guard_broken)
	_guard = guard
	if _guard and not _guard.guard_broken.is_connected(_on_guard_broken):
		_guard.guard_broken.connect(_on_guard_broken)


func _behavior_guard() -> GuardModule:
	var brain: EnemyBrain = null
	if is_instance_valid(enemy.behavior) and enemy.behavior is ModularBehavior and (enemy.behavior as ModularBehavior).enemy:
		brain = (enemy.behavior as ModularBehavior).brain()
	elif enemy.data:
		brain = enemy.data.brain
	return brain.guard if brain else null


func uses_sprite() -> bool:
	return actor != null


func _process(delta: float) -> void:
	if actor:
		_update_actor(delta)
	queue_redraw()


## AI state -> animation, with fallbacks so partial art sets still play.
func _update_actor(delta: float) -> void:
	_bind_guard(_behavior_guard())
	actor.face(enemy.facing)
	var one_shot := actor.is_playing_one_shot()
	if one_shot and (enemy.ai == Enemy.AI.WINDUP or enemy.ai == Enemy.AI.ACTIVE or enemy.ai == Enemy.AI.DEAD):
		one_shot = false  # a telegraph or a death always shows at once
	if not one_shot:
		_play(anim_names_now())
	# Tint: hit flash > stagger > wind-up warning (T05 repair a).
	var tint := Color.WHITE
	if enemy.flash_timer > 0.0:
		tint = hit_tint(Settings.flash_reduction)
	elif enemy.ai == Enemy.AI.STAGGER or enemy.ai == Enemy.AI.LAUNCHED:
		tint = Color(0.65, 0.65, 0.65)
	elif enemy.ai == Enemy.AI.WINDUP:
		tint = windup_tint(enemy.ai_time, Settings.flash_reduction)
	actor.self_modulate = tint
	if actor.mask and enemy.data.has_meta(&"mask_tint"):
		# A variant's own visor colour (Krail Null: white) over the palette key.
		actor.mask.modulate = enemy.data.get_meta(&"mask_tint")
	# Knock and hitstop shake (visual only).
	_knock_t = maxf(_knock_t - delta, 0.0)
	var pos := _knock if _knock_t > 0.0 else Vector2.ZERO
	pos += _sprite_offset()
	if enemy.hitstop_timer > 0.0:
		pos.x += roundf(_rng.randf_range(-1.0, 1.0))
	actor.position = pos
	_update_outline()


## The names to try now: the behavior's (bosses, per attack family), then
## the generic map.
func anim_names_now() -> Array[StringName]:
	var out: Array[StringName] = []
	if is_instance_valid(enemy.behavior):
		out.append_array(enemy.behavior.anim_names(enemy.ai, enemy.current_attack))
	out.append_array(generic_anim_names(enemy.ai, enemy.current_attack, enemy.ai_enabled, _moving()))
	return out


func _moving() -> bool:
	return absf(enemy.velocity.x) > 5.0 or (enemy.data.flying and enemy.velocity.length() > 5.0)


## The shared map. Attack ids containing "lunge" ask for the lunge pair
## first, the rest for the baton pair (Enforcer); sheets without them fall
## back to the plain windup/attack rows. A dormant practice dummy (AI off,
## needle_dormant) plays dormant.
static func generic_anim_names(ai: int, attack: AttackData, ai_enabled: bool, moving: bool) -> Array[StringName]:
	var lunge := attack != null and String(attack.id).contains("lunge")
	match ai:
		Enemy.AI.WINDUP:
			return [&"windup_lunge" if lunge else &"windup_baton", &"windup", &"attack", &"idle"]
		Enemy.AI.ACTIVE:
			return [&"attack_lunge" if lunge else &"attack_baton", &"attack", &"idle"]
		Enemy.AI.STAGGER, Enemy.AI.LAUNCHED:
			return [&"hurt", &"idle"]
		Enemy.AI.DEAD:
			return [&"death", &"hurt", &"idle"]
		Enemy.AI.IDLE:
			if not ai_enabled:
				return [&"dormant", &"idle"]
	if moving:
		return [&"move", &"idle"]
	return [&"idle"]


## Plays the first existing name. A non-looping pose holds its last frame
## (AnimatedSprite2D.play would restart a finished one); it restarts when the
## name or the attack changes, or on a new AI state other than RECOVER: the
## boss maps give ACTIVE and RECOVER the same strike row, and RECOVER holds
## that strike's last frame instead of replaying it.
func _play(names: Array[StringName]) -> void:
	var n := &""
	for item in names:
		if actor.sprite_frames.has_animation(item):
			n = item
			break
	if n == &"":
		return
	var key := [enemy.ai, enemy.current_attack, n]
	var loops := actor.sprite_frames.get_animation_loop(n)
	if actor.animation != n or (not loops and pose_restarts(_anim_key, key)):
		actor.stop()
		actor.play(n)
		actor.frame = 0
		actor.frame_progress = 0.0
	elif loops and not actor.is_playing():
		actor.play(n)
	_anim_key = key


## Whether a non-looping pose with the same name restarts on the move from
## `prev` to `key` (both [ai, attack, anim]; `prev` empty after a one-shot).
static func pose_restarts(prev: Array, key: Array) -> bool:
	if prev.size() != 3:
		return true
	if prev[1] != key[1] or prev[2] != key[2]:
		return true
	return prev[0] != key[0] and key[0] != Enemy.AI.RECOVER


# --- Hit reactions -----------------------------------------------------------------

func _on_enemy_damaged(who: Node2D, hit: HitInfo, result: int) -> void:
	if who != enemy or actor == null or result != CombatResult.HIT:
		return
	var d := Vector2(-enemy.facing, 0)
	if hit and hit.direction != Vector2.ZERO:
		d = hit.direction
	var px := 2.0 if hit and hit.attack and hit.attack.hitstop >= 0.08 else 1.0
	_knock = (d.normalized() * px).round()
	_knock_t = KNOCK_TIME
	# A stagger plays its own row through the map; a telegraph never hides.
	if enemy.ai in [Enemy.AI.STAGGER, Enemy.AI.LAUNCHED, Enemy.AI.WINDUP, Enemy.AI.ACTIVE]:
		return
	actor.play_once_first([&"hurt"])
	_anim_key = []


func _on_guard_broken(who: Enemy) -> void:
	if who != enemy or actor == null:
		return
	actor.play_once_first([&"guard_break", &"hurt"])
	_anim_key = []


# --- Accessibility in sprite mode (T05 repair a) ----------------------------------

## Sprite tint during a wind-up: toward Palette danger by 0.35..0.7 (held at
## 0.525 under flash reduction), the blend the placeholder body uses.
static func windup_tint(t: float, reduced: bool) -> Color:
	return Color.WHITE.lerp(Palette.color(&"danger"), 0.35 + 0.35 * windup_pulse(t, reduced))


func _update_outline() -> void:
	if not UiTheme.high_contrast():
		for s in outline_nodes:
			s.visible = false
		return
	if outline_nodes.is_empty():
		if _outline_shader == null:
			_outline_shader = Shader.new()
			_outline_shader.code = OUTLINE_SHADER
		var mat := ShaderMaterial.new()
		mat.shader = _outline_shader
		for off in OUTLINE_OFFSETS:
			var s := Sprite2D.new()
			s.name = "HcOutline"
			s.show_behind_parent = true
			s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			s.centered = true
			s.material = mat
			s.set_meta(&"offset", off)
			add_child(s)
			move_child(s, 0)  # behind the actor
			outline_nodes.append(s)
	var tex := actor.sprite_frames.get_frame_texture(actor.animation, actor.frame)
	(outline_nodes[0].material as ShaderMaterial).set_shader_parameter(&"flat_color", body_outline_color(enemy.data.elite, true))
	for s in outline_nodes:
		s.visible = actor.visible
		s.texture = tex
		s.offset = actor.offset
		s.flip_h = actor.flip_h
		s.position = actor.position + (s.get_meta(&"offset") as Vector2)


# --- Death (T05) -----------------------------------------------------------------------

## Called by Enemy._pop as the body is freed. Spawns the detached corpse
## (sprite mode) and the death burst into `parent`. Returns false when no
## burst could spawn, so Enemy keeps its HitSpark fallback.
func spawn_death_visuals(parent: Node) -> bool:
	if parent == null or not is_instance_valid(parent):
		return false
	spawn_corpse(parent)
	var data := enemy.data
	var id := &"death_burst_boss" if data.boss else &"death_burst"
	var anim := burst_anim(data)
	var at := _local_in(parent, enemy.global_position + Vector2(0, -data.body_size.y * 0.5))
	return VfxOneShot.spawn(parent, id, anim, at, {"facing": enemy.facing, "tint": burst_tint(data.color)}) != null


## death_burst row: small for regular enemies, large for elites, the boss
## sheet's single row for bosses.
static func burst_anim(data: EnemyData) -> StringName:
	if data.boss:
		return &"boss"
	return &"large" if data.elite else &"small"


## The corpse: the enemy's frames on `death`, continuing from the body's
## current death frame, held CORPSE_HOLD s, faded CORPSE_FADE s, darkened.
## No collision; frees itself. Null without a sprite or a death row.
func spawn_corpse(parent: Node) -> VfxOneShot:
	if actor == null or not actor.sprite_frames.has_animation(&"death"):
		return null
	var m := enemy.data.sprite_modulate
	var fx := VfxOneShot.spawn_frames(parent, actor.sprite_frames, &"death", _local_in(parent, enemy.global_position + _sprite_offset()), {
		"facing": enemy.facing, "offset": actor.spec.offset_for(&"death"), "hold_last": true,
		"tint": Color(m.r * CORPSE_DIM, m.g * CORPSE_DIM, m.b * CORPSE_DIM, m.a), "z_index": enemy.z_index})
	if fx == null:
		return null
	fx.name = "EnemyCorpse"
	var count := actor.sprite_frames.get_frame_count(&"death")
	fx.sprite.frame = clampi(actor.frame if actor.animation == &"death" else 0, 0, count - 1)
	var fps := maxf(actor.sprite_frames.get_animation_speed(&"death"), 1.0)
	var remaining := float(count - fx.sprite.frame) / fps
	fx.lifetime = remaining + CORPSE_HOLD + CORPSE_FADE + 0.05
	_corpse_mask(fx)
	var tw := fx.create_tween()
	tw.tween_interval(remaining + CORPSE_HOLD)
	tw.tween_property(fx, "modulate:a", 0.0, CORPSE_FADE)
	return fx


## The tint-mask overlay (a visor's palette colour, Krail Null's white) rides
## on the corpse: a child of its sprite, so the corpse's dim and fade apply,
## following its frame. The high-contrast outline is not copied: the corpse
## is a dimmed, non-interactive remnant that is gone within about a second.
func _corpse_mask(fx: VfxOneShot) -> void:
	if actor.mask == null or not actor.mask.sprite_frames.has_animation(&"death"):
		return
	var m := AnimatedSprite2D.new()
	m.name = "Mask"
	m.sprite_frames = actor.mask.sprite_frames
	m.animation = &"death"
	m.centered = fx.sprite.centered
	m.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	m.flip_h = fx.sprite.flip_h
	m.offset = fx.sprite.offset
	m.modulate = actor.mask.modulate
	m.frame = fx.sprite.frame
	fx.sprite.add_child(m)
	var src := fx.sprite
	fx.sprite.frame_changed.connect(func() -> void: m.frame = src.frame)


func _sprite_offset() -> Vector2:
	return enemy.behavior.sprite_offset() if is_instance_valid(enemy.behavior) else Vector2.ZERO


static func _local_in(parent: Node, global: Vector2) -> Vector2:
	return (parent as Node2D).to_local(global) if parent is Node2D else global


## EnemyData.color lifted toward BURST_PALE (half-way at least) until its
## brightest tone reaches BURST_MIN_LSTAR, so a dark maroon or slate enemy
## still bursts in a readable tone.
static func burst_tint(c: Color) -> Color:
	var t := 0.5
	var out := c.lerp(BURST_PALE, t)
	while lstar(out) < BURST_MIN_LSTAR and t < 1.0:
		t = minf(t + 0.05, 1.0)
		out = c.lerp(BURST_PALE, t)
	return Color(out, 1.0)


## CIE L* (0..100) of an sRGB colour.
static func lstar(c: Color) -> float:
	var y := 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)
	return 116.0 * pow(y, 1.0 / 3.0) - 16.0 if y > 0.008856 else 903.3 * y


static func _lin(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


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
	# Sprite mode too: the behaviors' code cues (guard rim, pupil, boss lamps,
	# floor tells); their placeholder body parts skip themselves (uses_sprite).
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
