extends RedlineTestCase
## Presentation overhaul T05: enemy, boss, Sweeper, Collector eye and NPC
## sprites. Visual only: every EnemyData number stays as recorded before the
## overhaul (tests/fixtures/enemy_data_fields.json), placeholders stay the
## fallback, bosses map every attack to a sheet row.

const ENEMY_SCENE := "res://enemies/variants/Needle.tscn"
const COLLECTOR_SCENE := "res://bosses/CollectorDrone.tscn"
const KRAIL_SCENE := "res://bosses/WardenKrail.tscn"
const MISSING := "res://assets/enemies/t05_missing_sheet.png"

var _root: Node2D
var _saved := {}


func before_each() -> void:
	_root = Node2D.new()
	_root.name = "T05Root"
	add_child(_root)
	_saved = {"hc": Settings.high_contrast, "fr": Settings.flash_reduction}


func after_each() -> void:
	Settings.high_contrast = _saved["hc"]
	Settings.flash_reduction = _saved["fr"]
	_root.queue_free()
	await physics_frames(2)


func _enemies() -> Array[EnemyData]:
	var out: Array[EnemyData] = []
	for path in DataDir.list("res://data/enemies"):
		var d := load(path) as EnemyData
		if d:
			out.append(d)
	return out


## An enemy on the test root, physics off (no fall, no AI); its visual runs.
func _spawn(data: EnemyData, scene := ENEMY_SCENE, physics := false, ai_on := true) -> Enemy:
	var e := (load(scene) as PackedScene).instantiate() as Enemy
	e.data = data
	e.ai_enabled = ai_on
	e.position = Vector2(100, 100)
	_root.add_child(e)
	e.set_physics_process(physics)
	return e


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _visual(e: Enemy) -> Node2D:
	return e.get_node(^"Visual") as Node2D


func _set_ai(e: Enemy, ai: int, attack: AttackData = null) -> void:
	e.ai = ai
	e.ai_time = 0.0
	e.current_attack = attack


func _step(e: Enemy) -> SpriteActor:
	var v := _visual(e)
	v.call(&"_update_actor", 1.0 / 60.0)
	return v.get(&"actor") as SpriteActor


func _has(spec: SpriteSheetSpec, anim: StringName) -> bool:
	return spec.animations.any(func(a: SpriteAnim) -> bool: return a.name == anim)


# --- Data ---------------------------------------------------------------------------

func test_every_enemy_has_a_valid_sheet() -> void:
	for d in _enemies():
		check(d.sprite != null, "%s: no sprite" % d.resource_path)
		if d.sprite == null:
			continue
		check(d.sprite.validate().is_empty(), "%s: %s" % [d.resource_path, d.sprite.validate()])
		for a in [&"idle", &"hurt", &"death"]:
			check(_has(d.sprite, a), "%s sheet has no %s" % [d.resource_path.get_file(), a])


func test_enemy_numbers_match_the_pre_overhaul_fixture() -> void:
	var before := EnemyFieldDump.read_fixture()
	check(not before.is_empty(), "fixture missing")
	var now := EnemyFieldDump.dump_all()
	check(now.keys().size() == before.keys().size(), "enemy files added or removed: %s vs %s" % [now.keys(), before.keys()])
	for k in before:
		check(now.has(k), "%s missing" % k)
		if not now.has(k):
			continue
		# JSON round trip, so both sides compare as parsed JSON.
		var a: Variant = JSON.parse_string(JSON.stringify(now[k]))
		check(a == before[k], "%s: gameplay fields or validate() changed" % k)


func test_colour_moves() -> void:
	check((load("res://data/enemies/needle.tres") as EnemyData).color.to_html(false) == "c9c2b4", "needle colour")
	check((load("res://data/enemies/enforcer.tres") as EnemyData).color.to_html(false) == "5a2a30", "enforcer colour")
	check((load("res://data/enemies/scout_drone.tres") as EnemyData).color.to_html(false) == "7a6034", "scout colour")
	check((load("res://data/enemies/needle_null.tres") as EnemyData).sprite_modulate != Color.WHITE, "null variant is a palette swap")
	check((load("res://data/enemies/warden_krail.tres") as EnemyData).sprite_modulate == Color.WHITE, "base Krail untinted")


