extends RedlineTestCase
## Presentation overhaul T01: the shared runtime API later tasks code against
## (SpriteActor, VfxLibrary / VfxOneShot, Motion, PresentationIndex, the
## NpcProfile art fields, the ambient motion and ambience volume settings)
## and the phase-A assets it rests on.

const ROOK_SPEC := "res://assets/rook/rook_sheet.tres"
const DUST_SPEC := "res://assets/vfx/dust.tres"
const PHASE_A_VFX: Array[StringName] = [&"slash_smears", &"hit_sparks", &"death_burst", &"death_burst_boss", &"dust",
	&"splash", &"pulse_motes", &"projectiles", &"muzzle", &"heal", &"anchor_rest", &"perfect_dodge", &"shockwave",
	&"electric_arc", &"steam", &"debris", &"ambient_particles"]
const SETTINGS_PATH := "user://test_overhaul_settings.cfg"

var _snap: Dictionary = {}


func before_each() -> void:
	_snap = snapshot_settings()


func after_each() -> void:
	restore_settings(_snap)
	Palette.invalidate()
	for c in get_children():
		c.free()
	await physics_frames(1)


# --- assets -----------------------------------------------------------------

func test_every_asset_spec_validates_and_builds() -> void:
	var n := 0
	for path in ContentValidator._files("res://assets", ["tres"]):
		var res := load(path)
		if not (res is SpriteSheetSpec):
			continue
		n += 1
		var spec := res as SpriteSheetSpec
		check(spec.validate().is_empty(), "%s: %s" % [path, spec.validate()])
		var frames := spec.build_frames()
		check(frames != null and frames.get_animation_names().size() == spec.animations.size(), "%s builds no frames" % path)
	check(n >= 35, "phase-A sheets present (%d specs)" % n)


# --- VFX library ------------------------------------------------------------

func test_vfx_library_resolves_every_id() -> void:
	var lib := VfxLibrary.get_library()
	check(lib.validate().is_empty(), "vfx_library.tres: %s" % lib.validate())
	for id in PHASE_A_VFX:
		check(VfxLibrary.ids().has(id), "library has %s" % id)
		check(VfxLibrary.spec(id) != null, "%s spec loads" % id)
		check(VfxLibrary.frames(id) != null, "%s builds frames" % id)
	for id in VfxLibrary.ids():
		check(str(VfxLibrary.entry(id)["spec"]) == "res://assets/vfx/%s.tres" % id, "%s spec path follows the id" % id)


func test_vfx_default_palette_keys_resolve_in_every_palette() -> void:
	var keys := 0
	for id in VfxLibrary.ids():
		var key := StringName(VfxLibrary.entry(id).get("palette_key", &""))
		if key == &"":
			continue
		keys += 1
		for p in Palette.all():
			check(p.resolve(key) != Color.MAGENTA, "%s: '%s' resolves in palette %s" % [id, key, p.id])
	check(keys >= 3, "some effects follow the palette (%d)" % keys)


func test_spawn_returns_null_for_missing_things() -> void:
	check(VfxOneShot.spawn(self, &"no_such_vfx", &"land", Vector2.ZERO) == null, "unknown id")
	check(VfxOneShot.spawn(self, &"dust", &"no_such_anim", Vector2.ZERO) == null, "unknown animation")
	var lib := VfxLibrary.get_library()
	lib.entries[&"test_missing_sheet"] = {"spec": "res://assets/vfx/test_missing_sheet.tres", "palette_key": &"",
		"color": Color.WHITE, "additive": false, "cap": 4}
	check(VfxOneShot.spawn(self, &"test_missing_sheet", &"land", Vector2.ZERO) == null, "missing sheet keeps the placeholder")
	lib.entries.erase(&"test_missing_sheet")
	VfxLibrary.clear_cache()
	var bad := SpriteSheetSpec.new()
	bad.texture_path = "res://assets/vfx/test_missing_sheet.png"
	check(SpriteActor.create(bad) == null, "SpriteActor.create returns null without a texture")
	check(get_child_count() == 0, "nothing was added")


