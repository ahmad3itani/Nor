@tool
class_name GrayboxBlock
extends StaticBody2D
## Rectangle of solid (or one-way) graybox geometry. Size is authored in the
## scene; the collision shape is rebuilt from it so the tscn stays pure data.
## Origin is the top-left corner, matching how level designers think in tiles.

const COLOR_SOLID := Color("3a3548")
const COLOR_EDGE := Color("6b6380")
const COLOR_ONE_WAY := Color("5c7a8a")
## The 16 px autotile atlas layout shared by every district tileset
## (tools/assetgen tiles_null.py / env_process.build_atlas): 8 columns,
## row-major names. Tests check it against each tileset's .json.
const TILE := 16
const TILE_COLS := 8
const TILE_NAMES: Array[StringName] = [
	&"top_L", &"top_M", &"top_R", &"top_single", &"wall_L", &"wall_R", &"inner_TL", &"inner_TR",
	&"fill_0", &"fill_1", &"fill_2", &"fill_3", &"under_L", &"under_M", &"under_R", &"under_single",
	&"oneway_L", &"oneway_M", &"oneway_R", &"oneway_single", &"col_top", &"col_mid", &"col_bottom", &"block_single",
	&"face_0", &"face_1", &"face_2", &"face_3", &"inner_BL", &"inner_BR", &"wall_L_bottom", &"wall_R_bottom",
	&"fill_4", &"fill_5", &"fill_6", &"fill_7", &"fill_8", &"fill_9", &"fill_10", &"fill_11",
	&"fill_12", &"fill_13", &"fill_14", &"fill_15", &"fill_16", &"fill_17", &"fill_18", &"fill_19"]
const FILL_TILES := 20

## path -> Texture2D (null when missing), shared by every block.
static var _tilesets: Dictionary = {}

@export var size: Vector2 = Vector2(64, 16):
	set(v):
		size = v.snapped(Vector2.ONE)
		_rebuild()
@export var one_way: bool = false:
	set(v):
		one_way = v
		_rebuild()

var _shape_node: CollisionShape2D
var _theme: DistrictTheme


func _ready() -> void:
	var n := get_parent()
	while n and not _theme:
		if n is Room:
			_theme = (n as Room).theme
		n = n.get_parent()
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _shape_node == null:
		_shape_node = CollisionShape2D.new()
		add_child(_shape_node)
	var rect := RectangleShape2D.new()
	rect.size = size
	_shape_node.shape = rect
	_shape_node.position = size * 0.5
	_shape_node.one_way_collision = one_way
	# Layer 1 = world, layer 3 = one-way (the player's stand check ignores one-way).
	collision_layer = 4 if one_way else 1
	collision_mask = 0
	queue_redraw()


## The theme's tileset atlas, or null (flat fill).
func tileset() -> Texture2D:
	if _theme == null or _theme.tileset_path == "":
		return null
	var path := _theme.tileset_path
	if not _tilesets.has(path):
		_tilesets[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _tilesets[path]


## The atlas tile name for cell (cx, cy) of a cols x rows solid block.
## Fills and faces vary by a hash of the cell's world position.
static func tile_for(cx: int, cy: int, cols: int, rows: int, one_way_block: bool, world_cell: Vector2i) -> StringName:
	var h := absi(hash(world_cell))
	if one_way_block:
		if cols == 1:
			return &"oneway_single"
		return &"oneway_L" if cx == 0 else (&"oneway_R" if cx == cols - 1 else &"oneway_M")
	if cols == 1:
		if rows == 1:
			return &"block_single"
		return &"col_top" if cy == 0 else (&"col_bottom" if cy == rows - 1 else &"col_mid")
	var left := cx == 0
	var right := cx == cols - 1
	if cy == 0:
		if rows == 1:
			return &"top_L" if left else (&"top_R" if right else &"top_M")
		return &"top_L" if left else (&"top_R" if right else &"top_M")
	if cy == rows - 1 and rows > 2:
		return &"under_L" if left else (&"under_R" if right else &"under_M")
	if left:
		return &"wall_L_bottom" if cy == rows - 1 else &"wall_L"
	if right:
		return &"wall_R_bottom" if cy == rows - 1 else &"wall_R"
	if cy == 1:
		return StringName("face_%d" % (h % 4))
	var f := h % FILL_TILES
	return StringName("fill_%d" % f)


func _draw() -> void:
	var atlas := tileset()
	if atlas:
		_draw_tiles(atlas)
		return
	var solid := _theme.solid_color if _theme else COLOR_SOLID
	var edge := _theme.edge_color if _theme else COLOR_EDGE
	if one_way:
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, 3)), _theme.one_way_color if _theme else COLOR_ONE_WAY)
		return
	draw_rect(Rect2(Vector2.ZERO, size), solid)
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, 1)), edge)
	if _theme and size.y > 24.0:
		# Subtle vertical banding: reads as masonry/concrete rather than a flat box.
		var x := 8.0
		while x < size.x:
			draw_rect(Rect2(x, 2, 1, size.y - 2), solid.darkened(0.12))
			x += 24.0


## The theme's 16 px autotile atlas over the block (draw only: size, one_way
## and the collision shape are untouched). Partial cells at the right and
## bottom take the tile's right / bottom part so edges keep their pixels.
func _draw_tiles(atlas: Texture2D) -> void:
	var cols := maxi(1, int(ceil(size.x / TILE)))
	var rows := 1 if one_way else maxi(1, int(ceil(size.y / TILE)))
	var origin_cell := Vector2i((global_position / TILE).floor()) if is_inside_tree() else Vector2i.ZERO
	for cy in rows:
		for cx in cols:
			var name_id := tile_for(cx, cy, cols, rows, one_way, origin_cell + Vector2i(cx, cy))
			var idx := TILE_NAMES.find(name_id)
			if idx < 0:
				continue
			var w := minf(TILE, size.x - cx * TILE)
			var h: float = minf(TILE, size.y - cy * TILE) if not one_way else float(TILE)
			if w <= 0.0 or h <= 0.0:
				continue
			var src := Rect2((idx % TILE_COLS) * TILE, floori(idx / float(TILE_COLS)) * TILE, TILE, TILE)
			# Right-edge and bottom partial cells show the tile's far side.
			if cx == cols - 1 and cols > 1:
				src.position.x += TILE - w
			if cy == rows - 1 and rows > 1:
				src.position.y += TILE - h
			src.size = Vector2(w, h)
			draw_texture_rect_region(atlas, Rect2(cx * TILE, cy * TILE, w, h), src)
