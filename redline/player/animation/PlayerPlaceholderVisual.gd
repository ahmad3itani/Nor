extends Node2D
## Rook's visual. With `sprite` set and its sheet present, Rook is drawn from
## the sheet (SpriteActor); otherwise the graybox stand-in below is drawn, so
## missing art always degrades to the placeholder (D-026 swap-in rule).
## The placeholder still sells feel: squash/stretch on jump and land, state
## tinting, a facing "visor", and afterimages during dodge/dash (bible §25).
##
## M9 (T12, D4 §7.1/7.2): the post-hit blink (10 Hz) holds a steady see-through
## body under flash reduction (the 3 Hz rule), and high contrast outlines the
## body in white instead of black.
##
## Presentation overhaul (T04, ART_DIRECTION F9), sprite mode only:
## - a base animation per movement state (air picks jump_rise/jump_fall by
##   velocity, melee plays the attack id), with one-shot overlays on top:
##   per-weapon shots (PlayerCombat.fired, never EventBus.ranged_fired, which a
##   reload also emits), turn, land / land_hard, idle_fidget (after 6-10 s of
##   continuous idle, own RNG), interact and the rest loop at an anchor;
## - priorities: death > hurt > melee > dodge/dash > shot > land/turn/fidget/
##   interact/rest. An overlay never blocks or delays gameplay state: a state
##   of higher priority cancels it, and land/turn/fidget/interact/rest also
##   yield to any state change (fidget and rest to any input); a shot pose
##   stays over idle <-> run but ends on air, slide, crouch or heal;
## - non-looping base rows (crouch, slide, dodge, swings) play once and hold
##   their last frame while the state lasts;
## - code squash is scaled down while an authored squash frame plays, so the
##   two never multiply;
## - the Core seam mask brightens with the reactor (critical pulse, static
##   under flash reduction) and turns heal-green while healing; the hurt blink
##   reaches it through SpriteActor's alpha copy. The sheet has one mask for
##   visor and seam, so the visor follows the seam tint (a split mask is a
##   later art task);
## - afterimages are copies of the live frame, a high-contrast mode adds a
##   1 px white silhouette outline, and `step_contact` marks foot plants.
## Everything here is visual only; it never touches the player's state.

## A foot planted: 0 / 1 alternate on run contact frames, FOOT_LANDING on a
## landing. Footsteps (T08) and run puffs (T06) connect when present.
signal step_contact(foot: int)

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

## Ranged anims keyed by the shot AttackData id, with the weapon id as a
## second key (the sheet names them by gun, the data by shot).
const SHOT_ANIMS := {
	&"pistol_shot": &"shoot_pistol",
	&"scatter_pellet": &"shoot_scatter",
	&"revolver_shot": &"shoot_revolver",
	&"service_pistol": &"shoot_pistol",
	&"scattergun": &"shoot_scatter",
	&"heavy_revolver": &"shoot_revolver",
}
## Run frames (0-based, 8-frame cycle) where a foot plants: the two widest
## two-foot stances of the rig's run row, one per half cycle.
const RUN_CONTACT_FRAMES: Array[int] = [1, 5]
## Placeholder run cadence (the sheet's run fps), so step_contact still fires
## without art.
const PLACEHOLDER_RUN_FPS := 14.0
const FOOT_LANDING := 2
const FIDGET_MIN := 6.0
const FIDGET_MAX := 10.0
## Code squash kept while an authored squash frame plays (land, land_hard,
## jump_rise frame 0), so the drawn squash is not doubled.
const AUTHORED_SQUASH_KEEP := 0.35
const AFTERIMAGE_TINT := Color("a9a3b8")
const AFTERIMAGE_ALPHA := 0.4
const AFTERIMAGE_LIFETIME := 0.25
## Core seam overlay brightness: dim at rest, full and pulsing when critical.
const SEAM_VALUE := 0.8
const SEAM_CRITICAL_VALUE := 1.0
const SEAM_PULSE_DEPTH := 0.25
const SEAM_PULSE_HZ := 0.5
const OUTLINE_OFFSETS: Array[Vector2] = [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]
## Flat white in the frame's alpha. In a canvas_item fragment COLOR already
## holds modulate x texture colour, so the modulate is carried over from the
## vertex stage (its alpha keeps the hurt blink) and the texture gives only
## the silhouette.
const OUTLINE_SHADER := "shader_type canvas_item;\nvarying vec4 v_mod;\nvoid vertex() {\n\tv_mod = COLOR;\n}\nvoid fragment() {\n\tCOLOR = vec4(1.0, 1.0, 1.0, v_mod.a * texture(TEXTURE, UV).a);\n}\n"