func test_one_shot_frees_itself() -> void:
	var fx := VfxOneShot.spawn(self, &"hit_sparks", &"spark_small", Vector2(40, 40))
	check(fx != null and is_instance_valid(fx), "spark spawned")
	check(VfxOneShot.live_count(&"hit_sparks") >= 1, "live count")
	await physics_frames(30)
	check(not is_instance_valid(fx), "a one-shot frees itself after its animation")
	check(VfxOneShot.live_count(&"hit_sparks") == 0, "live count drops")


func test_hold_last_waits_for_stop() -> void:
	var fx := VfxOneShot.spawn(self, &"hit_sparks", &"spark_small", Vector2.ZERO, {"hold_last": true})
	await physics_frames(30)
	check(is_instance_valid(fx), "hold_last keeps the last frame")
	if is_instance_valid(fx):
		check(fx.frame == fx.sprite.sprite_frames.get_frame_count(&"spark_small") - 1, "on the last frame")
		fx.stop()
	await physics_frames(1)
	check(not is_instance_valid(fx), "stop() frees it")


func test_looping_effects_never_leak() -> void:
	var timed := VfxOneShot.spawn(self, &"ambient_particles", &"mote", Vector2.ZERO, {"lifetime": 0.2})
	var stopped := VfxOneShot.spawn(self, &"ambient_particles", &"spore", Vector2.ZERO)
	var owner_node := Node2D.new()
	owner_node.position = Vector2(100, 50)
	add_child(owner_node)
	var aura := VfxOneShot.spawn(self, &"ambient_particles", &"ash", Vector2(110, 40), {"follow": owner_node})
	check(timed != null and stopped != null and aura != null, "loops spawned")
	check(EventBus.room_leaving.is_connected(stopped._on_room_leaving), "a loop frees on room_leaving")
	await physics_frames(20)
	check(not is_instance_valid(timed), "a loop with lifetime frees after it")
	check(is_instance_valid(stopped), "a loop without lifetime keeps playing")
	owner_node.position = Vector2(200, 80)
	await physics_frames(1)
	check(is_instance_valid(aura) and aura.global_position.is_equal_approx(Vector2(210, 70)), "follow keeps the offset")
	stopped.stop()
	owner_node.queue_free()
	await physics_frames(2)
	check(not is_instance_valid(stopped), "stop() frees a loop")
	check(not is_instance_valid(aura), "a loop frees when its follow target goes")


func test_cap_limits_live_instances() -> void:
	var first := VfxOneShot.spawn(self, &"death_burst_boss", &"boss", Vector2.ZERO)
	check(first != null, "first boss burst")
	check(VfxOneShot.spawn(self, &"death_burst_boss", &"boss", Vector2.ZERO) == null, "cap 1: the second returns null")
	first.free()
	check(VfxOneShot.spawn(self, &"death_burst_boss", &"boss", Vector2.ZERO) != null, "freed slot is reusable")


func test_direction_snaps_to_quarter_turns() -> void:
	var dirs := [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(1, 1), Vector2(-1, 0.9),
		Vector2(0.3, -1), Vector2(-0.7, -0.71), Vector2(1, -0.2)]
	for d: Vector2 in dirs:
		var fx := VfxOneShot.spawn(self, &"hit_sparks", &"spark_heavy", Vector2.ZERO, {"direction": d})
		var deg := posmod(roundi(fx.rotation_degrees), 360)
		check([0, 90, 180, 270].has(deg) and is_equal_approx(fx.rotation_degrees, float(roundi(fx.rotation_degrees))),
			"%s -> rotation %.2f" % [d, fx.rotation_degrees])
		fx.free()
	var left := VfxOneShot.spawn(self, &"hit_sparks", &"spark_heavy", Vector2.ZERO, {"direction": Vector2.LEFT})
	check(left.flip_h and is_zero_approx(left.rotation), "left is a flip, not a half turn")
	left.free()
	var down := VfxOneShot.spawn(self, &"hit_sparks", &"spark_heavy", Vector2.ZERO, {"direction": Vector2.DOWN})
	check(is_equal_approx(down.rotation_degrees, 90.0), "down is a quarter turn")
	down.free()


