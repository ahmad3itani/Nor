class_name VfxOneShot
extends Node2D
## A pooled-by-cap sprite effect from the VFX library (hit sparks, smears,
## dust, bursts): spawn it, it plays and frees itself.
##
##   VfxOneShot.spawn(room, &"dust", &"land", at, {"facing": -1})
##
## Returns null (so the caller keeps its placeholder effect) when the id is
## unknown, its sheet or animation is missing, or the id's live cap is full.
## opts:
##   facing: int            -1 flips the +x-facing sheet
##   direction: Vector2     snapped to 90-degree steps: left/right become a
##                          flip, up/down a 90/270 rotation (never 45: diamond
##                          mixels at integer scale)
##   tint: Color / palette_key: StringName   (else the library default;
##                          unknown keys fall back to tint or white)
##   z_index: int, speed_scale: float
##   follow: Node2D         keeps the spawn offset to it; freed with it
##   hold_last: bool        a non-looping anim stays on its last frame
##   lifetime: float        seconds, then it frees (any anim)
## A looping anim without lifetime frees when `follow` goes away or on
## EventBus.room_leaving, so nothing leaks. Under flash reduction the tint's
## value is scaled by 0.7 (tone 255 -> ~178). stop() frees it at once.
##
## A Node2D holding an AnimatedSprite2D (`sprite`): AnimatedSprite2D.stop()
## is native and cannot be overridden, and stop() must free the effect.

## Flash reduction scales the tint's value by this (Art Bible / fx notes).
const FLASH_REDUCED_VALUE := 0.7

## id -> live instances (in the tree).
static var _live: Dictionary = {}
## "id/anim" -> true once warned about a missing animation.
static var _warned: Dictionary = {}
static var _additive: CanvasItemMaterial

var vfx_id: StringName = &""
var spec: SpriteSheetSpec
var sprite: AnimatedSprite2D
var lifetime: float = -1.0
var hold_last: bool = false
var _age: float = 0.0
var _follow: Node2D
var _has_follow: bool = false
var _follow_delta: Vector2 = Vector2.ZERO
var _counted: bool = false

## Read-only views of the sprite, so callers can treat the effect like one.
var animation: StringName:
	get: return sprite.animation if sprite else &""
var frame: int:
	get: return sprite.frame if sprite else 0
var flip_h: bool:
	get: return sprite.flip_h if sprite else false
var flip_v: bool:
	get: return sprite.flip_v if sprite else false
var offset: Vector2:
	get: return sprite.offset if sprite else Vector2.ZERO


static func spawn(parent: Node, id: StringName, anim: StringName, at: Vector2, opts: Dictionary = {}) -> VfxOneShot:
	if parent == null or not is_instance_valid(parent):
		return null
	var e := VfxLibrary.entry(id)
	if e.is_empty():
		return null
	var frames := VfxLibrary.frames(id)
	if frames == null:
		return null
	if not frames.has_animation(anim):
		var key := "%s/%s" % [id, anim]
		if not _warned.has(key):
			_warned[key] = true
			push_warning("VfxOneShot: sheet '%s' has no animation '%s'" % [id, anim])
		return null
	var cap := int(e.get("cap", 0))
	if cap > 0 and live_count(id) >= cap:
		return null
	var fx := VfxOneShot.new()
	fx.vfx_id = id
	fx.spec = VfxLibrary.spec(id)
	fx._setup(frames, anim, VfxLibrary.default_color(id), bool(e.get("additive", false)), opts)
	fx._place(parent, at, opts)
	return fx


## Character death copies and other one-off frames (no library entry, no cap).
## opts as spawn(), plus offset: Vector2 (the frames' origin offset).
static func spawn_frames(parent: Node, frames: SpriteFrames, anim: StringName, at: Vector2, opts: Dictionary = {}) -> VfxOneShot:
	if parent == null or not is_instance_valid(parent) or frames == null or not frames.has_animation(anim):
		return null
	var fx := VfxOneShot.new()
	fx._setup(frames, anim, Color.WHITE, bool(opts.get("additive", false)), opts)
	fx._place(parent, at, opts)
	return fx


static func live_count(id: StringName) -> int:
	return int(_live.get(id, 0))


