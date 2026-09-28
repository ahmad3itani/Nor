extends RedlineTestCase
## Presentation overhaul T03: the painted backdrop runtime (BackdropSet /
## PlaneSpec per kind, ParallaxPlane, FogBand, LightShaft, AmbientParticles,
## AmbientLife, LampGlow, SwayCable, ClothStrip, Vignette, the foreground
## layer, GrayboxBlock tiles and the title scene). Everything is visual only
## and falls back to the procedural placeholders.

const PARTICLES_SPEC := "res://assets/vfx/ambient_particles.tres"
const TITLE_SCENE := "res://world/rooms/TitleBackdrop.tscn"
const WARD_ROOM := "res://world/rooms/undercity/MedicalRuin.tscn"
const STREET_ROOM := "res://world/rooms/lowlight/MarketRun.tscn"
const PURSUIT_ROOM := "res://world/rooms/undercity/FirstPursuit.tscn"
const VIEW := Vector2(480, 270)

var _snap: Dictionary = {}


func before_each() -> void:
	_snap = snapshot_settings()
	Settings.ambient_motion = Motion.FULL
	Settings.background_dim = 0
	Settings.high_contrast = false
	Settings.flash_reduction = false


func after_each() -> void:
	restore_settings(_snap)
	for c in get_children():
		c.free()
	await physics_frames(1)


# --- helpers -----------------------------------------------------------------

## A room scene as a lab room (world_room off: no Game.state writes).
func _room(path: String) -> Room:
	var room := (load(path) as PackedScene).instantiate() as Room
	room.world_room = false
	add_child(room)
	return room


func _backdrop_of(room: Node) -> DistrictBackdrop:
	for c in room.get_children():
		if c is DistrictBackdrop:
			return c
	return null


func _bare_backdrop(kind: StringName, theme_path: String = "res://data/districts/undercity.tres") -> DistrictBackdrop:
	var cam := Camera2D.new()
	add_child(cam)
	var b := DistrictBackdrop.new()
	b.backdrop_kind = kind
	b.ref_camera_y = 0.0
	b.setup(load(theme_path) as DistrictTheme, cam)
	add_child(b)
	return b


static func _abs_z(n: CanvasItem) -> int:
	var z := 0
	var c: Node = n
	while c is CanvasItem:
		var ci := c as CanvasItem
		z += ci.z_index
		if not ci.z_as_relative:
			break
		c = c.get_parent()
	return z


func _all(root: Node) -> Array[Node]:
	var out: Array[Node] = [root]
	for c in root.get_children():
		out.append_array(_all(c))
	return out


# --- data ----------------------------------------------------------------------

func test_every_kind_has_a_set_with_existing_textures() -> void:
	var spec := load(PARTICLES_SPEC) as SpriteSheetSpec
	var rows: Array[StringName] = []
	for a in spec.animations:
		rows.append(a.name)
	for kind in PresentationIndex.BACKDROP_KINDS:
		var s := BackdropSet.for_kind(kind)
		check(s != null, "%s has a BackdropSet" % kind)
		if s == null:
			continue
		check(s.validate().is_empty(), "%s validates: %s" % [kind, s.validate()])
		check(not s.background_planes().is_empty(), "%s has painted planes" % kind)
		for p in s.planes:
			for path in p.paths():
				check(ResourceLoader.exists(path), "%s: %s exists" % [kind, path])
		if s.particle_row() != &"":
			check(rows.has(s.particle_row()), "%s particle '%s' is a row of the ambient_particles spec" % [kind, s.ambient_particle])
	var dust := BackdropSet.new()
	dust.ambient_particle = &"dust"
	check(dust.particle_row() == &"mote", "dust reads as mote")