func test_tint_and_flash_reduction() -> void:
	Settings.flash_reduction = false
	var plain := VfxOneShot.spawn(self, &"hit_sparks", &"spark_small", Vector2.ZERO, {"tint": Color.WHITE})
	check(plain.modulate.is_equal_approx(Color.WHITE), "tint applied")
	var unknown := VfxOneShot.spawn(self, &"hit_sparks", &"spark_small", Vector2.ZERO,
		{"tint": Color(0.2, 0.4, 0.6), "palette_key": &"not_a_key"})
	check(unknown.modulate.is_equal_approx(Color(0.2, 0.4, 0.6)), "an unknown palette key falls back to the tint")
	var keyed := VfxOneShot.spawn(self, &"hit_sparks", &"spark_small", Vector2.ZERO, {"palette_key": &"info"})
	check(keyed.modulate.is_equal_approx(Palette.color(&"info")), "palette key applied")
	var heal := VfxOneShot.spawn(self, &"heal", &"heal_rise", Vector2.ZERO)
	check(heal.modulate.is_equal_approx(Palette.color(&"heal")), "library default palette key")
	Settings.flash_reduction = true
	var soft := VfxOneShot.spawn(self, &"hit_sparks", &"spark_small", Vector2.ZERO, {"tint": Color.WHITE})
	check_near(soft.modulate.r, 0.7, 0.001, "flash reduction scales the value to 0.7")
	check_near(soft.modulate.a, 1.0, 0.001, "alpha untouched")
	Settings.flash_reduction = false


func test_off_centre_origin_is_flip_safe() -> void:
	var spec := load(DUST_SPEC) as SpriteSheetSpec
	check(spec.origin_for(&"wall_scrape") == Vector2i(17, 16), "wall_scrape overrides the origin")
	check(spec.origin_for(&"land") == spec.origin, "land keeps the sheet origin")
	var cell := spec.cell_size.x
	var o := spec.origin_for(&"wall_scrape").x
	for flipped in [false, true]:
		var off := spec.offset_for(&"wall_scrape", flipped)
		var left := off.x - cell * 0.5
		# the origin column after the mirror sits at cell - 1 - o
		var col := (cell - 1 - o) if flipped else o
		var span_left := left + col
		if flipped:
			check(is_equal_approx(span_left + 1.0, 0.0), "flipped: the origin pixel ends on the node (%.1f)" % span_left)
		else:
			check(is_equal_approx(span_left, 0.0), "unflipped: the origin pixel starts on the node (%.1f)" % span_left)
	var fx := VfxOneShot.spawn(self, &"dust", &"wall_scrape", Vector2.ZERO, {"facing": -1})
	check(fx.offset.is_equal_approx(spec.offset_for(&"wall_scrape", true)), "VfxOneShot applies the flipped offset")
	fx.free()


