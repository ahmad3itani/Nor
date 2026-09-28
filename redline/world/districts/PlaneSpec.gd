class_name PlaneSpec
extends Resource
## One painted parallax plane of a BackdropSet (presentation overhaul,
## ART_DIRECTION section 0 value ladder). Paths are plain strings: a missing
## texture drops the plane and the backdrop falls back to its procedural
## skyline, so nothing here can break a room.
##
## Motion ladder (x / y): sky 0/0 (screen-fixed), far 0.12/0.03, fog A
## 0.2/0.05, mid 0.3/0.07, near 0.55/0.2, backwall 0.85/0.85, fog B 0.6/0.3,
## foreground 1.2.

## The plane's texture (res://assets/...png).
@export var texture_path: String = ""
## Optional B variant: the plane alternates A, B, A, B... every tile, so the
## 480 px source does not visibly repeat (F8).
@export var alt_path: String = ""
@export var motion: Vector2 = Vector2(0.3, 0.07)
## Bottom of the plane relative to the view bottom (px, negative = higher)
## while the camera rests at the room floor (its lowest position).
@export var y_anchor: float = 0.0
## Repeat vertically too (tall rooms, backwalls); y_anchor is then ignored.
@export var tile_y: bool = false
## Horizontal repeat in px (0 = the texture width). A landmark sprite uses
## a large spacing so it shows up once every few screens.
@export var spacing: int = 0
## Shifts the repeat (px), so two planes of one texture do not line up.
@export var x_offset: float = 0.0
## Opaque and covering the whole view at every camera position: everything
## behind it is hidden (fill-rate, REPAIR e).
@export var opaque: bool = false
## A foreground silhouette set (atlas + .json regions next to it) drawn in
## front of the world at motion 1.2, only in the top 40 px and below the
## floor line, and only where RoomPresentation.foreground allows it.
@export var is_foreground: bool = false


func load_texture() -> Texture2D:
	return PlaneSpec.load_at(texture_path)


func load_alt() -> Texture2D:
	return PlaneSpec.load_at(alt_path)


## A res:// texture or null when the path is empty or missing.
static func load_at(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## Every path this plane names (tests check they all exist).
func paths() -> PackedStringArray:
	var out := PackedStringArray([texture_path])
	if alt_path != "":
		out.append(alt_path)
	return out
