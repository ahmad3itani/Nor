extends RedlineTestCase
## Presentation overhaul T04: Rook's sheet drives the player visual. Every
## movement state and attack maps to an animation, the new hooks (turn, land,
## idle fidget, death, interact/rest, per-weapon shots) play as overlays that
## never touch gameplay state, and the accessibility paths (hurt blink on the
## tint mask, high-contrast outline) hold in sprite mode. A missing sheet
## falls back to the placeholder body.

const PLAYER_SCENE := preload("res://player/Player.tscn")
const VISUAL_SCRIPT := preload("res://player/animation/PlayerPlaceholderVisual.gd")

var world: Node2D
var player: Player
var visual: Node2D
var _snap: Dictionary


func before_each() -> void:
	_snap = snapshot_settings()
	Settings.flash_reduction = false
	Settings.high_contrast = false
	world = Node2D.new()
	add_child(world)


func after_each() -> void:
	world.queue_free()
	restore_settings(_snap)
	await physics_frames(1)


## Rook on a wide floor, grounded, then frozen (physics off) so a test can set
## states by hand and step the visual with advance().
func _spawn(spec: SpriteSheetSpec = null, use_spec := false) -> void:
	var b := GrayboxBlock.new()
	b.size = Vector2(1600, 64)
	b.position = Vector2(-400, 0)
	world.add_child(b)
	player = PLAYER_SCENE.instantiate()
	player.abilities = PlayerAbilities.new()
	player.input_source = ScriptedInputSource.new()
	visual = player.get_node("Visual")
	if use_spec:
		visual.sprite = spec
	world.add_child(player)
	player.respawn(Vector2(0, -2))
	# Long enough for the spawn landing one-shot to finish.
	await physics_frames(24)
	player.set_physics_process(false)
	player.last_input = PlayerInputFrame.new()


func _force(state: StringName) -> void:
	player.state_machine.force_state(state)
	visual.advance(0.0)


func test_player_scene_uses_the_rook_sheet() -> void:
	await _spawn()
	check(visual.sprite != null and visual.sprite.texture_path == "res://assets/rook/rook_sheet.png", "Player.tscn Visual.sprite is the Rook sheet")
	check(visual.actor != null, "the sheet builds an actor")
	check(visual.actor.mask != null, "the visor/seam tint mask is loaded")
	check(visual.sprite.get_meta(&"mask_palette_key", &"") == &"accent", "mask palette key is accent")


func test_each_movement_state_plays_its_animation() -> void:
	await _spawn()
	for state: StringName in [&"idle", &"run", &"crouch", &"slide", &"dodge", &"heal", &"hurt"]:
		_force(state)
		check(visual.actor.animation == state, "%s plays %s, got %s" % [state, state, visual.actor.animation])
	player.abilities.dash = true
	_force(&"dash")
	check(visual.actor.animation == &"dash", "dash plays dash, got %s" % visual.actor.animation)


func test_air_picks_rise_or_fall_by_velocity() -> void:
	await _spawn()
	_force(&"air")
	player.velocity.y = -120.0
	visual.advance(0.0)
	check(visual.actor.animation == &"jump_rise", "rising plays jump_rise, got %s" % visual.actor.animation)
	player.velocity.y = 120.0
	visual.advance(0.0)
	check(visual.actor.animation == &"jump_fall", "falling plays jump_fall, got %s" % visual.actor.animation)


func test_melee_plays_the_attack_id() -> void:
	await _spawn()
	var seen: Array = []
	for heavy: bool in [false, false, true]:
		if heavy:
			player.combat.heavy_buffer = 1.0
		else:
			player.combat.light_buffer = 1.0
		_force(&"melee")
		var id: StringName = player.combat.current_attack.id
		seen.append(id)
		check(visual.actor.animation == id, "melee %s plays its row, got %s" % [id, visual.actor.animation])
		_force(&"idle")
	check(seen == [&"blade_light_1", &"blade_light_2", &"blade_heavy"], "blade attacks swung: %s" % [seen])
	var katars: WeaponData = load("res://data/weapons/split_katars.tres")
	var frames: SpriteFrames = visual.actor.sprite_frames
	for atk: AttackData in katars.light_chain + [katars.heavy, katars.launcher, katars.air_light, katars.air_heavy]:
		if atk:
			check(frames.has_animation(atk.id), "the sheet has a row for %s" % atk.id)