func test_sprite_actor_origin_override_and_one_shots() -> void:
	var actor := SpriteActor.create(load(DUST_SPEC))
	add_child(actor)
	actor.play(&"land")
	check(actor.offset.is_equal_approx(Vector2(0, -15)), "sheet origin (16, 31): offset %s" % actor.offset)
	actor.play(&"wall_scrape")
	check(actor.offset.is_equal_approx(Vector2(-1, 0)), "per-anim origin (17, 16): offset %s" % actor.offset)
	actor.face(-1)
	check(actor.offset.is_equal_approx(Vector2(1, 0)), "flipped offset %s" % actor.offset)
	var ended: Array = []
	actor.one_shot_finished.connect(func(a: StringName) -> void: ended.append(a))
	actor.play(&"land")
	await physics_frames(3)
	check(actor.play_once_first([&"nope", &"land"]) == &"land", "first existing anim")
	check(actor.frame == 0 and actor.is_playing_one_shot(), "restarted from frame 0")
	await physics_frames(30)
	check(ended == [&"land"], "one_shot_finished once: %s" % str(ended))
	check(not actor.is_playing_one_shot(), "one-shot over")
	check(actor.play_once_first([&"nope"]) == &"", "nothing to play")


func test_sprite_actor_mask_overlay() -> void:
	var spec := load(ROOK_SPEC) as SpriteSheetSpec
	check(spec.load_mask_texture() != null, "rook has a tint mask")
	var actor := SpriteActor.create(spec)
	add_child(actor)
	check(actor.mask != null and actor.mask.get_parent() == actor, "mask overlay built")
	actor.play(&"run")
	actor.frame = 3
	actor.face(-1)
	check(actor.mask.animation == &"run" and actor.mask.frame == 3, "mask follows animation and frame")
	check(actor.mask.flip_h and actor.mask.offset.is_equal_approx(actor.offset), "mask follows flip and offset")
	actor.self_modulate = Color(1, 1, 1, 0.3)
	await physics_frames(1)
	check_near(actor.mask.self_modulate.a, 0.3, 0.001, "mask copies the hurt-blink alpha")
	Settings.colorblind_mode = 0
	EventBus.settings_changed.emit()
	var default_tint := actor.mask.modulate
	check(default_tint.is_equal_approx(Palette.palette(0).resolve(&"accent")), "mask uses the accent colour")
	Settings.colorblind_mode = 1
	EventBus.settings_changed.emit()
	check(actor.mask.modulate.is_equal_approx(Palette.palette(1).resolve(&"accent")), "colour-blind mode re-tints the mask")
	check(not actor.mask.modulate.is_equal_approx(default_tint), "the tint changed")
	var plain := SpriteActor.create(load(DUST_SPEC))
	check(plain.mask == null, "no mask without mask_path")
	plain.free()


# --- Motion and settings ------------------------------------------------------

func test_ambient_motion_setting() -> void:
	var visual := Settings.settings_catalog().page(&"visual")
	check(Settings.settings_catalog().page_keys(visual).has(&"ambient_motion"), "ambient motion row on the Visual page")
	var audio := Settings.settings_catalog().page(&"audio")
	check(Settings.settings_catalog().page_keys(audio).has(&"ambience_volume"), "ambience volume row on the Audio page")
	check(Settings.defaults()["ambient_motion"] == 0 and is_equal_approx(Settings.defaults()["ambience_volume"], 0.8), "defaults")
	for lv in 3:
		Settings.ambient_motion = lv
		check(Motion.level() == lv, "level %d" % lv)
		check_near(Motion.count_scale(), [1.0, 0.5, 0.0][lv], 0.0001, "count scale at %d" % lv)
		check(Motion.animate_ambient() == (lv != 2), "animate_ambient at %d" % lv)
		check(Motion.cloth() == (lv == 0), "cloth at %d" % lv)
	Settings.ambient_motion = 9
	check(Settings.ambient_motion == 2, "clamped")
	Settings.load_settings(SETTINGS_PATH)
	Settings.ambient_motion = 1
	Settings.ambience_volume = 0.3
	check(Settings.save_settings() == OK, "save")
	Settings.ambient_motion = 0
	Settings.ambience_volume = 0.8
	Settings.load_settings(SETTINGS_PATH)
	check(Settings.ambient_motion == 1, "ambient_motion restored")
	check_near(Settings.ambience_volume, 0.3, 0.0001, "ambience_volume restored")
	Settings.reset_keys([&"ambient_motion", &"ambience_volume"])
	check(Settings.ambient_motion == 0 and is_equal_approx(Settings.ambience_volume, 0.8), "reset to defaults")
	check(Settings.reset_all_keys().has(&"ambient_motion") and Settings.reset_all_keys().has(&"ambience_volume"), "reset all covers both")
	Settings.remove_settings_files(SETTINGS_PATH)


