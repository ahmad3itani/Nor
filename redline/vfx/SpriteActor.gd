class_name SpriteActor
extends AnimatedSprite2D
## Plays a SpriteSheetSpec with its origin (feet) on this node, picking the
## first animation that exists from a fallback list, so partial art sets work
## (e.g. no "windup" yet -> "attack" -> "idle").
##
## Presentation overhaul (T01):
## - per-animation origins (SpriteAnim.origin) are applied whenever the
##   animation or the facing changes; flip_h mirrors the texture but not
##   `offset`, so the x offset is negated when flipped (SpriteSheetSpec.offset_for);
## - play_once_first() restarts a non-looping animation and reports its end
##   through one_shot_finished;
## - a tint-mask overlay: when the spec names metadata/mask_path, a child
##   AnimatedSprite2D with the same animations on the mask texture follows
##   this node's animation, frame, flip and alpha and is modulated by
##   Palette.color(mask_palette_key), so colour-blind and high-contrast
##   settings re-tint the visor/Core seam. The baked colour stays underneath
##   as the fallback.

signal one_shot_finished(anim: StringName)

## Palette key the mask overlay uses when the spec names none.
const DEFAULT_MASK_KEY := &"accent"

var spec: SpriteSheetSpec
## The tint-mask overlay (null when the spec has no mask or it is missing).
var mask: AnimatedSprite2D
var _one_shot: StringName = &""
var _mask_key: StringName = DEFAULT_MASK_KEY


static func create(p_spec: SpriteSheetSpec) -> SpriteActor:
	if p_spec == null:
		return null
	var frames := p_spec.build_frames()
	if frames == null:
		return null
	var a := SpriteActor.new()
	a.spec = p_spec
	a.sprite_frames = frames
	a.centered = true
	a.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	a._apply_offset()
	a._build_mask()
	# Only a mask overlay needs the per-frame alpha copy; enemies and VFX
	# without one skip _process entirely (T09 repair: headless CPU).
	a.set_process(a.mask != null)
	a.animation_changed.connect(a._on_animation_changed)
	a.frame_changed.connect(a.sync_mask)
	a.animation_finished.connect(a._on_animation_finished)
	return a


func _enter_tree() -> void:
	var bus := _event_bus()
	if mask and bus and not bus.is_connected("settings_changed", retint_mask):
		bus.connect("settings_changed", retint_mask)
	retint_mask()


func _exit_tree() -> void:
	var bus := _event_bus()
	if bus and bus.is_connected("settings_changed", retint_mask):
		bus.disconnect("settings_changed", retint_mask)


func _process(_delta: float) -> void:
	# self_modulate (hurt blink, hit tint) is not inherited by children.
	sync_mask()


## Plays the first of `names` that the sheet has. Returns the one playing.
func play_first(names: Array) -> StringName:
	for item in names:
		var n := StringName(item)
		if sprite_frames.has_animation(n):
			if animation != n or not is_playing():
				play(n)
			return n
	return &""


## Plays the first of `names` that exists from its first frame, even when it
## is the current animation. one_shot_finished(anim) fires when a
## non-looping one ends. Returns the one playing (&"" when none exists).
func play_once_first(names: Array) -> StringName:
	for item in names:
		var n := StringName(item)
		if sprite_frames.has_animation(n):
			stop()
			_one_shot = n
			play(n)
			frame = 0
			frame_progress = 0.0
			return n
	return &""


func is_playing_one_shot() -> bool:
	return _one_shot != &"" and animation == _one_shot and is_playing()


func face(dir: int) -> void:
	var f := dir < 0
	if flip_h != f:
		flip_h = f
		_apply_offset()
		sync_mask()


## The tint the mask overlay draws with (Palette key from the spec's
## metadata/mask_palette_key, default accent).
func mask_color() -> Color:
	return Palette.color(_mask_key)


## Re-reads the mask colour (settings_changed: colour-blind mode, high contrast).
func retint_mask() -> void:
	if mask:
		mask.modulate = mask_color()


## Copies animation, frame, flip, offset and alpha onto the mask overlay.
func sync_mask() -> void:
	if mask == null:
		return
	if mask.animation != animation and mask.sprite_frames.has_animation(animation):
		mask.animation = animation
	if mask.frame != frame:
		mask.frame = frame
	# Guarded writes: a same-value set still queues a redraw.
	if mask.flip_h != flip_h:
		mask.flip_h = flip_h
	if mask.flip_v != flip_v:
		mask.flip_v = flip_v
	if mask.offset != offset:
		mask.offset = offset
	if mask.self_modulate.a != self_modulate.a:
		mask.self_modulate.a = self_modulate.a


func _apply_offset() -> void:
	if spec:
		offset = spec.offset_for(animation, flip_h, flip_v)


func _on_animation_changed() -> void:
	_apply_offset()
	if _one_shot != &"" and animation != _one_shot:
		_one_shot = &""
	sync_mask()


func _on_animation_finished() -> void:
	if _one_shot != &"" and animation == _one_shot:
		var n := _one_shot
		_one_shot = &""
		one_shot_finished.emit(n)


func _build_mask() -> void:
	var tex := spec.load_mask_texture()
	if tex == null:
		return
	var frames := spec.build_frames(tex)
	if frames == null:
		return
	_mask_key = StringName(spec.get_meta(&"mask_palette_key", DEFAULT_MASK_KEY))
	mask = AnimatedSprite2D.new()
	mask.name = "TintMask"
	mask.sprite_frames = frames
	mask.centered = true
	mask.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mask.animation = animation
	add_child(mask)
	retint_mask()
	sync_mask()


static func _event_bus() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("EventBus") if tree and tree.root else null