# --- EnemyVisual -----------------------------------------------------------------------

func test_every_enemy_plays_its_states() -> void:
	var seen := {}
	for d in _enemies():
		if seen.has(d.sprite.resource_path) or d.boss:
			continue
		seen[d.sprite.resource_path] = true
		var e := _spawn(d)
		var v := _visual(e)
		check(v.call(&"uses_sprite"), "%s: no sprite" % d.id)
		var actor := _step(e)
		check(actor.animation == &"idle", "%s idle: %s" % [d.id, actor.animation])
		e.velocity = Vector2(40, 0)
		_set_ai(e, Enemy.AI.ENGAGE)
		actor = _step(e)
		check(actor.animation == (&"move" if _has(d.sprite, &"move") else &"idle"), "%s move: %s" % [d.id, actor.animation])
		e.velocity = Vector2.ZERO
		_set_ai(e, Enemy.AI.WINDUP, d.attacks[0])
		actor = _step(e)
		check(String(actor.animation).begins_with("windup"), "%s windup: %s" % [d.id, actor.animation])
		check(not actor.sprite_frames.get_animation_loop(actor.animation), "%s windup loops" % d.id)
		_set_ai(e, Enemy.AI.ACTIVE, d.attacks[0])
		actor = _step(e)
		check(String(actor.animation).begins_with("attack"), "%s attack: %s" % [d.id, actor.animation])
		_set_ai(e, Enemy.AI.IDLE)
		_step(e)
		EventBus.enemy_damaged.emit(e, HitInfo.create(null, d.attacks[0], Vector2.ZERO, Vector2.RIGHT), CombatResult.HIT)
		actor = _step(e)
		check(actor.animation == &"hurt", "%s hurt one-shot: %s" % [d.id, actor.animation])
		check(actor.position.x > 0.0 and actor.position.x <= 2.0, "%s knock along the hit: %s" % [d.id, actor.position])
		_set_ai(e, Enemy.AI.DEAD)
		actor = _step(e)
		check(actor.animation == &"death", "%s death: %s" % [d.id, actor.animation])
		e.queue_free()


func test_windup_pose_holds_its_last_frame() -> void:
	var d := load("res://data/enemies/enforcer.tres") as EnemyData
	var e := _spawn(d)
	_set_ai(e, Enemy.AI.WINDUP, d.attacks[0])
	var actor := _step(e)
	var name := actor.animation
	var last := actor.sprite_frames.get_frame_count(name) - 1
	for i in 120:
		await get_tree().process_frame
		if actor.frame == last and not actor.is_playing():
			break
	_step(e)
	await get_tree().process_frame
	check(actor.animation == name and actor.frame == last, "wind-up restarted instead of holding (%s %d)" % [actor.animation, actor.frame])
	var lunge: AttackData = null
	for a in d.attacks:
		if String(a.id).contains("lunge"):
			lunge = a
	if lunge:
		_set_ai(e, Enemy.AI.WINDUP, lunge)
		check(_step(e).animation == &"windup_lunge", "enforcer lunge pose")
		_set_ai(e, Enemy.AI.ACTIVE, lunge)
		check(_step(e).animation == &"attack_lunge", "enforcer lunge strike")


func test_dormant_needle_plays_dormant() -> void:
	var e := _spawn(load("res://data/enemies/needle_dormant.tres") as EnemyData, ENEMY_SCENE, false, false)
	check(_step(e).animation == &"dormant", "dormant row")


