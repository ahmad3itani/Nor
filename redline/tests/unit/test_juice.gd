extends RedlineTestCase
## Presentation overhaul T06: combat juice and power effects. Every spawn
## site draws its vfx sprite when the sheet loads and keeps the old
## placeholder (HitSpark / DustBurst particles, SlashArc, drawn motes) when
## VfxLibrary points at a missing sheet; nothing here touches gameplay.

const PLAYER_SCENE := preload("res://player/Player.tscn")
const PISTOL := preload("res://data/weapons/service_pistol.tres")
const SCATTER := preload("res://data/weapons/scattergun.tres")
const REVOLVER := preload("res://data/weapons/heavy_revolver.tres")
const BLADE := preload("res://data/weapons/pulse_blade.tres")
const KATARS := preload("res://data/weapons/split_katars.tres")
const EYE_BOLT := preload("res://data/combat/collector_eye_bolt.tres")
const TAG_VOLLEY := preload("res://data/combat/collector_tag_volley.tres")
const PRESS_WAVE := preload("res://data/combat/collector_press_wave.tres")
## The T06 sources: no camera writes (shake only via EventBus).
const OWN_SOURCES: Array[String] = ["res://vfx/HitSpark.gd", "res://vfx/DustBurst.gd", "res://vfx/SlashArc.gd",
	"res://vfx/PulseMotes.gd", "res://vfx/CoreAura.gd", "res://vfx/PowerFlourish.gd", "res://vfx/JuiceDirector.gd",
	"res://player/animation/PlayerFeedback.gd"]

var world: Node2D
var player: Player
var input: ScriptedInputSource
var _snap: Dictionary = {}
## id -> original spec path, for sheets a test pointed at a missing file.
var _broken: Dictionary = {}
var _shakes: Array = []


func before_each() -> void:
	_snap = snapshot_settings()
	Settings.flash_reduction = false
	Settings.ambient_motion = Motion.FULL
	world = Node2D.new()
	add_child(world)
	var floor_block := GrayboxBlock.new()
	floor_block.size = Vector2(2000, 64)
	floor_block.position = Vector2(-1000, 0)
	world.add_child(floor_block)
	player = PLAYER_SCENE.instantiate()
	player.abilities = PlayerAbilities.new()
	input = ScriptedInputSource.new()
	player.input_source = input
	world.add_child(player)
	player.add_to_group(&"player")
	player.respawn(Vector2(0, -2))
	_shakes.clear()
	EventBus.camera_shake_requested.connect(_on_shake)
	await physics_frames(3)


func after_each() -> void:
	EventBus.camera_shake_requested.disconnect(_on_shake)
	_restore_sheets()
	ScrapPickup.reset_art_cache()
	world.queue_free()
	await physics_frames(2)
	restore_settings(_snap)
	Palette.invalidate()


func _on_shake(t: float) -> void:
	_shakes.append(t)


## Points the library id at a missing sheet (the placeholder path).
func _break_sheet(id: StringName) -> void:
	var e: Dictionary = VfxLibrary.get_library().entries[id]
	if not _broken.has(id):
		_broken[id] = e["spec"]
	e["spec"] = "res://assets/vfx/test_missing_sheet.tres"
	VfxLibrary._specs.erase(id)
	VfxLibrary._frames.erase(id)


func _restore_sheets() -> void:
	for id in _broken:
		(VfxLibrary.get_library().entries[id] as Dictionary)["spec"] = _broken[id]
	_broken.clear()
	VfxLibrary.clear_cache()


func _all(root: Node, pred: Callable) -> Array[Node]:
	var out: Array[Node] = []
	for c in root.get_children():
		if pred.call(c):
			out.append(c)
		out.append_array(_all(c, pred))
	return out


func _vfx(id: StringName, anim: StringName = &"") -> Array[Node]:
	return _all(world, func(n: Node) -> bool:
		return n is VfxOneShot and (n as VfxOneShot).vfx_id == id and (anim == &"" or (n as VfxOneShot).animation == anim))


func _sparks() -> Array[Node]:
	return _all(world, func(n: Node) -> bool: return n is HitSpark)


func _dust_particles() -> Array[Node]:
	return _all(world, func(n: Node) -> bool: return n is DustBurst)


# --- hit sparks ---------------------------------------------------------------