## Overlay one-shots and their priority (a state of higher priority cancels).
const PRIO_LOW := 1
const PRIO_SHOT := 2
const STATE_PRIORITY := {&"dodge": 3, &"dash": 3, &"melee": 4, &"hurt": 5}
## Overlays that yield to any state change, and those that yield to any input.
const YIELD_ON_STATE := [&"turn", &"land", &"land_hard", &"idle_fidget", &"interact", &"rest"]
const YIELD_ON_INPUT := [&"idle_fidget", &"rest"]
## A shot pose is a standing pose: a change into one of these states ends it
## (the base row takes over), so it never slides through a jump or a slide.
## Idle <-> run keeps it (the shot reads over locomotion).
const SHOT_BREAKERS := [&"air", &"slide", &"crouch", &"heal"]
const AUTHORED_SQUASH := [&"land", &"land_hard"]

static var _outline_shader: Shader

@export var squash_recovery_rate: float = 14.0
## Final art: when set and its texture exists, Rook is drawn from the sheet
## (animation per movement state) and the placeholder body is skipped.
## Squash/stretch, afterimages and the hurt blink still apply.
@export var sprite: SpriteSheetSpec

var actor: SpriteActor

var _scale := Vector2.ONE
var _ghosts: Array = []
var _ghost_timer: float = 0.0
## Sprite-mode afterimages: {"node": Sprite2D, "age": float, "alpha": float}.
var _afterimages: Array = []
var _ghost_layer: Node2D
var _outline_layer: Node2D
var _outlines: Array[Sprite2D] = []

var _overlay: StringName = &""
var _overlay_prio: int = 0
## Queued after the current overlay ends (interact -> rest at an anchor).
var _after_overlay: StringName = &""
var _last_state: StringName = &""
var _last_facing: int = 1
var _idle_time: float = 0.0
var _fidget_at: float = 0.0
var _dead_played: bool = false
## The next base play restarts from frame 0 (state entered, attack started).
var _base_restart: bool = true
## jump_rise's first frame is an authored squash only on the first pass of
## the (looping) row: set when the row starts, cleared once frame 0 advances.
var _rise_first: bool = false
var _foot: int = 0
var _run_phase: float = 0.0
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()
## 0..1 set by T06's CoreAura while in Flow: lifts the seam toward full.
var _seam_boost: float = 0.0

@onready var player: Player = get_parent()


func _ready() -> void:
	_rng.seed = hash("rook_visual")
	_fidget_at = _next_fidget()
	if sprite:
		actor = SpriteActor.create(sprite)
		if actor:
			_ghost_layer = Node2D.new()
			_ghost_layer.name = "Afterimages"
			add_child(_ghost_layer)
			_outline_layer = Node2D.new()
			_outline_layer.name = "HcOutline"
			add_child(_outline_layer)
			add_child(actor)
			actor.one_shot_finished.connect(_on_one_shot_finished)
			actor.frame_changed.connect(_on_actor_frame_changed)
			actor.animation_changed.connect(_on_actor_animation_changed)
	_last_facing = player.facing
	player.jumped.connect(func(_kind: StringName) -> void: _scale = Vector2(0.72, 1.3))
	player.landed.connect(_on_landed)
	# The player's @onready fields are set after its children's _ready.
	var combat := player.get_node_or_null("Combat") as PlayerCombat
	if combat:
		combat.fired.connect(_on_fired)
		combat.attack_started.connect(func(_a: AttackData) -> void: _base_restart = true)
	EventBus.dialogue_requested.connect(_on_dialogue_requested)
	EventBus.anchor_rested.connect(_on_anchor_rested)
	EventBus.player_respawned.connect(_on_player_respawned)


