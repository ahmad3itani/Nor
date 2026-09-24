extends RedlineTestCase
## M6 art pipeline: sheets validated against the Art Bible, and final art
## swaps in for the placeholders with data only.

const DIR := "user://test_art"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func after_each() -> void:
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute("%s/%s" % [DIR, f])
	await physics_frames(1)


## A crisp 2-frame 48x48 strip (plus a blurred variant for failure cases).
func _sheet(file: String, size := Vector2i(96, 48), soft := false) -> String:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(18, 10, 12, 36), Color("d8d4e0"))
	img.fill_rect(Rect2i(66, 12, 12, 34), Color("d8d4e0"))
	if soft:
		img.set_pixel(17, 20, Color(1, 1, 1, 0.5))
	var path := "%s/%s" % [DIR, file]
	img.save_png(path)
	return path


func _spec(path: String) -> SpriteSheetSpec:
	var s := SpriteSheetSpec.new()
	s.texture_path = ProjectSettings.globalize_path(path)
	var a := SpriteAnim.new()
	a.name = &"idle"
	a.frame_count = 2
	s.animations = [a]
	return s


func test_good_sheet_passes_and_builds_frames() -> void:
	var path := _sheet("needle_idle.png")
	var v := ArtValidator.new()
	v.check_image(path)
	check(v.errors.is_empty(), "good sheet flagged: %s" % v.errors)
	var spec := _spec(path)
	check(spec.validate().is_empty(), "spec invalid: %s" % spec.validate())
	var frames := spec.build_frames()
	check(frames.has_animation(&"idle") and frames.get_frame_count(&"idle") == 2, "frames not cut from the sheet")


func test_bad_sheets_are_rejected() -> void:
	var v := ArtValidator.new()
	v.check_image(_sheet("NeedleIdle.png"))
	check(Array(v.errors).any(func(e: String) -> bool: return e.contains("snake_case")), "bad name not caught")
	v = ArtValidator.new()
	v.check_image(_sheet("needle_soft.png", Vector2i(96, 48), true))
	check(Array(v.errors).any(func(e: String) -> bool: return e.contains("semi-transparent")), "soft alpha not caught")
	var spec := _spec(_sheet("needle_odd.png", Vector2i(100, 48)))
	check(Array(spec.validate()).any(func(e: String) -> bool: return e.contains("not a multiple")), "odd sheet size not caught")
	spec.animations[0].frame_count = 5
	check(Array(spec.validate()).any(func(e: String) -> bool: return e.contains("outside the sheet")), "animation overrun not caught")


func test_repo_art_and_project_filter_are_valid() -> void:
	var v := ArtValidator.new().run()
	check(v.ok(), "art validation errors: %s" % v.errors)


func test_enemy_sprite_replaces_placeholder() -> void:
	var data: EnemyData = (load("res://data/enemies/needle.tres") as EnemyData).duplicate()
	data.sprite = _spec(_sheet("needle_idle.png"))
	var e: Enemy = load("res://enemies/variants/Needle.tscn").instantiate()
	e.data = data
	e.ai_enabled = false
	add_child(e)
	await physics_frames(2)
	var visual := e.get_node("Visual")
	check(visual.uses_sprite(), "enemy should draw from the sprite sheet")
	check(visual.actor.animation == &"idle" and visual.actor.is_playing(), "idle should play")
	e.queue_free()


func test_player_sprite_replaces_placeholder() -> void:
	var p: Player = load("res://player/Player.tscn").instantiate()
	var visual := p.find_child("*Visual*", true, false)
	check(visual != null and "sprite" in visual, "player visual missing")
	visual.sprite = _spec(_sheet("rook_idle.png"))
	p.abilities = PlayerAbilities.new()
	add_child(p)
	p.respawn(Vector2.ZERO)
	await physics_frames(3)
	check(visual.actor != null and visual.actor.animation == &"idle", "Rook should play idle from the sheet")
	p.queue_free()