func test_spark_rows_follow_the_hit() -> void:
	var light: AttackData = BLADE.light_chain[0]
	check(HitSpark.row_for(light, CombatResult.HIT) == &"spark_small", "light hit: small")
	check(HitSpark.row_for(BLADE.heavy, CombatResult.HIT) == &"spark_heavy", "blade_heavy: heavy")
	check(HitSpark.row_for(BLADE.launcher, CombatResult.HIT) == &"spark_heavy", "launcher: heavy")
	var spin: AttackData = null
	for a: AttackData in [KATARS.heavy, KATARS.launcher, KATARS.air_heavy]:
		if a and String(a.id) == "katar_spin":
			spin = a
	if spin:
		check(HitSpark.is_heavy(spin), "katar_spin: heavy")
	check(HitSpark.row_for(BLADE.light_chain[2], CombatResult.HIT) == &"spark_heavy", "damage >= threshold: heavy")
	check(HitSpark.row_for(light, CombatResult.BLOCKED) == &"spark_guard", "blocked: guard")
	check(HitSpark.row_for(light, CombatResult.KILLED) == &"spark_crit", "the finishing hit: crit")


func test_spark_sprite_and_placeholder() -> void:
	var fx := HitSpark.play(world, Vector2(10, -10), Vector2.RIGHT, &"spark_small")
	check(fx is VfxOneShot and (fx as VfxOneShot).animation == &"spark_small", "sprite spark")
	var guard := HitSpark.play(world, Vector2.ZERO, Vector2.LEFT, &"spark_guard", HitSpark.GUARD_COLOR, 6)
	check(guard is VfxOneShot and guard.modulate.is_equal_approx(HitSpark.GUARD_COLOR), "guard spark keeps the literal guard blue")
	_break_sheet(&"hit_sparks")
	var old := HitSpark.play(world, Vector2.ZERO, Vector2.RIGHT, &"spark_small", HitSpark.NO_TINT, 10, 140.0, Color.WHITE)
	check(old is HitSpark and (old as HitSpark).amount == 10, "missing sheet: the particle sparks")


func test_spark_rotation_is_a_quarter_turn() -> void:
	for d in [Vector2(1, 0.3), Vector2(-1, -0.3), Vector2(0.2, 1), Vector2(0.1, -1), Vector2(0.7, 0.7), Vector2(-0.6, 0.8)]:
		var fx := HitSpark.play(world, Vector2.ZERO, d, &"spark_heavy")
		var deg := fposmod(rad_to_deg(fx.rotation), 360.0)
		var ok := false
		for q in [0.0, 90.0, 180.0, 270.0]:
			ok = ok or is_equal_approx(deg, q)
		check(ok, "direction %s -> %s degrees" % [d, deg])
		fx.free()


func test_flash_reduction_dims_and_swaps_the_crit_row() -> void:
	var full := HitSpark.play(world, Vector2.ZERO, Vector2.RIGHT, &"spark_crit") as VfxOneShot
	check(full.animation == &"spark_crit", "crit row by default")
	Settings.flash_reduction = true
	var soft := HitSpark.play(world, Vector2.ZERO, Vector2.RIGHT, &"spark_crit") as VfxOneShot
	check(soft.animation == &"spark_heavy", "flash reduction: the flash-safe row, never the white-core crit")
	check(soft.modulate.v < full.modulate.v and soft.modulate.v <= VfxOneShot.FLASH_REDUCED_VALUE + 0.01,
		"flash reduction lowers the value (%s vs %s)" % [soft.modulate, full.modulate])
	var mote := PulseMotes.accent_color()
	check(mote.v < Palette.color(&"accent").v + 0.001 and mote.v <= Palette.color(&"accent").v * 0.71, "mote red is dimmed too")


func test_player_hit_draws_a_sprite_spark() -> void:
	var e: Enemy = preload("res://enemies/variants/Needle.tscn").instantiate()
	e.ai_enabled = false
	e.position = Vector2(20, -2)
	world.add_child(e)
	await physics_frames(3)
	input.press_light()
	await physics_frames(12)
	check(_vfx(&"hit_sparks").size() + _sparks().size() >= 1, "a hit makes sparks")
	check(_vfx(&"hit_sparks").size() >= 1, "the sprite spark, not particles")
	check(_sparks().is_empty(), "no placeholder particles when the sheet loads")