func test_motion_defaults_without_settings() -> void:
	Settings.ambient_motion = 2
	var s := get_tree().root.get_node("Settings")
	s.name = "SettingsAway"
	var lv := Motion.level()
	var sc := Motion.count_scale()
	var anim := Motion.animate_ambient()
	s.name = "Settings"
	check(lv == Motion.FULL and is_equal_approx(sc, 1.0) and anim, "no Settings node: Full defaults (%d, %.2f)" % [lv, sc])
	check(Motion.level() == 2, "back to the setting")


# --- presentation map ---------------------------------------------------------

func test_every_world_room_has_a_presentation() -> void:
	check(PresentationIndex.get_index().validate().is_empty(), "rooms.tres: %s" % PresentationIndex.get_index().validate())
	var n := 0
	for dir in ["res://world/rooms/undercity", "res://world/rooms/lowlight", "res://world/rooms/challenge"]:
		for path in DataDir.list_scenes(dir):
			n += 1
			var p := PresentationIndex.for_room(path)
			check(p != null, "%s has an entry or a district default" % path)
			if p:
				check(p.ambience == &"" or PresentationIndex.BED_IDS.has(p.ambience), "%s bed %s" % [path, p.ambience])
				check(p.ambience_layer == &"" or PresentationIndex.BED_IDS.has(p.ambience_layer), "%s layer" % path)
				check(PresentationIndex.BACKDROP_KINDS.has(p.backdrop_kind), "%s kind %s" % [path, p.backdrop_kind])
	check(n == 22, "22 world rooms (%d)" % n)
	for lab in ["res://world/rooms/CombatLab.tscn", "res://world/rooms/MovementLab.tscn"]:
		check(PresentationIndex.for_room(lab) == null, "%s stays graybox" % lab)
	check(PresentationIndex.for_room("res://world/rooms/TitleBackdrop.tscn").backdrop_kind == &"title", "title backdrop")
	check(PresentationIndex.for_room("res://world/rooms/undercity/FirstPursuit.tscn").ambience == &"amb_undercity_ward", "shaft bed falls back to ward")
	check(PresentationIndex.for_room("res://world/rooms/lowlight/NeonRoofs.tscn").reverb == &"roof", "roof reverb")
	var fallback := PresentationIndex.for_room("res://world/rooms/lowlight/NotARoom.tscn", "Lowlight")
	check(fallback != null and fallback.backdrop_kind == &"ll_street", "district default by name")
	check(PresentationIndex.district_of("res://world/rooms/lowlight/Relay.tscn") == "The Relay", "district read from the scene")


# --- NPC art ----------------------------------------------------------------

func test_npc_profiles_carry_art() -> void:
	var orr := NpcProfile.find_by_display_name("Orr")
	check(orr != null and orr.npc_id == "orr", "Orr by display name")
	check(orr != null and orr.portrait != null and orr.sprite != null and orr.signature_anim == &"tune_radio", "Orr's art")
	check(NpcProfile.find_by_display_name("Nobody") == null, "unknown name")
	for id in ["orr", "mara", "nix", "vell", "iko"]:
		var p := load("res://data/npcs/%s.tres" % id) as NpcProfile
		check(p.sprite != null and p.portrait != null and p.signature_anim != &"", "%s has art" % id)
		check(p.validate().is_empty(), "%s: %s" % [id, p.validate()])
	var radio := load("res://data/npcs/orr_radio.tres") as NpcProfile
	check(radio.sprite == null and radio.portrait == null, "bodiless voices stay without art")