## Frees the effect now (a looping aura when its owner stops, a held frame).
func stop() -> void:
	if not is_queued_for_deletion():
		queue_free()


func _setup(frames: SpriteFrames, anim: StringName, default_tint: Color, additive: bool, opts: Dictionary) -> void:
	name = "Vfx_%s" % (vfx_id if vfx_id != &"" else &"frames")
	sprite = AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = frames
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.animation = anim
	sprite.speed_scale = float(opts.get("speed_scale", 1.0))
	add_child(sprite)
	# Facing: flips only; vertical directions rotate by exact quarter turns.
	var fh := int(opts.get("facing", 1)) < 0
	var fv := false
	var quarter := 0
	if opts.has("direction") and opts["direction"] is Vector2 and (opts["direction"] as Vector2) != Vector2.ZERO:
		var d: Vector2 = opts["direction"]
		if absf(d.x) >= absf(d.y):
			fh = d.x < 0.0
		else:
			fh = false
			quarter = 1 if d.y > 0.0 else 3
	sprite.flip_h = fh
	sprite.flip_v = fv
	rotation = quarter * PI * 0.5
	if spec:
		sprite.offset = spec.offset_for(anim, fh, fv)
	elif opts.has("offset"):
		var o: Vector2 = opts["offset"]
		sprite.offset = Vector2(-o.x if fh else o.x, o.y)
	modulate = _tint(default_tint, opts)
	if additive:
		if _additive == null:
			_additive = CanvasItemMaterial.new()
			_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		sprite.material = _additive
	if opts.has("z_index"):
		z_index = int(opts["z_index"])
	lifetime = float(opts.get("lifetime", -1.0))
	hold_last = bool(opts.get("hold_last", false))
	if opts.get("follow") is Node2D:
		_follow = opts["follow"]
		_has_follow = true
	sprite.animation_finished.connect(_on_finished)


func _place(parent: Node, at: Vector2, _opts: Dictionary) -> void:
	position = at
	parent.add_child(self)
	if _has_follow and is_instance_valid(_follow):
		_follow_delta = global_position - _follow.global_position
	sprite.play(sprite.animation)


func _tint(default_tint: Color, opts: Dictionary) -> Color:
	var c := default_tint
	var has_tint := opts.get("tint") is Color
	if has_tint:
		c = opts["tint"]
	if opts.has("palette_key"):
		var key := StringName(opts["palette_key"])
		if VfxLibrary.is_palette_key(key):
			c = Palette.color(key)
		else:
			push_warning("VfxOneShot: unknown palette key '%s' (%s); using %s" % [key, vfx_id, "the tint" if has_tint else "white"])
			c = opts["tint"] if has_tint else Color.WHITE
	if _flash_reduced():
		c = Color(c.r * FLASH_REDUCED_VALUE, c.g * FLASH_REDUCED_VALUE, c.b * FLASH_REDUCED_VALUE, c.a)
	return c


func _enter_tree() -> void:
	if vfx_id != &"" and not _counted:
		_live[vfx_id] = live_count(vfx_id) + 1
		_counted = true
	var bus := _event_bus()
	if bus and not bus.is_connected("room_leaving", _on_room_leaving):
		bus.connect("room_leaving", _on_room_leaving)


func _exit_tree() -> void:
	if _counted:
		_live[vfx_id] = maxi(0, live_count(vfx_id) - 1)
		_counted = false
	var bus := _event_bus()
	if bus and bus.is_connected("room_leaving", _on_room_leaving):
		bus.disconnect("room_leaving", _on_room_leaving)


func _process(delta: float) -> void:
	_age += delta
	if lifetime > 0.0 and _age >= lifetime:
		stop()
		return
	if _has_follow:
		if not is_instance_valid(_follow) or _follow.is_queued_for_deletion() or not _follow.is_inside_tree():
			stop()
			return
		global_position = _follow.global_position + _follow_delta


func _on_finished() -> void:
	# Only non-looping animations emit animation_finished.
	if hold_last:
		return
	stop()


func _on_room_leaving(_room: Node) -> void:
	stop()


static func _flash_reduced() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var s: Node = tree.root.get_node_or_null("Settings") if tree and tree.root else null
	return s != null and bool(s.get("flash_reduction"))


static func _event_bus() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("EventBus") if tree and tree.root else null