# --- slash smears -------------------------------------------------------------

func test_smear_row_per_attack_id() -> void:
	var want := {
		&"blade_light_1": &"light", &"blade_light_2": &"light", &"blade_light_3": &"light", &"blade_heavy": &"heavy",
		&"blade_launcher": &"launcher", &"blade_air_light": &"air", &"blade_air_heavy": &"spike",
		&"katar_light_1": &"katar", &"katar_light_4": &"katar", &"katar_cross": &"katar", &"katar_dive": &"katar",
		&"katar_spin": &"katar_spin", &"pistol_shot": &"", &"mystery_swing": &"",
	}
	for id in want:
		check(SlashArc.smear_row(id) == want[id], "%s -> '%s' (got '%s')" % [id, want[id], SlashArc.smear_row(id)])
	var frames := VfxLibrary.frames(&"slash_smears")
	for w: WeaponData in [BLADE, KATARS]:
		for a: AttackData in w.light_chain + [w.heavy, w.launcher, w.air_light, w.air_heavy]:
			if a:
				check(frames.has_animation(SlashArc.smear_row(a.id)), "%s has a smear row in the sheet" % a.id)


func test_melee_smear_waits_for_the_active_window() -> void:
	input.press_light()
	await physics_frames(1)
	var attack := player.combat.current_attack
	check(attack != null and attack.startup > 0.0, "swing started")
	check(_vfx(&"slash_smears").is_empty(), "no smear during startup")
	await physics_frames(int(ceil(attack.startup * 60.0)) + 1)
	var smears := _vfx(&"slash_smears", &"light")
	check(smears.size() == 1, "one light smear in the active window")
	check(_all(world, func(n: Node) -> bool: return n is SlashArc).is_empty(), "no arc placeholder with the sheet")
	if smears.size() == 1:
		var fx := smears[0] as VfxOneShot
		var box := attack.world_hitbox(player.global_position, player.facing)
		check(fx.global_position.distance_to(box.get_center()) < 12.0, "smear sits on the hitbox")


func test_melee_arc_placeholder_without_the_sheet() -> void:
	_break_sheet(&"slash_smears")
	input.press_light()
	await physics_frames(2)
	check(_all(world, func(n: Node) -> bool: return n is SlashArc).size() == 1, "the SlashArc placeholder draws")
	check(_vfx(&"slash_smears").is_empty(), "no sprite smear")


# --- dust ---------------------------------------------------------------------

func test_landing_dust_sprite_and_placeholder() -> void:
	var seen := [0, 0]
	player.respawn(Vector2(0, -120))
	for i in 90:
		await physics_frames(1)
		seen[0] = maxi(seen[0], _vfx(&"dust", &"land_hard").size() + _vfx(&"dust", &"land").size())
		seen[1] = maxi(seen[1], _dust_particles().size())
	check(seen[0] >= 1, "landing draws a dust sprite")
	check(seen[1] == 0, "no particle dust with the sheet")
	_break_sheet(&"dust")
	player.respawn(Vector2(0, -120))
	seen = [0, 0]
	for i in 90:
		await physics_frames(1)
		seen[1] = maxi(seen[1], _dust_particles().size())
	check(seen[1] >= 1, "missing sheet: DustBurst particles")


func test_dust_on_water_uses_splash_rows() -> void:
	var fx := DustBurst.puff(world, &"land", Vector2.ZERO, 1, true)
	check(fx != null and fx.vfx_id == &"splash" and fx.animation == &"land", "water landing splashes")
	check(DustBurst.puff(world, &"run_puff", Vector2.ZERO, -1, true).animation == &"step", "water steps")
	check(DustBurst.puff(world, &"wall_scrape", Vector2.ZERO, 1, true) == null, "no wall scrape on water")


func test_run_puffs_follow_the_motion_setting() -> void:
	var fb: Node = player.get_node("Feedback")
	player.state_machine.force_state(&"run")
	for lv in [Motion.FULL, Motion.REDUCED, Motion.OFF]:
		Settings.ambient_motion = lv
		for fx in _vfx(&"dust"):
			fx.free()
		for i in 4:
			fb.call("_on_step_contact")
		var n := _vfx(&"dust", &"run_puff").size()
		check(n == [4, 2, 0][lv], "motion %d: %d run puffs" % [lv, n])