func test_guard_break_plays_on_a_broken_guard() -> void:
	var d := load("res://data/enemies/shield.tres") as EnemyData
	var e := _spawn(d, "res://enemies/variants/Shield.tscn")
	e.facing = 1
	_step(e)
	e.poise = 0.01
	var atk := AttackData.new()
	atk.id = &"t05_poke"
	atk.damage = 1.0
	atk.poise_damage = 5.0
	var hit := HitInfo.create(null, atk, Vector2(-50, 0), Vector2.LEFT)
	hit.source_position = e.global_position + Vector2(20, -10)
	e.receive_hit(hit)
	var actor := _step(e)
	check(actor.animation == &"guard_break", "guard break row: %s" % actor.animation)


func test_windup_tint_and_high_contrast_outline_in_sprite_mode() -> void:
	var d := load("res://data/enemies/needle.tres") as EnemyData
	var e := _spawn(d)
	var v := _visual(e)
	Settings.high_contrast = false
	var actor := _step(e)
	check(actor.self_modulate == Color.WHITE, "idle untinted")
	check((v.get(&"outline_nodes") as Array).is_empty(), "no outline without high contrast")
	_set_ai(e, Enemy.AI.WINDUP, d.attacks[0])
	actor = _step(e)
	check(actor.self_modulate != Color.WHITE and actor.self_modulate.r >= actor.self_modulate.g, "wind-up tints the sprite: %s" % actor.self_modulate)
	Settings.flash_reduction = true
	var a := EnemyVisual_windup(0.0)
	var b := EnemyVisual_windup(0.37)
	check(a == b, "wind-up tint holds still under flash reduction")
	Settings.high_contrast = true
	_step(e)
	var nodes: Array = v.get(&"outline_nodes")
	check(nodes.size() == 4, "4 outline copies: %d" % nodes.size())
	for n in nodes:
		check((n as Sprite2D).visible and (n as Sprite2D).texture != null, "outline copy drawn")
	Settings.high_contrast = false
	_step(e)
	for n in nodes:
		check(not (n as Sprite2D).visible, "outline hidden again")


func EnemyVisual_windup(t: float) -> Color:
	return (load("res://enemies/base/EnemyVisual.gd") as GDScript).call(&"windup_tint", t, Settings.flash_reduction)


func test_missing_sheet_keeps_the_placeholder() -> void:
	var d := (load("res://data/enemies/needle.tres") as EnemyData).duplicate() as EnemyData
	var spec := d.sprite.duplicate() as SpriteSheetSpec
	spec.texture_path = MISSING
	d.sprite = spec
	var e := _spawn(d)
	check(not _visual(e).call(&"uses_sprite"), "missing sheet must fall back to the placeholder")
	_visual(e).queue_redraw()
	await get_tree().process_frame


# --- Death -------------------------------------------------------------------------------

func test_killed_enemy_leaves_a_corpse_that_frees_itself() -> void:
	var d := load("res://data/enemies/needle_dormant.tres") as EnemyData
	var e := _spawn(d, ENEMY_SCENE, true, false)
	var floor_body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(400, 20)
	shape.shape = rect
	floor_body.add_child(shape)
	floor_body.position = Vector2(100, 110)
	floor_body.collision_layer = CombatLayers.WORLD
	_root.add_child(floor_body)
	await physics_frames(10)
	var atk := AttackData.new()
	atk.id = &"t05_kill"
	atk.damage = 999.0
	var hit := HitInfo.create(null, atk, Vector2.ZERO, Vector2.RIGHT)
	hit.source_position = e.global_position
	e.receive_hit(hit)
	check(e.is_dead(), "killed")
	var corpse: Node = null
	for i in 90:
		await get_tree().physics_frame
		corpse = _root.get_node_or_null(^"EnemyCorpse")
		if corpse:
			break
	check(corpse != null, "no corpse left behind")
	if corpse == null:
		return
	check(not is_instance_valid(e) or e.is_queued_for_deletion(), "body freed")
	check(corpse.find_children("*", "CollisionObject2D", true, false).is_empty() and not (corpse is CollisionObject2D), "corpse has collision")
	check((corpse as CanvasItem).modulate.r <= 0.61, "corpse darkened: %s" % (corpse as CanvasItem).modulate)
	check((corpse as VfxOneShot).animation == &"death", "corpse plays death")
	var burst := false
	for c in _root.get_children():
		if c is VfxOneShot and (c as VfxOneShot).vfx_id == &"death_burst":
			burst = true
	check(burst, "death burst spawned")
	var freed := false
	for i in 150:
		await get_tree().physics_frame
		if not is_instance_valid(corpse):
			freed = true
			break
	check(freed, "corpse never freed")