func test_translucent_layers_and_opaque_flags() -> void:
	for kind in PresentationIndex.BACKDROP_KINDS:
		var s := BackdropSet.for_kind(kind)
		var translucent := 1 if s.vignette_alpha > 0.0 else 0
		for p in s.background_planes():
			var img := Image.load_from_file(ProjectSettings.globalize_path(p.texture_path))
			var full := p.tile_y or img.get_height() >= int(VIEW.y)
			var opaque := img.detect_alpha() == Image.ALPHA_NONE
			if p.opaque:
				check(opaque and full, "%s: %s flagged opaque is opaque and full-screen" % [kind, p.texture_path.get_file()])
			elif full:
				translucent += 1
		check(translucent <= 3, "%s: %d translucent full-screen layers (<= 3)" % [kind, translucent])


func test_tileset_layout_matches_the_atlas() -> void:
	for d in ["undercity", "lowlight", "relay", "null"]:
		var theme := load("res://data/districts/%s.tres" % d) as DistrictTheme
		check(ResourceLoader.exists(theme.tileset_path), "%s tileset exists" % d)
		var tex := load(theme.tileset_path) as Texture2D
		check(tex.get_size() == Vector2(128, 96), "%s tileset is the 8x6 atlas" % d)
		var layout := UiKit.read_json(theme.tileset_layout_path)
		var names: Array = layout.get("names", [])
		check(names.size() == GrayboxBlock.TILE_NAMES.size(), "%s layout size" % d)
		for i in mini(names.size(), GrayboxBlock.TILE_NAMES.size()):
			check(StringName(names[i]) == GrayboxBlock.TILE_NAMES[i], "%s tile %d is %s" % [d, i, names[i]])
		check(theme.backdrop_kind_default != &"" and BackdropSet.for_kind(theme.backdrop_kind_default) != null, "%s default kind" % d)
	var relay := load("res://data/districts/relay.tres") as DistrictTheme
	for c in relay.window_colors:
		check(c.r > c.g and c.g > c.b and not c.is_equal_approx(Color("ffcf5a")), "Relay windows use the lamp_core family (%s)" % c)


# --- fallback and dim -------------------------------------------------------

func test_missing_set_or_texture_draws_the_procedural_skyline() -> void:
	var none := _bare_backdrop(&"no_such_kind")
	check(none.backdrop_set == null and none.procedural_skyline(), "no set: procedural skyline")
	check(none.sky_layer() != null and none.sky_layer().visible, "no set: the sky layer stays")
	check(none.sky_layer().modulate == DistrictBackdrop.dim_modulate(0), "no set: dim unchanged")
	check(none.grade_root().modulate == Color.WHITE, "no set: no grade")
	var broken := BackdropSet.new()
	var p := PlaneSpec.new()
	p.texture_path = "res://assets/undercity/test_missing_plane.png"
	broken.planes = [p]
	broken.grade = Color("dfeee8")
	var cam := Camera2D.new()
	add_child(cam)
	var b := DistrictBackdrop.new()
	b.backdrop_set = broken
	b.setup(load("res://data/districts/undercity.tres") as DistrictTheme, cam)
	add_child(b)
	check(b.planes().is_empty() and b.procedural_skyline(), "a missing texture falls back to the skyline")
	check(b.sky_layer().visible, "the procedural sky shows")


func test_apply_dim_reaches_every_plane_and_grade_stays_off_the_sky() -> void:
	var b := _bare_backdrop(&"uc_pursuit")
	check(not b.planes().is_empty() and not b.procedural_skyline(), "painted planes load")
	check(b.grade_root().modulate == b.backdrop_set.grade, "the grade sits on the backdrop's grade root")
	check(b.sky_layer().modulate == DistrictBackdrop.dim_modulate(0), "sky modulate is the dim, not the grade")
	Settings.background_dim = 2
	EventBus.settings_changed.emit()
	var dim := DistrictBackdrop.dim_modulate(2)
	check(dim != Color.WHITE, "Strong dims")
	check(b.sky_layer().modulate == dim, "sky gets exactly the dim")
	var n := 0
	for node in b.dimmed_nodes():
		n += 1
		check(node.modulate == dim, "%s dimmed" % node.name)
	check(n >= b.planes().size() + b.fogs().size(), "every plane and fog is dimmed (%d)" % n)
	Settings.high_contrast = true
	Settings.background_dim = 0
	EventBus.settings_changed.emit()
	check(b.sky_layer().modulate == Color.WHITE, "high contrast forces no dim")
	for node in b.dimmed_nodes():
		check(node.modulate == Color.WHITE, "%s undimmed" % node.name)