# --- muzzle and projectiles -----------------------------------------------------

func test_muzzle_rows_and_placeholder() -> void:
	var rows := {PISTOL: &"pistol", SCATTER: &"scatter", REVOLVER: &"revolver"}
	for w: WeaponData in rows:
		var fx := Projectile.muzzle_flash(world, Vector2.ZERO, Vector2.RIGHT, w)
		check(fx is VfxOneShot and (fx as VfxOneShot).animation == rows[w], "%s muzzle" % w.id)
	_break_sheet(&"muzzle")
	check(Projectile.muzzle_flash(world, Vector2.ZERO, Vector2.RIGHT, PISTOL) is HitSpark, "missing sheet: muzzle sparks")


func test_projectile_heads() -> void:
	var cases := [
		[PISTOL.shot, CombatLayers.ENEMY_HURTBOX, &"pistol_bolt"],
		[SCATTER.shot, CombatLayers.ENEMY_HURTBOX, &"pellet"],
		[REVOLVER.shot, CombatLayers.ENEMY_HURTBOX, &"revolver_round"],
		[EYE_BOLT, CombatLayers.PLAYER_HURTBOX, &"enemy_bolt"],
		[TAG_VOLLEY, CombatLayers.PLAYER_HURTBOX, &"collector_tag"],
		[PRESS_WAVE, CombatLayers.PLAYER_HURTBOX, &"ground_wave"],
	]
	for c in cases:
		var p := Projectile.spawn(world, null, c[0], Vector2(0, -300), Vector2.RIGHT, c[1])
		check(p.head_row() == c[2], "%s -> %s" % [c[0].id, c[2]])
		check(is_instance_valid(p.head_sprite) and p.head_sprite.animation == c[2], "%s head sprite" % c[0].id)
		if c[1] == CombatLayers.PLAYER_HURTBOX and c[2] != &"collector_tag":
			check(p.head_sprite.modulate.is_equal_approx(Palette.color(&"danger")), "enemy shot tinted danger")
		p.free()
	_break_sheet(&"projectiles")
	var bare := Projectile.spawn(world, null, PISTOL.shot, Vector2(0, -300), Vector2.RIGHT, CombatLayers.ENEMY_HURTBOX)
	check(bare.head_sprite == null, "missing sheet: the placeholder head")
	bare.free()


func test_projectile_motion_is_unchanged_by_the_sprite() -> void:
	var a := Projectile.spawn(world, null, PISTOL.shot, Vector2(0, -300), Vector2.RIGHT, CombatLayers.ENEMY_HURTBOX)
	_break_sheet(&"projectiles")
	var b := Projectile.spawn(world, null, PISTOL.shot, Vector2(0, -200), Vector2.RIGHT, CombatLayers.ENEMY_HURTBOX)
	await physics_frames(5)
	check(is_instance_valid(a) and is_instance_valid(b) and is_equal_approx(a.position.x, b.position.x),
		"same travel with and without the head sprite")
	check(a._life == b._life, "same lifetime")


func test_reload_spawns_no_muzzle() -> void:
	player.combat.set_loadout(BLADE, PISTOL)
	var w := PISTOL
	player.combat.ammo[w.id] = w.ammo_max - 1
	player.combat.since_last_shot = w.reload_time
	player.combat._tick_reload(0.01)
	check(int(player.combat.ammo[w.id]) == w.ammo_max, "reloaded")
	check(_vfx(&"muzzle").is_empty() and _sparks().is_empty(), "a reload draws no muzzle flash")


# --- deaths, Pulse, heal, dodge -------------------------------------------------