func test_each_weapon_shot_maps_to_its_shoot_anim() -> void:
	await _spawn()
	var cases := {
		"res://data/weapons/service_pistol.tres": &"shoot_pistol",
		"res://data/weapons/scattergun.tres": &"shoot_scatter",
		"res://data/weapons/heavy_revolver.tres": &"shoot_revolver",
	}
	for path: String in cases:
		var w: WeaponData = load(path)
		check(VISUAL_SCRIPT.SHOT_ANIMS.get(w.shot.id) == cases[path], "%s shot id maps" % w.id)
		player.combat.fired.emit(w)
		visual.advance(0.0)
		check(visual.actor.animation == cases[path], "%s plays %s, got %s" % [w.id, cases[path], visual.actor.animation])
		# Layered over locomotion: running on does not cancel the shot.
		_force(&"run")
		check(visual.actor.animation == cases[path], "%s stays over run" % w.id)
		_force(&"idle")
		visual.call("_clear_overlay")


func test_a_reload_does_not_play_a_shoot_anim() -> void:
	await _spawn()
	var w: WeaponData = load("res://data/weapons/service_pistol.tres")
	EventBus.ranged_fired.emit(w, w.ammo_max)
	visual.advance(0.0)
	check(visual.actor.animation == &"idle", "a reload (ranged_fired) keeps idle, got %s" % visual.actor.animation)
	player.combat.fired.emit(w)
	visual.advance(0.0)
	check(visual.actor.animation == &"shoot_pistol", "combat.fired plays the shot")


func test_higher_priority_state_cancels_a_one_shot() -> void:
	await _spawn()
	player.combat.fired.emit(load("res://data/weapons/scattergun.tres"))
	visual.advance(0.0)
	_force(&"hurt")
	check(visual.actor.animation == &"hurt", "hurt beats a shot, got %s" % visual.actor.animation)
	check(visual.overlay() == &"", "the overlay is dropped")
	check(player.current_state_id() == &"hurt", "the overlay never touches the state")


func test_turn_plays_on_a_facing_flip_while_running() -> void:
	await _spawn()
	check(player.is_on_floor(), "grounded")
	_force(&"run")
	player.facing = -player.facing
	visual.advance(0.0)
	check(visual.actor.animation == &"turn", "a facing flip on the floor plays turn, got %s" % visual.actor.animation)
	check(visual.actor.flip_h == (player.facing < 0), "the sprite faces the new way at once")
	# Not in the air.
	_force(&"air")
	player.facing = -player.facing
	visual.advance(0.0)
	check(visual.actor.animation != &"turn", "no turn in the air")


func test_hard_landing_plays_land_hard() -> void:
	await _spawn()
	_force(&"air")
	player.landed.emit(player.config.hard_land_speed + 20.0)
	visual.advance(0.0)
	check(visual.actor.animation == &"land_hard", "hard landing plays land_hard, got %s" % visual.actor.animation)
	# Settling into idle after the landing is the landing itself.
	_force(&"idle")
	check(visual.actor.animation == &"land_hard", "land_hard survives the settle")
	var authored: Vector2 = visual.actor.scale
	var code: Vector2 = visual.get("_scale")
	check(absf(code.y - 1.0) > 0.1 and absf(authored.y - 1.0) < absf(code.y - 1.0) * 0.5, "code squash is scaled down over the authored squash")
	_force(&"run")
	check(visual.actor.animation == &"run", "a new input state takes over, got %s" % visual.actor.animation)
	_force(&"air")
	player.landed.emit(player.config.hard_land_speed * 0.5)
	visual.advance(0.0)
	check(visual.actor.animation == &"land", "a soft landing plays land, got %s" % visual.actor.animation)


func test_idle_fidget_after_idle_time_and_cancelled_by_input() -> void:
	await _spawn()
	_force(&"idle")
	for i in 19:
		visual.advance(0.3)
	check(visual.actor.animation == &"idle", "no fidget before 6 s")
	var seen := false
	for i in 20:
		visual.advance(0.25)
		if visual.actor.animation == &"idle_fidget":
			seen = true
			break
	check(seen, "idle_fidget plays within 10 s of continuous idle")
	player.last_input.move_x = 1
	visual.advance(0.0)
	check(visual.actor.animation != &"idle_fidget", "any input cancels the fidget")
	check(visual.overlay() == &"", "the fidget overlay is cleared")