func _on_landed(impact_speed: float) -> void:
	var t := clampf(impact_speed / player.config.hard_land_speed, 0.3, 1.2)
	_scale = Vector2(1.0 + 0.35 * t, 1.0 - 0.3 * t)
	step_contact.emit(FOOT_LANDING)
	if actor and not player.combat.dead:
		var hard := impact_speed >= player.config.hard_land_speed
		_start_overlay(&"land_hard" if hard else &"land", PRIO_LOW)


func _on_fired(w: WeaponData) -> void:
	if actor == null or w == null or player.combat.dead:
		return
	var anim: StringName = &""
	if w.shot and SHOT_ANIMS.has(w.shot.id):
		anim = SHOT_ANIMS[w.shot.id]
	elif SHOT_ANIMS.has(w.id):
		anim = SHOT_ANIMS[w.id]
	if anim != &"":
		_start_overlay(anim, PRIO_SHOT)


func _on_dialogue_requested(_dialogue: Resource, _npc_name: String) -> void:
	if actor and not player.combat.dead:
		_start_overlay(&"interact", PRIO_LOW)


func _on_anchor_rested(_anchor: Node) -> void:
	if actor == null or player.combat.dead:
		return
	if _start_overlay(&"interact", PRIO_LOW):
		_after_overlay = &"rest"
	else:
		_start_overlay(&"rest", PRIO_LOW)


func _on_player_respawned(p: Node2D, _spawn: StringName) -> void:
	if p != player:
		return
	_clear_overlay()
	_dead_played = false
	_idle_time = 0.0
	_fidget_at = _next_fidget()
	_last_facing = player.facing
	if actor:
		_base_restart = true
		_play_base(&"idle")


func _process(delta: float) -> void:
	advance(delta)


## One presentation tick (tests drive it with large steps to skip time).
func advance(delta: float) -> void:
	_time += delta
	_scale = _scale.lerp(Vector2.ONE, 1.0 - exp(-squash_recovery_rate * delta))
	var state := player.current_state_id()
	if state == &"dodge" or state == &"dash" or (state == &"slide" and absf(player.velocity.x) > player.config.max_run_speed):
		_ghost_timer -= delta
		if _ghost_timer <= 0.0:
			_ghost_timer = GHOST_INTERVAL
			spawn_afterimage(AFTERIMAGE_ALPHA if actor else 0.35)
	for g in _ghosts:
		g["age"] += delta
	_ghosts = _ghosts.filter(func(g: Dictionary) -> bool: return g["age"] < GHOST_LIFETIME)
	_age_afterimages(delta)
	if actor:
		_update_actor(delta)
	else:
		_placeholder_steps(delta, state)
	_last_state = state
	queue_redraw()


## Leaves a fading copy of Rook where he stands (dodge/dash trail, and T06's
## perfect-dodge flourish). Sprite mode copies the live frame; the
## placeholder leaves a body rectangle.
func spawn_afterimage(alpha: float = AFTERIMAGE_ALPHA) -> void:
	if actor == null:
		_ghosts.append({"pos": player.global_position, "size": _body_size(), "age": 0.0, "color": _body_color(), "alpha": alpha})
		return
	var tex := actor.sprite_frames.get_frame_texture(actor.animation, actor.frame) if actor.sprite_frames.has_animation(actor.animation) else null
	if tex == null:
		return
	var s := Sprite2D.new()
	s.top_level = true
	s.texture = tex
	s.centered = actor.centered
	s.offset = actor.offset
	s.flip_h = actor.flip_h
	s.flip_v = actor.flip_v
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.global_position = actor.global_position
	s.scale = actor.scale
	var c := AFTERIMAGE_TINT
	c.a = alpha
	s.modulate = c
	_ghost_layer.add_child(s)
	_afterimages.append({"node": s, "age": 0.0, "alpha": alpha})


## Live afterimage copies (sprite mode), oldest first.
func afterimages() -> Array[Sprite2D]:
	var out: Array[Sprite2D] = []
	for a in _afterimages:
		out.append(a["node"])
	return out