func test_kill_motes_home_and_free_themselves() -> void:
	var dir := player.get_node("Feedback").get("director") as JuiceDirector
	check(dir != null, "PlayerFeedback made the JuiceDirector")
	var body := Node2D.new()
	body.position = Vector2(60, -10)
	world.add_child(body)
	dir._on_enemy_killed(body, null)
	var groups := _all(world, func(n: Node) -> bool: return n is PulseMotes)
	check(groups.size() == 1, "one mote stream")
	var pm := groups[0] as PulseMotes
	check(pm.motes.size() >= JuiceDirector.MOTES_MIN and pm.motes.size() <= JuiceDirector.MOTES_MAX, "4-8 motes (%d)" % pm.motes.size())
	check(_vfx(&"pulse_motes", &"mote").size() == pm.motes.size(), "each mote is a sprite")
	await physics_frames(24)
	var seam := player.global_position + PulseMotes.SEAM_OFFSET
	var near := 0
	for m in pm.motes:
		if (m["pos"] as Vector2).distance_to(seam) < (body.position - seam).length():
			near += 1
	check(near == pm.motes.size(), "motes close in on the seam")
	await physics_frames(13)
	check(not is_instance_valid(pm), "the stream frees itself within 0.6 s")
	check(_vfx(&"pulse_motes").is_empty(), "no mote left behind")


func test_motion_scales_motes_but_never_sparks() -> void:
	Settings.ambient_motion = Motion.OFF
	check(PulseMotes.scaled_count(8) == 2 and PulseMotes.scaled_count(16) == 4, "Off: a quarter of the motes")
	Settings.ambient_motion = Motion.REDUCED
	check(PulseMotes.scaled_count(8) == 4, "Reduced: half")
	Settings.ambient_motion = Motion.OFF
	check(HitSpark.play(world, Vector2.ZERO, Vector2.RIGHT, &"spark_small") is VfxOneShot, "sparks ignore Motion")
	check(DustBurst.puff(world, &"land", Vector2.ZERO) != null, "landing dust ignores Motion")


func test_mote_placeholder_without_the_sheet() -> void:
	_break_sheet(&"pulse_motes")
	var rng := RandomNumberGenerator.new()
	var pm := PulseMotes.spawn(world, Vector2(40, -20), player, 6, rng)
	check(pm != null and pm.motes.size() == 6, "the stream still runs")
	check(_vfx(&"pulse_motes").is_empty(), "drawn motes, no sprites")
	await physics_frames(36)
	check(not is_instance_valid(pm), "freed on time")


func test_heal_and_perfect_dodge() -> void:
	var dir := player.get_node("Feedback").get("director") as JuiceDirector
	EventBus.player_healed.emit(player.combat.health)
	check(_vfx(&"heal", &"heal_rise").size() == 1, "heal rise on player_healed")
	dir._on_perfect_dodge(null)
	check(_vfx(&"perfect_dodge", &"flourish").size() == 1, "perfect dodge flourish")
	_break_sheet(&"heal")
	_break_sheet(&"perfect_dodge")
	var before := _sparks().size()
	dir._on_player_healed(3)
	dir._on_perfect_dodge(null)
	check(_sparks().size() == before + 2, "missing sheets: the heal and dodge sparks")


func test_core_aura_only_in_flow_and_no_afterimages() -> void:
	await physics_frames(2)
	check(player.get_node_or_null("CoreAura") == null, "no aura outside Flow")
	player.reactor.enter_flow()
	await physics_frames(3)
	check(player.get_node_or_null("CoreAura") is CoreAura, "aura in Flow")
	check(float(player.visual.get("_seam_boost")) == 1.0, "aura boosts the visual's seam")
	await physics_frames(20)
	var ghosts: Array = player.visual.get("_ghosts")
	check(ghosts.is_empty(), "Flow alone makes no afterimages (they mean dodge/dash i-frames)")
	if player.visual.has_method(&"afterimages"):
		check((player.visual.call(&"afterimages") as Array).is_empty(), "no sprite afterimages")
	# T04's visual keeps a persistent "Afterimages" layer; only its children are afterimages.
	check(_all(world, func(n: Node) -> bool: return String(n.name).contains("Afterimage") and n.name != &"Afterimages").is_empty(), "no afterimage nodes")
	player.reactor.charge = 0.0
	await physics_frames(2)
	check((player.get_node("CoreAura") as CoreAura).critical(), "critical drip state")
	player.reactor.exit_flow()
	await physics_frames(3)
	check(player.get_node_or_null("CoreAura") == null, "aura gone after Flow")
	check(float(player.visual.get("_seam_boost")) == 0.0, "seam boost cleared after Flow")


# --- anchor, power flourishes, pickups, walls ----------------------------------