func test_burst_tint_is_readable_and_rows_exist() -> void:
	var enforcer := Color("5a2a30")
	check(EnemyVisual_lstar(EnemyVisual_burst(enforcer)) >= 60.0, "enforcer burst L* %.1f" % EnemyVisual_lstar(EnemyVisual_burst(enforcer)))
	for d in _enemies():
		check(EnemyVisual_lstar(EnemyVisual_burst(d.color)) >= 60.0, "%s burst too dark" % d.resource_path.get_file())
	var small := VfxLibrary.frames(&"death_burst")
	var boss := VfxLibrary.frames(&"death_burst_boss")
	check(small != null and small.has_animation(&"small") and small.has_animation(&"large"), "death_burst rows")
	check(boss != null and boss.has_animation(&"boss"), "death_burst_boss row")
	var ev := load("res://enemies/base/EnemyVisual.gd") as GDScript
	var krail := load("res://data/enemies/warden_krail.tres") as EnemyData
	check(ev.call(&"burst_anim", krail) == &"boss", "boss burst row")
	check(ev.call(&"burst_anim", load("res://data/enemies/needle.tres")) == &"small", "regular burst row")


func EnemyVisual_burst(c: Color) -> Color:
	return (load("res://enemies/base/EnemyVisual.gd") as GDScript).call(&"burst_tint", c)


func EnemyVisual_lstar(c: Color) -> float:
	return (load("res://enemies/base/EnemyVisual.gd") as GDScript).call(&"lstar", c)


# --- Bosses ----------------------------------------------------------------------------

func _all_attacks(d: EnemyData) -> Array[AttackData]:
	var out: Array[AttackData] = []
	for a in d.attacks:
		var f := a
		while f:
			out.append(f)
			f = f.follow_up
	return out


func _check_boss_map(scene: String, data_path: String) -> Enemy:
	var d := load(data_path) as EnemyData
	var e := _spawn(d, scene)
	for a in _all_attacks(d):
		for ai in [Enemy.AI.WINDUP, Enemy.AI.ACTIVE, Enemy.AI.RECOVER]:
			_set_ai(e, ai, a)
			var names := e.behavior.anim_names(ai, a)
			check(not names.is_empty() and _has(d.sprite, names[0]), "%s %s %s -> %s" % [d.id, a.id, Enemy.AI.keys()[ai], names])
	for ai in [Enemy.AI.STAGGER, Enemy.AI.DEAD]:
		_set_ai(e, ai)
		var names := e.behavior.anim_names(ai, null)
		check(not names.is_empty() and _has(d.sprite, names[0]), "%s %s -> %s" % [d.id, Enemy.AI.keys()[ai], names])
	_set_ai(e, Enemy.AI.ENGAGE)
	return e


func test_collector_maps_every_attack() -> void:
	var e := _check_boss_map(COLLECTOR_SCENE, "res://data/enemies/collector_drone.tres")
	var b := e.behavior
	var press := b.call(&"attack", &"collector_drop_press") as AttackData
	_set_ai(e, Enemy.AI.WINDUP, press)
	check(e.behavior.anim_names(Enemy.AI.WINDUP, press)[0] == &"windup_press", "press tell")
	_set_ai(e, Enemy.AI.ACTIVE, press)
	check(e.behavior.anim_names(Enemy.AI.ACTIVE, press)[0] == &"rotors_cut", "press drop with rotors cut")
	b.set(&"phase", 2)
	b.set(&"_pause", 1.0)
	_set_ai(e, Enemy.AI.ENGAGE)
	check(_step(e).animation == &"phase2", "phase 2 pause row")