## The white silhouette copies drawn behind the sprite in high contrast.
func outline_nodes() -> Array[Sprite2D]:
	return _outlines


## The one-shot overlay playing over the base animation (&"" when none).
func overlay() -> StringName:
	return _overlay


func _age_afterimages(delta: float) -> void:
	var keep: Array = []
	for a in _afterimages:
		var s: Sprite2D = a["node"]
		if not is_instance_valid(s):
			continue
		a["age"] += delta
		if a["age"] >= AFTERIMAGE_LIFETIME:
			s.queue_free()
			continue
		s.modulate.a = a["alpha"] * (1.0 - a["age"] / AFTERIMAGE_LIFETIME)
		keep.append(a)
	_afterimages = keep


## Movement state -> animation (Art Bible §6 minimum set), with fallbacks,
## and the one-shot overlays on top.
func _update_actor(delta: float) -> void:
	var state := player.current_state_id()
	var input := player.last_input
	actor.face(player.facing)
	if player.combat.dead:
		if not _dead_played:
			_clear_overlay()
			_dead_played = true
			actor.play_once_first([&"death", &"hurt", &"idle"])
		# Hold the last frame (non-looping: the sprite stops there).
	else:
		_dead_played = false
		var changed := state != _last_state and _last_state != &""
		var prio: int = STATE_PRIORITY.get(state, 0)
		# landed fires while the state is still `air`; settling into idle/run on
		# the next tick is the landing itself, not a new state to yield to.
		var settle := _last_state == &"air" and (state == &"idle" or state == &"run") and _overlay in AUTHORED_SQUASH
		if _overlay != &"":
			var shot_break := _overlay_prio == PRIO_SHOT and changed and state in SHOT_BREAKERS
			if prio > _overlay_prio or shot_break or (changed and not settle and _overlay in YIELD_ON_STATE) or (_overlay in YIELD_ON_INPUT and _input_active(input)):
				_clear_overlay()
				_base_restart = true
		_tick_fidget(delta, state, input, changed)
		if player.facing != _last_facing and (state == &"run" or state == &"idle") and player.is_on_floor():
			_start_overlay(&"turn", PRIO_LOW)
		if changed:
			_base_restart = true
		if _overlay == &"":
			_play_base(state)
		elif not actor.is_playing_one_shot() and _overlay != &"rest":
			# The overlay's anim is missing or was replaced: fall back to the base.
			_clear_overlay()
			_base_restart = true
			_play_base(state)
	_last_facing = player.facing
	var k := AUTHORED_SQUASH_KEEP if _authored_squash_playing() else 1.0
	actor.scale = Vector2.ONE + (_scale - Vector2.ONE) * k
	var a := hurt_alpha(player.combat.hurt_invuln_timer, Settings.flash_reduction)
	actor.self_modulate = Color(1, 1, 1, a)
	_update_seam(state)
	_update_outline(a)


## Plays the state's base row. A looping row keeps cycling; a non-looping one
## (crouch, slide, dodge, a swing, hurt) plays once and holds its last frame
## for as long as the state lasts, restarting only when the state is entered
## again or a new attack starts (AnimatedSprite2D.play() on a finished row
## would rewind it every tick).
func _play_base(state: StringName) -> void:
	var restart := _base_restart
	_base_restart = false
	for item in _base_names(state):
		var n := StringName(item)
		if not actor.sprite_frames.has_animation(n):
			continue
		if actor.animation != n:
			actor.play(n)
		elif restart:
			actor.stop()
			actor.play(n)
		elif not actor.is_playing() and actor.sprite_frames.get_animation_loop(n):
			actor.play(n)
		return


func _base_names(state: StringName) -> Array:
	if state == &"air":
		return [&"jump_rise" if player.velocity.y < 0.0 else &"jump_fall", &"air", &"idle"]
	if state == &"melee" and player.combat.current_attack:
		return [player.combat.current_attack.id, &"attack", &"idle"]
	return [state, &"idle"]