func test_anchor_rest_bloom_then_embers_until_rook_leaves() -> void:
	var anchor := Anchor.new()
	anchor.position = Vector2(0, 0)
	world.add_child(anchor)
	await physics_frames(2)
	anchor.rest_vfx(player)
	check(_vfx(&"anchor_rest", &"bloom").size() == 1, "bloom on rest")
	await physics_frames(60)
	check(is_instance_valid(anchor.rest_embers) and anchor.rest_embers.animation == &"embers", "embers loop after the bloom")
	await physics_frames(30)
	check(is_instance_valid(anchor.rest_embers), "embers keep looping while Rook rests")
	player.teleport(Vector2(80, -2))
	await physics_frames(3)
	check(anchor.rest_embers == null and _vfx(&"anchor_rest", &"embers").is_empty(), "embers freed once Rook leaves rest")
	_break_sheet(&"anchor_rest")
	var before := _sparks().size()
	anchor.rest_vfx(player)
	check(_sparks().size() == before + 1, "missing sheet: the old core sparks")


func test_power_flourish_kinds() -> void:
	var circuit := PowerFlourish.spawn(world, Vector2(0, -24), &"circuit", player)
	check(circuit != null and not circuit.placeholder, "circuit flourish")
	check(_vfx(&"shockwave", &"ring").size() == 1, "a ring")
	check(PowerFlourish.live_count(&"circuit") == 1, "live count")
	var weapon := PowerFlourish.spawn(world, Vector2(0, -16), &"weapon", player, {"weapon_id": "scattergun"})
	check(weapon.item != null and weapon.item.texture != null, "the weapon sprite rises")
	var ability := PowerFlourish.spawn(world, Vector2(0, -12), &"ability", player)
	await physics_frames(12)
	check(_vfx(&"shockwave", &"ring").size() >= 3, "ability: a second ring")
	check(PowerFlourish.spawn(world, Vector2.ZERO, &"no_such_power", player) == null, "unknown kinds are refused")
	await physics_frames(60)
	check(not is_instance_valid(circuit) and not is_instance_valid(weapon) and not is_instance_valid(ability), "flourishes free themselves")
	_break_sheet(&"shockwave")
	var before := _sparks().size()
	var old := PowerFlourish.spawn(world, Vector2.ZERO, &"ability", player)
	check(old.placeholder and _sparks().size() == before + 1, "missing sheet: the old ability sparks")


func test_grants_raise_flourishes() -> void:
	EventBus.circuit_granted.emit("test_circuit")
	EventBus.weapon_granted.emit("service_pistol")
	var kinds := _all(world, func(n: Node) -> bool: return n is PowerFlourish).map(func(n: Node) -> StringName: return (n as PowerFlourish).kind)
	check(kinds.has(&"circuit") and kinds.has(&"weapon"), "circuit and weapon flourishes (%s)" % [kinds])


func test_pickup_art_and_placeholder() -> void:
	for anim in [&"scrap_spin", &"scrap_cache", &"memory_shard", &"core_shard"]:
		check(ScrapPickup.has_art(anim), "pickup art for %s" % anim)
	check(not ScrapPickup.has_art(&"no_such_row"), "unknown row: placeholder")
	var pickup := ScrapPickup.new()
	pickup.position = Vector2(0, -400)
	world.add_child(pickup)
	var shard := Collectible.new()
	shard.kind = Collectible.Kind.CORE_SHARD
	check(shard.art() == [&"core_shard", Palette.color(&"accent")], "core shard: accent")
	shard.kind = Collectible.Kind.MEMORY_FRAGMENT
	check(shard.art()[1] == shard._color(), "memory shard keeps its own colour source")
	shard.free()
	await physics_frames(2)
	ScrapPickup.reset_art_cache("res://assets/props/test_missing_pickups.png", "res://assets/props/test_missing_pickups.png")
	check(not ScrapPickup.has_art(&"scrap_spin"), "missing sheets: placeholder")
	await physics_frames(2)
	check(is_instance_valid(pickup), "the placeholder draws without errors")


func test_breakable_wall_debris_and_placeholder() -> void:
	var wall := BreakableWall.new()
	wall.persist_id = "test_juice_wall"
	wall.position = Vector2(40, -48)
	world.add_child(wall)
	await physics_frames(1)
	wall._break_vfx(wall.global_position + wall.size * 0.5)
	check(_vfx(&"debris", &"concrete").size() >= 6, "concrete debris")
	await physics_frames(45)
	check(_vfx(&"debris").is_empty(), "debris frees itself")
	_break_sheet(&"debris")
	wall._break_vfx(wall.global_position + wall.size * 0.5)
	check(_sparks().size() == 3 and _dust_particles().size() == 1, "missing sheet: the old sparks + dust")