func test_death_plays_once_and_holds_the_last_frame() -> void:
	await _spawn()
	player.combat.dead = true
	_force(&"hurt")
	check(visual.actor.animation == &"death", "death plays while dead, got %s" % visual.actor.animation)
	await physics_frames(75)
	var last: int = visual.actor.sprite_frames.get_frame_count(&"death") - 1
	check(visual.actor.animation == &"death" and visual.actor.frame == last, "death holds its last frame (%d)" % visual.actor.frame)
	player.combat.fired.emit(load("res://data/weapons/service_pistol.tres"))
	visual.advance(0.0)
	check(visual.actor.animation == &"death" and visual.actor.frame == last, "nothing overrides death")
	player.set_physics_process(true)
	player.respawn(Vector2(0, -2))
	visual.advance(0.0)
	check(visual.actor.animation == &"idle", "respawn resets to idle, got %s" % visual.actor.animation)


func test_interact_and_rest_hooks() -> void:
	await _spawn()
	EventBus.dialogue_requested.emit(null, "Orr")
	visual.advance(0.0)
	check(visual.actor.animation == &"interact", "dialogue plays interact, got %s" % visual.actor.animation)
	visual.call("_clear_overlay")
	EventBus.anchor_rested.emit(null)
	visual.advance(0.0)
	check(visual.actor.animation == &"interact", "resting starts with interact")
	await physics_frames(40)
	check(visual.actor.animation == &"rest", "then rests in a loop, got %s" % visual.actor.animation)
	await physics_frames(40)
	check(visual.actor.animation == &"rest", "rest holds until input")
	player.last_input.move_x = -1
	visual.advance(0.0)
	check(visual.actor.animation == &"idle", "input ends the rest, got %s" % visual.actor.animation)


func test_afterimages_copy_the_live_frame() -> void:
	await _spawn()
	_force(&"run")
	player.facing = -1
	visual.advance(0.0)
	visual.spawn_afterimage()
	var ghosts: Array = visual.afterimages()
	check(ghosts.size() == 1, "one afterimage")
	var g: Sprite2D = ghosts[0]
	var live: Texture2D = visual.actor.sprite_frames.get_frame_texture(visual.actor.animation, visual.actor.frame)
	check(g.texture == live, "the afterimage is the live frame's texture")
	check(g.flip_h == visual.actor.flip_h and g.offset == visual.actor.offset, "same flip and offset")
	check_near(g.modulate.a, 0.4, 0.001, "40 % alpha")
	check(g.modulate.r == Color("a9a3b8").r, "tinted #a9a3b8")
	visual.advance(0.3)
	check(visual.afterimages().is_empty(), "faded out after 0.25 s")


func test_step_contact_fires_twice_per_run_cycle() -> void:
	await _spawn()
	_force(&"run")
	var feet: Array = []
	visual.step_contact.connect(func(foot: int) -> void: feet.append(foot))
	for f in 8:
		visual.actor.frame = f
	check(feet.size() == 2, "two contacts per 8-frame run cycle, got %d" % feet.size())
	check(feet.size() == 2 and feet[0] != feet[1], "the feet alternate")
	feet.clear()
	player.landed.emit(50.0)
	check(feet == [VISUAL_SCRIPT.FOOT_LANDING], "a landing is a contact too")


func test_high_contrast_adds_the_outline_in_sprite_mode() -> void:
	await _spawn()
	visual.advance(0.0)
	check(visual.outline_nodes().is_empty(), "no outline by default")
	Settings.high_contrast = true
	visual.advance(0.0)
	var nodes: Array = visual.outline_nodes()
	check(nodes.size() == 4, "four outline copies, got %d" % nodes.size())
	var live: Texture2D = visual.actor.sprite_frames.get_frame_texture(visual.actor.animation, visual.actor.frame)
	check(nodes.all(func(s: Sprite2D) -> bool: return s.texture == live and s.is_visible_in_tree()), "the copies follow the live frame")
	Settings.high_contrast = false
	visual.advance(0.0)
	check(not nodes[0].is_visible_in_tree(), "hidden again with high contrast off")


func test_mask_overlay_blinks_with_hurt_iframes_and_tints_the_seam() -> void:
	await _spawn()
	player.combat.hurt_invuln_timer = 0.5
	visual.advance(0.0)
	visual.actor.sync_mask()
	check(visual.actor.self_modulate.a < 1.0, "the body blinks")
	check(is_equal_approx(visual.actor.mask.self_modulate.a, visual.actor.self_modulate.a), "the visor/seam overlay blinks with it")
	player.combat.hurt_invuln_timer = 0.0
	visual.advance(0.0)
	var accent := Palette.color(&"accent")
	check_near(visual.actor.mask.modulate.r, accent.r * VISUAL_SCRIPT.SEAM_VALUE, 0.01, "the seam idles at 0.8")
	_force(&"heal")
	var heal := Palette.color(&"heal")
	check_near(visual.actor.mask.modulate.g, heal.g * VISUAL_SCRIPT.SEAM_VALUE, 0.01, "heal-green while healing")