## Starts a one-shot overlay unless a stronger state or overlay holds the
## sprite. Returns whether it plays.
func _start_overlay(anim: StringName, prio: int) -> bool:
	if actor == null or player.combat.dead:
		return false
	var state := player.current_state_id()
	if STATE_PRIORITY.get(state, 0) > prio:
		return false
	if _overlay != &"" and _overlay_prio > prio:
		return false
	if not actor.sprite_frames.has_animation(anim):
		return false
	_after_overlay = &""
	_overlay = anim
	_overlay_prio = prio
	if actor.sprite_frames.get_animation_loop(anim):
		actor.play_first([anim])
	else:
		actor.play_once_first([anim])
	if anim != &"idle_fidget":
		_idle_time = 0.0
	return true


func _clear_overlay() -> void:
	_overlay = &""
	_overlay_prio = 0
	_after_overlay = &""


func _on_one_shot_finished(anim: StringName) -> void:
	if anim != _overlay:
		return
	var next := _after_overlay
	_clear_overlay()
	if anim == &"idle_fidget":
		_idle_time = 0.0
		_fidget_at = _next_fidget()
	if next != &"":
		_start_overlay(next, PRIO_LOW)
	elif actor:
		_base_restart = true
		_play_base(player.current_state_id())


func _tick_fidget(delta: float, state: StringName, input: PlayerInputFrame, changed: bool) -> void:
	if state != &"idle" or changed or _input_active(input) or (_overlay != &"" and _overlay != &"idle_fidget"):
		_idle_time = 0.0
		return
	if _overlay == &"idle_fidget":
		return
	_idle_time += delta
	if _idle_time >= _fidget_at:
		_idle_time = 0.0
		_fidget_at = _next_fidget()
		_start_overlay(&"idle_fidget", PRIO_LOW)


func _next_fidget() -> float:
	return _rng.randf_range(FIDGET_MIN, FIDGET_MAX)


func _authored_squash_playing() -> bool:
	if actor.animation in AUTHORED_SQUASH and actor.is_playing():
		return true
	return _rise_first and actor.animation == &"jump_rise" and actor.frame == 0


## Core seam: accent (or the colour-blind/high-contrast key) at 0.8, full with
## a slow pulse at critical (held full under flash reduction), heal-green
## while healing. The mask texture is white, so modulate is the colour.
func _update_seam(state: StringName) -> void:
	if actor.mask == null:
		return
	var base := Palette.color(&"heal") if state == &"heal" else actor.mask_color()
	var v := lerpf(SEAM_VALUE, SEAM_CRITICAL_VALUE, _seam_boost)
	if _reactor_critical():
		v = SEAM_CRITICAL_VALUE
		if not Settings.flash_reduction:
			v += SEAM_PULSE_DEPTH * (0.5 + 0.5 * sin(TAU * SEAM_PULSE_HZ * _time))
	actor.mask.modulate = Color(base.r * v, base.g * v, base.b * v, base.a)


## CoreAura hook (T06): brighten the seam overlay while in Flow (0 = rest).
func set_seam_boost(amount: float) -> void:
	_seam_boost = clampf(amount, 0.0, 1.0)


## True when the seam is a sprite mask this visual brightens itself, so
## CoreAura skips its drawn seam glow (placeholder mode has no mask).
func has_seam_overlay() -> bool:
	return actor != null and actor.mask != null


func _reactor_critical() -> bool:
	var r := player.reactor
	return r != null and is_instance_valid(r) and r.config != null and r.is_critical() and r.in_flow()


## High contrast in sprite mode: four white copies of the live frame, 1 px
## out on each side, behind the sprite.
func _update_outline(alpha: float) -> void:
	var hc := UiTheme.high_contrast()
	if hc and _outlines.is_empty():
		_build_outline()
	_outline_layer.visible = hc
	if not hc:
		return
	_sync_outline_frame()
	for s in _outlines:
		s.modulate = Color(1, 1, 1, alpha)