func test_plane_offsets_are_not_rounded() -> void:
	var b := _bare_backdrop(&"ll_street", "res://data/districts/lowlight.tres")
	var mid: ParallaxPlane = null
	for p in b.planes():
		if is_equal_approx(p.motion.x, 0.3):
			mid = p
	check(mid != null, "a mid plane")
	mid.follow(Vector2(100.5, -10.25), 0.0)
	var want := -fposmod(100.5 * 0.3, mid.cycle())
	check(is_equal_approx(mid.position.x, want), "x follows the camera unrounded (%f vs %f)" % [mid.position.x, want])
	check(not is_equal_approx(mid.position.x, roundf(mid.position.x)), "fractional camera x -> fractional plane x")
	check(is_equal_approx(mid.cycle(), 960.0), "A/B planes repeat every 960 px (480 each)")
	var y0 := mid.position.y
	mid.follow(Vector2(100.5, -110.25), 0.0)
	check(is_equal_approx(mid.position.y - y0, 100.0 * 0.07), "y moves at the plane's motion")


func test_occluded_planes_are_hidden() -> void:
	var b := _bare_backdrop(&"uc_ward")
	var cover := b.planes()[b.planes().size() - 1]
	check(cover.covers_view(), "the ward backwall covers the view")
	check(not b.sky_layer().visible, "the procedural sky behind it is hidden")
	var b2 := _bare_backdrop(&"ll_street", "res://data/districts/lowlight.tres")
	check(not b2.sky_layer().visible, "an opaque painted sky hides the procedural one")
	var visible_planes := b2.planes().filter(func(p: ParallaxPlane) -> bool: return p.visible)
	check(visible_planes.size() == b2.planes().size(), "planes in front of the sky stay visible")


# --- vignette ------------------------------------------------------------------

func test_vignette_is_under_the_world_and_off_in_high_contrast() -> void:
	var b := _bare_backdrop(&"uc_pursuit")
	var v := b.vignette()
	check(v != null, "vignette present")
	check(b.get_child(b.get_child_count() - 1) == v, "vignette is the top child of the backdrop layer")
	check(b.layer < 0, "on the backdrop layer (%d)" % b.layer)
	check(v.visible, "visible by default")
	for n in _all(b):
		if n is CanvasLayer and (n as CanvasLayer).layer >= 0:
			for m in _all(n):
				check(not (m is Sprite2D and (m as Sprite2D).texture == v.texture), "no layer >= 0 carries the vignette")
	Settings.high_contrast = true
	EventBus.settings_changed.emit()
	check(not v.visible, "high contrast hides the vignette")


# --- rooms ----------------------------------------------------------------------

func test_room_grade_stays_on_the_backdrop() -> void:
	var room := _room(WARD_ROOM)
	await physics_frames(3)
	var b := _backdrop_of(room)
	check(b != null and b.backdrop_kind == &"uc_ward", "MedicalRuin uses uc_ward")
	check(b.grade_root().modulate == b.backdrop_set.grade and b.backdrop_set.grade != Color.WHITE, "grade on the backdrop")
	check(room.modulate == Color.WHITE and room.self_modulate == Color.WHITE, "room root not graded")
	check(room.player.modulate == Color.WHITE, "player not graded")
	check(b.grade_root().get_parent() == b, "the grade root lives on the backdrop layer")