func test_missing_sheet_falls_back_to_the_placeholder() -> void:
	var spec := SpriteSheetSpec.new()
	spec.texture_path = "res://assets/rook/%s.png" % "no_such_sheet"
	var a := SpriteAnim.new()
	a.name = &"idle"
	spec.animations = [a]
	await _spawn(spec, true)
	check(visual.actor == null, "no actor without the texture")
	visual.advance(0.1)
	visual.spawn_afterimage()
	check(visual.afterimages().is_empty(), "placeholder afterimages stay rectangles")
	var feet: Array = []
	visual.step_contact.connect(func(foot: int) -> void: feet.append(foot))
	_force(&"run")
	for i in 36:
		visual.advance(1.0 / 60.0)
	check(feet.size() == 2, "the placeholder still marks two steps per cycle, got %d" % feet.size())


## Review fix: a non-looping base row (crouch, slide) plays once and holds its
## last frame while the state lasts; replaying it every tick bobbed Rook
## between stand and crouch.
func test_non_looping_base_rows_hold_their_last_frame() -> void:
	await _spawn()
	for state: StringName in [&"crouch", &"slide", &"dodge"]:
		_force(state)
		var frames: SpriteFrames = visual.actor.sprite_frames
		check(not frames.get_animation_loop(state), "%s is a one-pass row" % state)
		var last: int = frames.get_frame_count(state) - 1
		await physics_frames(30)
		var held: Array = []
		for i in 5:
			await physics_frames(8)
			held.append(visual.actor.frame)
		check(visual.actor.animation == state, "%s still plays %s" % [state, visual.actor.animation])
		check(held.all(func(f: int) -> bool: return f == last), "%s holds frame %d over 1 s, got %s" % [state, last, held])
		_force(&"idle")
	# Entering the state again replays the row from the start.
	_force(&"crouch")
	check(visual.actor.frame == 0 and visual.actor.is_playing(), "re-entering crouch replays it")


## Review fix: the outline copies draw flat white (the sprite's own colours
## would give a dark fringe). Headless runs cannot read pixels back, so the
## shader itself is checked.
func test_high_contrast_outline_shader_is_flat_white() -> void:
	await _spawn()
	Settings.high_contrast = true
	visual.advance(0.0)
	var nodes: Array = visual.outline_nodes()
	check(not nodes.is_empty(), "outline copies exist")
	var mat := (nodes[0] as Sprite2D).material as ShaderMaterial
	check(mat != null and mat.shader != null, "the copies use the outline shader")
	var code: String = mat.shader.code.replace(" ", "")
	check("COLOR=vec4(1.0,1.0,1.0," in code, "the fragment writes flat white")
	check(not "COLOR.rgb" in code and not "texture(TEXTURE,UV).rgb" in code, "no sprite colour reaches the outline")
	check("texture(TEXTURE,UV).a" in code, "the frame's alpha shapes the silhouette")
	check("v_mod.a" in code, "the modulate alpha (hurt blink) is kept")


## Review fix: a shot pose ends when Rook jumps, slides, crouches or heals.
func test_a_shot_yields_to_air_slide_crouch_and_heal() -> void:
	await _spawn()
	var w: WeaponData = load("res://data/weapons/service_pistol.tres")
	for state: StringName in [&"air", &"slide", &"crouch", &"heal"]:
		_force(&"idle")
		player.velocity.y = -120.0
		player.combat.fired.emit(w)
		visual.advance(0.0)
		check(visual.overlay() == &"shoot_pistol", "the shot plays")
		_force(state)
		check(visual.overlay() == &"", "%s ends the shot" % state)
		check(visual.actor.animation != &"shoot_pistol", "%s shows its own row, got %s" % [state, visual.actor.animation])
	player.velocity.y = 0.0


## Review fix: only the first pass of jump_rise's frame 0 is an authored
## squash; the looping row coming back to frame 0 is not.
func test_rise_squash_only_on_the_first_frame() -> void:
	await _spawn()
	player.velocity.y = -120.0
	_force(&"air")
	check(visual.actor.animation == &"jump_rise" and visual.actor.frame == 0, "rise starts on frame 0")
	check(visual.call("_authored_squash_playing"), "the first frame is authored squash")
	visual.actor.frame = 1
	visual.actor.frame = 0
	check(not visual.call("_authored_squash_playing"), "the loop back to frame 0 is not")
	player.velocity.y = 0.0