# --- contracts ------------------------------------------------------------------

func test_every_requested_animation_exists() -> void:
	var wanted := {
		&"hit_sparks": [&"spark_small", &"spark_heavy", &"spark_guard", &"spark_crit"],
		&"death_burst": [&"small", &"large"], &"death_burst_boss": [&"boss"],
		&"dust": [&"land", &"land_hard", &"run_puff", &"slide", &"dash_trail", &"wall_scrape"],
		&"splash": [&"step", &"land"], &"anchor_rest": [&"bloom", &"embers"], &"pulse_motes": [PulseMotes.ROW],
		&"perfect_dodge": [&"flourish"], &"heal": [&"heal_rise"], &"shockwave": [&"ring"], &"debris": [&"concrete"],
		&"muzzle": Projectile.MUZZLE_ROWS.values(),
		&"projectiles": Projectile.PLAYER_ROWS.values() + [&"enemy_bolt", &"collector_tag", &"ground_wave"],
		&"slash_smears": SlashArc.SMEAR_ROWS.values() + SlashArc.SMEAR_PREFIXES.values(),
	}
	for w in DustBurst.WATER_ROWS.values():
		if w != &"":
			(wanted[&"splash"] as Array).append(w)
	for id in wanted:
		var frames := VfxLibrary.frames(id)
		check(frames != null, "%s builds" % id)
		if frames == null:
			continue
		for anim in wanted[id]:
			check(frames.has_animation(anim), "%s has '%s'" % [id, anim])
	for row in HitSpark.FLASH_SAFE_ROWS.values():
		check(VfxLibrary.frames(&"hit_sparks").has_animation(row), "flash-safe row %s exists" % row)
	for kind in PowerFlourish.KINDS:
		check((PowerFlourish.KINDS[kind] as Dictionary).has_all(["rings", "motes", "item", "palette_key", "duration"]), "%s spec" % kind)


func test_shake_only_through_the_event_bus() -> void:
	for path in OWN_SOURCES:
		var src := FileAccess.get_file_as_string(path)
		check(not src.contains("Camera2D") and not src.contains("get_camera_2d"), "%s never touches the camera" % path)
	var dir := player.get_node("Feedback").get("director") as JuiceDirector
	var body := Node2D.new()
	world.add_child(body)
	dir._on_enemy_killed(body, null)
	dir._on_perfect_dodge(null)
	dir._on_player_healed(3)
	dir._on_circuit_granted("x")
	PowerFlourish.spawn(world, Vector2.ZERO, &"ability", player)
	HitSpark.play(world, Vector2.ZERO, Vector2.RIGHT, &"spark_crit")
	check(_shakes.is_empty(), "the juice itself requests no shake")


func test_no_spawned_node_has_collision() -> void:
	var dir := player.get_node("Feedback").get("director") as JuiceDirector
	var body := Node2D.new()
	world.add_child(body)
	dir._on_enemy_killed(body, null)
	dir._on_perfect_dodge(null)
	dir._on_player_healed(3)
	PowerFlourish.spawn(world, Vector2.ZERO, &"weapon", player, {"weapon_id": "service_pistol"})
	HitSpark.play(world, Vector2.ZERO, Vector2.RIGHT, &"spark_small")
	DustBurst.puff(world, &"land_hard", Vector2.ZERO)
	var rng := RandomNumberGenerator.new()
	DustBurst.debris(world, Rect2(0, -40, 16, 40), &"concrete", 6, rng)
	player.reactor.enter_flow()
	await physics_frames(2)
	var fx := _all(world, func(n: Node) -> bool:
		return n is VfxOneShot or n is PulseMotes or n is PowerFlourish or n is CoreAura)
	check(fx.size() >= 8, "effects spawned (%d)" % fx.size())
	for n in fx:
		check(_all(n, func(c: Node) -> bool: return c is CollisionObject2D or c is CollisionShape2D).is_empty()
			and not (n is CollisionObject2D), "%s has no collision" % n.name)
	player.reactor.exit_flow()