func test_room_nodes_are_visual_only_and_unowned() -> void:
	var room := _room(STREET_ROOM)
	await physics_frames(3)
	var b := _backdrop_of(room)
	var life := b.life()
	check(life != null and life.is_inside_tree(), "street life spawned into the room")
	var extra: Array[Node] = []
	for n in [b, life]:
		extra.append_array(_all(n))
	for d in room.find_children("*", "Decor", true, false) + room.find_children("*", "NeonSign", true, false):
		for c in d.get_children():
			extra.append_array(_all(c))
	check(extra.size() > 10, "runtime dressing present (%d nodes)" % extra.size())
	for n in extra:
		check(not (n is CollisionObject2D) and not (n is Area2D), "%s has no collision" % n.name)
		check(not n.is_in_group(&"enemies") and not n.is_in_group(&"enemy_spawners"), "%s joins no gameplay group" % n.name)
		check(n.owner == null, "%s is unowned" % n.name)
	# Packing the live room keeps exactly the scene's nodes (tool-mode safety:
	# nothing created at runtime is owned, so an editor save writes nothing new).
	var packed := PackedScene.new()
	packed.pack(room)
	var original := load(STREET_ROOM) as PackedScene
	check(packed.get_state().get_node_count() == original.get_state().get_node_count(),
		"no extra owned nodes (%d vs %d)" % [packed.get_state().get_node_count(), original.get_state().get_node_count()])


func test_graybox_collision_unchanged_with_tiles() -> void:
	var room := _room(WARD_ROOM)
	await physics_frames(1)
	var n := 0
	for g in room.find_children("*", "GrayboxBlock", true, false):
		var b := g as GrayboxBlock
		n += 1
		check(b.tileset() != null, "%s draws the district tiles" % b.name)
		var cs: CollisionShape2D = null
		for c in b.get_children():
			if c is CollisionShape2D:
				cs = c
		check(cs != null and (cs.shape as RectangleShape2D).size == b.size and cs.position == b.size * 0.5, "%s shape follows size" % b.name)
		check(cs.one_way_collision == b.one_way and b.collision_layer == (4 if b.one_way else 1), "%s layers unchanged" % b.name)
		check(b.get_child_count() == 1, "%s gains no child" % b.name)
	check(n > 5, "blocks checked (%d)" % n)
	var names := {}
	for rows in [1, 2, 4]:
		for cols in [1, 2, 5]:
			for cy in rows:
				for cx in cols:
					names[GrayboxBlock.tile_for(cx, cy, cols, rows, false, Vector2i(cx, cy))] = true
	for k in names:
		check(GrayboxBlock.TILE_NAMES.has(k), "tile %s is in the layout" % k)
	check(GrayboxBlock.tile_for(0, 0, 3, 1, true, Vector2i.ZERO) == &"oneway_L", "one-way row")


func test_glows_sit_below_characters() -> void:
	var room := _room(STREET_ROOM)
	await physics_frames(2)
	var glows := get_tree().get_nodes_in_group(LampGlow.GROUP).filter(func(g: Node) -> bool: return room.is_ancestor_of(g))
	check(glows.size() >= 4, "the street's lamps and signs glow (%d)" % glows.size())
	var pz := _abs_z(room.player)
	for g in glows:
		check(_abs_z(g) < pz, "glow z %d below the player %d" % [_abs_z(g), pz])
		check((g as CanvasItem).material == LampGlow.material_shared(), "one shared additive material")
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if room.is_ancestor_of(e):
			for g in glows:
				check(_abs_z(g) < _abs_z(e), "glow below enemy %s" % e.name)
	var life := _backdrop_of(room).life()
	for s in life.critter_sprites():
		check(_abs_z(s) < pz, "critter behind the player")


func test_signs_glow_by_colour_and_broken_half() -> void:
	var host := Node2D.new()
	add_child(host)
	var sign := NeonSign.new()
	sign.size = Vector2(8, 24)
	sign.color = Color("58e0e8")
	sign.broken = true
	host.add_child(sign)
	var red := NeonSign.new()
	red.color = Color("e8283c")
	host.add_child(red)
	var green := NeonSign.new()
	green.color = Color("7dff9a")
	host.add_child(green)
	await physics_frames(2)
	var g := sign.lamp_glow()
	check(g != null, "a cyan sign glows")
	check(red.lamp_glow() == null, "danger-red signs get no glow")
	check(green.lamp_glow() != null and not LampGlow.near_any(green.lamp_glow().tint, LampGlow.RESERVED), "heal-green glows desaturated")
	check(not LampGlow.near_any(g.tint, LampGlow.RESERVED), "cyan near guard blue glows desaturated (%s)" % g.tint.to_html())
	check(g.position.y < 0.0, "the broken sign glows only its lit (upper) half")
	check(g.glow_rect().size.x <= sign.size.y * 0.5 + LampGlow.TUBE_CAP * 2 + 0.5, "half-length tube (%s)" % g.glow_rect())
	var saw_off := false
	var saw_on := false
	for i in 120:
		await get_tree().process_frame
		if sign.is_lit():
			saw_on = saw_on or g.level > 0.0
		else:
			saw_off = saw_off or is_zero_approx(g.level)
	check(saw_on and saw_off, "the glow follows the stutter")


