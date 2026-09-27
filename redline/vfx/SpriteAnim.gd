class_name SpriteAnim
extends Resource
## One animation strip inside a sprite sheet (Art Bible §6/§9: horizontal
## strips, fixed cell size; 12 fps base, 15-24 for fast actions).

@export var name: StringName = &"idle"
@export var row: int = 0
@export var first_frame: int = 0
@export var frame_count: int = 1
@export_range(1, 30) var fps: float = 12.0
@export var loop: bool = true
## Per-animation origin override (a VFX row anchored somewhere else, e.g. a
## wall scrape at the wall, a ground wave at its base). (-1, -1) = the
## sheet's origin (SpriteSheetSpec.origin_for).
@export var origin: Vector2i = Vector2i(-1, -1)