func test_krail_maps_every_attack() -> void:
	var e := _check_boss_map(KRAIL_SCENE, "res://data/enemies/warden_krail.tres")
	var b := e.behavior
	b.set(&"phase", 2)
	b.set(&"_pause", 1.0)
	check(_step(e).animation == &"phase2_roar", "roar during the phase pause")
	_set_ai(e, Enemy.AI.STAGGER)
	check(_step(e).animation == &"stagger", "stagger row")
	check(WardenKrailBehavior_tip() == Color("cfe4f2"), "baton tip moved off guard blue")


func WardenKrailBehavior_tip() -> Color:
	return (load("res://bosses/WardenKrailBehavior.gd") as GDScript).get(&"BATON_TIP")


func test_krail_null_visor_is_white() -> void:
	var e := _spawn(load("res://data/enemies/warden_krail_null.tres") as EnemyData, KRAIL_SCENE)
	var actor := _step(e)
	check(actor.mask != null and actor.mask.modulate == Color.WHITE, "null visor mask tint")
	check(actor.modulate != Color.WHITE, "null palette swap")


# --- Sweeper, Collector eye, NPC -----------------------------------------------------------

func test_pursuer_maps_every_mode() -> void:
	var spec := load(Pursuer.SPRITE_PATH) as SpriteSheetSpec
	for m in Pursuer.Mode.values():
		check(_has(spec, Pursuer.anim_for(m)), "Sweeper mode %s -> %s" % [Pursuer.Mode.keys()[m], Pursuer.anim_for(m)])
	var p := Pursuer.new()
	p.data = load("res://data/world/chase/test_chase.tres") as PursuerData
	_root.add_child(p)
	await _frames(2)
	check(p.uses_sprite(), "Sweeper sprite")
	p.set_mode(Pursuer.Mode.CHASE)
	await _frames(2)
	check(p.actor.animation == &"chase", "chase row")
	p.set_mode(Pursuer.Mode.DERAIL)
	await _frames(2)
	check(p.actor.animation == &"derail" and not p.actor.is_playing(), "derail is progress-driven")
	var q := Pursuer.new()
	q.sprite_path = "res://assets/lowlight/t05_missing_sheet.tres"
	q.data = p.data
	_root.add_child(q)
	await _frames(2)
	check(not q.uses_sprite(), "missing Sweeper sheet keeps the placeholder")


func test_collector_eye_maps_every_state() -> void:
	var spec := load(CeilingTracker.SPRITE_PATH) as SpriteSheetSpec
	check(spec.origin == Vector2i(16, 4), "rail point origin")
	for s in CeilingTracker.State.values():
		check(_has(spec, CeilingTracker.anim_for(s)), "eye state %s -> %s" % [CeilingTracker.STATE_NAMES[s], CeilingTracker.anim_for(s)])
	check(_has(spec, &"fire"), "fire row")


func test_npc_sprite_idle_talk_and_voice() -> void:
	var orr := load("res://data/npcs/orr.tres") as NpcProfile
	var npc := NPC.new()
	npc.profile = orr
	_root.add_child(npc)
	await _frames(2)
	check(npc.actor != null and npc.actor.animation == &"idle", "NPC idles")
	EventBus.dialogue_requested.emit(DialogueData.new(), "Someone else")
	await _frames(2)
	check(npc.actor.animation != &"talk", "another speaker's dialogue")
	EventBus.dialogue_requested.emit(DialogueData.new(), orr.display_name)
	await _frames(2)
	check(npc.actor.animation == &"talk", "talks in its dialogue: %s" % npc.actor.animation)
	EventBus.dialogue_finished.emit(DialogueData.new())
	await _frames(2)
	check(npc.actor.animation == &"idle", "idle after the dialogue")
	var radio := NPC.new()
	radio.profile = load("res://data/npcs/orr_radio.tres") as NpcProfile
	_root.add_child(radio)
	await _frames(2)
	check(radio.actor == null, "a bodiless voice draws no sprite")