## Copies the actor's live frame into the outline copies. Also run from the
## actor's frame_changed / animation_changed: the parent's _process runs
## before the child AnimatedSprite2D advances, so copying only there left the
## outline a frame behind on 18-24 fps attack rows (a white ghost).
func _sync_outline_frame() -> void:
	if _outlines.is_empty() or actor == null or not _outline_layer.visible:
		return
	var tex := actor.sprite_frames.get_frame_texture(actor.animation, actor.frame) if actor.sprite_frames.has_animation(actor.animation) else null
	for i in _outlines.size():
		var s := _outlines[i]
		s.texture = tex
		s.offset = actor.offset
		s.flip_h = actor.flip_h
		s.flip_v = actor.flip_v
		s.scale = actor.scale
		s.position = actor.position + OUTLINE_OFFSETS[i]


## The texture each outline copy shows (tests).
func outline_texture() -> Texture2D:
	return _outlines[0].texture if not _outlines.is_empty() else null


func _build_outline() -> void:
	if _outline_shader == null:
		_outline_shader = Shader.new()
		_outline_shader.code = OUTLINE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _outline_shader
	for i in OUTLINE_OFFSETS.size():
		var s := Sprite2D.new()
		s.name = "Outline%d" % i
		s.centered = actor.centered
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.material = mat
		_outline_layer.add_child(s)
		_outlines.append(s)


func _on_actor_animation_changed() -> void:
	_rise_first = actor.animation == &"jump_rise"
	_sync_outline_frame()


func _on_actor_frame_changed() -> void:
	_sync_outline_frame()
	if actor.frame != 0:
		_rise_first = false
	if actor.animation == &"run" and actor.frame in RUN_CONTACT_FRAMES:
		_emit_step()


## Without the sheet the run cadence is timed the same way, so footsteps
## keep working on the placeholder.
func _placeholder_steps(delta: float, state: StringName) -> void:
	if state != &"run" or not player.is_on_floor():
		_run_phase = 0.0
		return
	var before := int(_run_phase)
	_run_phase = fmod(_run_phase + delta * PLACEHOLDER_RUN_FPS, 8.0)
	var now := int(_run_phase)
	if now != before and now in RUN_CONTACT_FRAMES:
		_emit_step()


func _emit_step() -> void:
	step_contact.emit(_foot)
	_foot = 1 - _foot


static func _input_active(f: PlayerInputFrame) -> bool:
	if f == null:
		return false
	return f.move_x != 0 or f.down_held or f.up_held or f.jump_pressed or f.jump_held or f.dodge_pressed \
		or f.light_pressed or f.heavy_pressed or f.ranged_pressed or f.interact_pressed or f.heal_pressed


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
		c.a = float(g.get("alpha", 0.35)) * (1.0 - g["age"] / GHOST_LIFETIME)
		var s: Vector2 = g["size"]
		draw_rect(Rect2(local + Vector2(-s.x * 0.5, -s.y), s), c)
	if actor:
		return

	# Body anchored at the feet so squash keeps contact with the floor.
	var size := _body_size() * _scale
	var body := Rect2(Vector2(-size.x * 0.5, -size.y), size).abs()
	var body_color := _body_color()
	# Blink while post-hit invulnerable so the grace period is readable.
	var a := hurt_alpha(player.combat.hurt_invuln_timer, Settings.flash_reduction)
	if a < 1.0:
		body_color.a = a
	if player.combat.dead:
		body_color = body_color.darkened(0.5)
	draw_rect(body, body_color)
	draw_rect(body, outline_color(UiTheme.high_contrast()), false, 1.0)
	# Visor: a 4x2 slit near the head on the facing side reads direction at a glance.
	var visor_y := body.position.y + minf(5.0, size.y * 0.25)
	var visor_x := 1.0 if player.facing > 0 else -5.0
	draw_rect(Rect2(Vector2(visor_x, visor_y), Vector2(4, 2)), VISOR_COLOR)


## Body alpha during post-hit invulnerability: a 10 Hz blink between 0.35 and
## 1, or a steady 0.55 under flash reduction (still reads as "can't be hit").
static func hurt_alpha(invuln_timer: float, reduced: bool) -> float:
	if invuln_timer <= 0.0:
		return 1.0
	if reduced:
		return 0.55
	return 0.35 if int(invuln_timer * 20.0) % 2 == 0 else 1.0


static func outline_color(hc: bool) -> Color:
	return Color.WHITE if hc else Color(0, 0, 0, 0.6)