func test_ambient_caps_follow_the_motion_level() -> void:
	var room := _room(STREET_ROOM)
	await physics_frames(3)
	var b := _backdrop_of(room)
	var life := b.life()
	check(life.count(&"moth") > 0 and life.count(&"moth") <= AmbientLife.CAPS[&"moth"], "moths capped (%d)" % life.count(&"moth"))
	check(life.count(&"rat") <= 2, "rats capped")
	check(b.particles().live_count() <= AmbientParticles.MAX and b.particles().live_count() > 0, "particles capped")
	var full_particles := b.particles().live_count()
	Settings.ambient_motion = Motion.REDUCED
	EventBus.settings_changed.emit()
	await physics_frames(1)
	check(life.count(&"moth") <= AmbientLife.CAPS[&"moth"] / 2, "Reduced halves moths (%d)" % life.count(&"moth"))
	check(b.particles().live_count() <= full_particles / 2 + 1, "Reduced halves particles")
	Settings.ambient_motion = Motion.OFF
	EventBus.settings_changed.emit()
	await physics_frames(1)
	check(life.critter_sprites().is_empty(), "Off: no critters")
	check(b.particles().live_count() == 0, "Off: no particles")
	var drifts := b.fogs().map(func(f: FogBand) -> float: return f.drift)
	await physics_frames(20)
	for i in b.fogs().size():
		check(is_equal_approx(b.fogs()[i].drift, drifts[i]), "Off: fog drift frozen")
	check(not b.foreground_layer().visible, "Off: foreground hidden")
	check(is_zero_approx(FogBand.speed_scale()), "Off: fog speed 0")
	Settings.ambient_motion = Motion.REDUCED
	check(is_equal_approx(FogBand.speed_scale(), 0.5), "Reduced: fog at half speed")


func test_rats_hide_while_enemies_are_near() -> void:
	var room := _room(WARD_ROOM)
	await physics_frames(3)
	var life := _backdrop_of(room).life()
	var rats := life._critters.filter(func(c: Dictionary) -> bool: return c["kind"] == &"rat")
	check(not rats.is_empty(), "the ward has a rat")
	if rats.is_empty():
		return
	var rat := rats[0]["sprite"] as AnimatedSprite2D
	var e: Enemy = preload("res://enemies/variants/Needle.tscn").instantiate()
	e.position = rat.position + Vector2(40, -8)
	e.ai_enabled = false
	room.add_child(e)
	await physics_frames(3)
	check(life.fight_on(rat.position), "a living enemy within 160 px counts as a fight")
	check(not rat.visible, "the rat hides")


func test_foreground_rules() -> void:
	check(not PresentationIndex.for_room(PURSUIT_ROOM).foreground, "no foreground in First Pursuit")
	for path in PresentationIndex.get_index().rooms:
		var pres := PresentationIndex.for_room(path)
		if not pres.foreground or path.ends_with("TitleBackdrop.tscn"):
			continue
		var room := (load(path) as PackedScene).instantiate()
		check(room.find_children("*", "CeilingTracker", true, false).is_empty(), "%s has fg and no Collector eye rail" % path.get_file())
		room.free()
	var room := _room(WARD_ROOM)
	await physics_frames(3)
	var b := _backdrop_of(room)
	check(b.foreground_layer() != null and b.foreground_layer().layer > 0, "the ward has a foreground layer in front of the world")
	check(not b.foreground_pieces().is_empty(), "fg pieces placed")
	for p in b.foreground_pieces():
		var size: Vector2 = p["size"]
		if p["top"]:
			check(size.y <= DistrictBackdrop.FG_TOP_BAND and is_zero_approx((p["node"] as Node2D).position.y), "top piece in the top 40 px")
		else:
			var node := p["node"] as Node2D
			if node.visible:
				var line: float = float(p["floor"]) - room.camera.get_screen_center_position().y + VIEW.y * 0.5
				check(node.position.y >= line, "bottom piece below the floor line (%f >= %f)" % [node.position.y, line])
	var pursuit := _room(PURSUIT_ROOM)
	await physics_frames(2)
	check(_backdrop_of(pursuit).foreground_layer() == null, "First Pursuit builds no foreground")


