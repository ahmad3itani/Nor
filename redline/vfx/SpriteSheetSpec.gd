class_name SpriteSheetSpec
extends Resource
## How to cut a character sheet into animations (Art Bible §9). Point an
## EnemyData.sprite / the player visual at one and the placeholder drawing
## is replaced by the sprite, with no code change (D-026 swap-in rule).
## Telegraphs and health bars keep drawing on top (accessibility aids).

@export_file("*.png") var texture_path: String = ""
@export var cell_size: Vector2i = Vector2i(48, 48)
## Pixel in a cell that sits on the node's origin: bottom-centre, at the feet.
@export var origin: Vector2i = Vector2i(24, 46)
@export var animations: Array[SpriteAnim] = []


func load_texture() -> Texture2D:
	if texture_path.begins_with("res://"):
		return load(texture_path) as Texture2D if ResourceLoader.exists(texture_path) else null
	var img := Image.load_from_file(texture_path)
	return ImageTexture.create_from_image(img) if img else null


func build_frames() -> SpriteFrames:
	var tex := load_texture()
	if tex == null:
		return null
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for a in animations:
		frames.add_animation(a.name)
		frames.set_animation_speed(a.name, a.fps)
		frames.set_animation_loop(a.name, a.loop)
		for i in a.frame_count:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(Vector2((a.first_frame + i) * cell_size.x, a.row * cell_size.y), Vector2(cell_size))
			frames.add_frame(a.name, at)
	return frames


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if texture_path == "":
		errors.append("sprite spec without texture_path")
		return errors
	var tex := load_texture()
	if tex == null:
		errors.append("sprite texture missing: %s" % texture_path)
		return errors
	var size := Vector2i(tex.get_size())
	if size.x % cell_size.x != 0 or size.y % cell_size.y != 0:
		errors.append("%s: %dx%d is not a multiple of the %dx%d cell" % [texture_path.get_file(), size.x, size.y, cell_size.x, cell_size.y])
	if origin.x < 0 or origin.y < 0 or origin.x >= cell_size.x or origin.y >= cell_size.y:
		errors.append("%s: origin %s outside the cell" % [texture_path.get_file(), origin])
	var cols := size.x / maxi(1, cell_size.x)
	var rows := size.y / maxi(1, cell_size.y)
	var seen := {}
	for a in animations:
		if seen.has(a.name):
			errors.append("%s: duplicate animation %s" % [texture_path.get_file(), a.name])
		seen[a.name] = true
		if a.row >= rows or a.first_frame + a.frame_count > cols or a.frame_count < 1:
			errors.append("%s: animation %s runs outside the sheet" % [texture_path.get_file(), a.name])
	return errors