func test_lightning_off_at_motion_off_and_static_under_flash_reduction() -> void:
	var b := _bare_backdrop(&"ll_roof", "res://data/districts/lowlight.tres")
	check(b.backdrop_set.lightning, "roofs have lightning")
	Settings.ambient_motion = Motion.OFF
	b._lightning_timer = 0.01
	await physics_frames(20)
	check(b.sky_flash() == Color.WHITE, "no lightning at ambient motion Off")
	Settings.ambient_motion = Motion.FULL
	b._lightning_timer = 0.01
	var saw := false
	for i in 20:
		await get_tree().process_frame
		saw = saw or b.sky_flash() != Color.WHITE
	check(saw, "a flash at Full")
	for t in [0.0, 0.1, 0.2, 0.5, 0.9]:
		check(DistrictBackdrop.lightning_tint(t, true) == DistrictBackdrop.FLASH_STATIC_TINT, "flash reduction: steady brighter sky at %.1f s" % t)
	check(DistrictBackdrop.lightning_tint(0.1, false) == Color.WHITE, "a strobe gap without flash reduction")


func test_fog_and_shafts_hold_still_when_asked() -> void:
	var b := _bare_backdrop(&"uc_pursuit")
	check(b.fogs().size() == 2, "two fog bands")
	var s := LightShaft.create(false, Vector2.ZERO, Color.WHITE, 0.0)
	add_child(s)
	Settings.flash_reduction = true
	await physics_frames(5)
	check(is_equal_approx(s.self_modulate.a, 1.0), "shaft static under flash reduction")
	Settings.flash_reduction = false
	Settings.ambient_motion = Motion.OFF
	await physics_frames(5)
	check(is_equal_approx(s.self_modulate.a, 1.0), "shaft static at Off")


func test_cloth_and_cables_freeze_below_full() -> void:
	var host := Node2D.new()
	add_child(host)
	var cable := SwayCable.create(Vector2(96, 20), Color.WHITE, 7)
	host.add_child(cable)
	var cloth := ClothStrip.for_banner(Vector2(16, 30), Color.GRAY, Color.WHITE, 3)
	host.add_child(cloth)
	cable._next_gust = 0.0
	await physics_frames(30)
	check(cable.pts != cable.rest, "the cable sways at Full")
	Settings.ambient_motion = Motion.REDUCED
	await physics_frames(2)
	check(cable.pts == cable.rest, "Reduced: cable at rest")
	check(cloth.segment_offsets() == PackedInt32Array([0, 0, 0]), "Reduced: cloth at rest")


func test_title_backdrop_layers_and_rook() -> void:
	var title := (load(TITLE_SCENE) as PackedScene).instantiate()
	add_child(title)
	await physics_frames(2)
	var b: DistrictBackdrop = null
	for c in title.get_children():
		if c is DistrictBackdrop:
			b = c
	check(b != null and b.backdrop_kind == &"title", "the title uses the title set")
	check(b.planes().size() == 3 and not b.procedural_skyline(), "sky, spires and rooftops")
	check(b.backdrop_set.lightning and b.backdrop_set.life.has(&"train"), "far lightning and a train")
	var rook: SpriteActor = title.call("title_rook")
	check(rook != null and rook.animation == &"title_stand", "Rook stands on the ledge")
	check(rook.get_global_transform_with_canvas().origin.x >= VIEW.x * 2.0 / 3.0 - 16.0, "the ledge is in the right third")
