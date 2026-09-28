class_name ScrapPickup
extends Node2D
## Scrap from kills and breakables. Pops out, then homes onto Rook after a
## short delay so collecting never interrupts movement (pillar §2.1).

const HOME_DELAY := 0.35
const COLLECT_DISTANCE := 10.0
const COLOR := Color("ffd36b")
## Presentation (T06): props/pickups.png holds the baked parts and
## pickups_fill.png the tint masks in the same 16 px layout; rows per anim.
const ART_BAKED := "res://assets/props/pickups.png"
const ART_FILL := "res://assets/props/pickups_fill.png"
const ART_CELL := 16
## anim -> [row, frames, fps, origin]
const ART_ROWS := {
	&"scrap_spin": [0, 6, 12.0, Vector2(8, 8)],
	&"scrap_cache": [1, 1, 1.0, Vector2(8, 15)],
	&"memory_shard": [2, 8, 8.0, Vector2(8, 8)],
	&"core_shard": [3, 8, 8.0, Vector2(8, 8)],
}

static var _art_baked: Texture2D
static var _art_fill: Texture2D
static var _art_loaded: bool = false

var value: int = 1
var velocity: Vector2
var _age: float = 0.0
var _target: Node2D


static func burst(parent: Node, at: Vector2, total: int) -> void:
	var remaining := total
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(at)
	while remaining > 0:
		var p := ScrapPickup.new()
		p.value = mini(remaining, 5 if remaining > 10 else 1)
		remaining -= p.value
		p.position = at
		p.velocity = Vector2(rng.randf_range(-90, 90), rng.randf_range(-180, -90))
		parent.add_child(p)


func _physics_process(delta: float) -> void:
	_age += delta
	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group(&"player") as Node2D
	if _age < HOME_DELAY or _target == null:
		velocity.y += 500.0 * delta
		velocity *= 0.97
	else:
		var goal := _target.global_position + Vector2(0, -14)
		var to := goal - global_position
		if to.length() < COLLECT_DISTANCE:
			_collect()
			return
		velocity = velocity.lerp(to.normalized() * (180.0 + _age * 260.0), 0.25)
	position += velocity * delta
	queue_redraw()


func _collect() -> void:
	Game.add_scrap(roundi(value * Game.scrap_multiplier()))
	AudioManager.play_sfx(&"scrap_pickup")
	queue_free()


## Draws pickup art on `ci` (baked parts, then the fill tinted `tint`) with
## the anim's origin at `at`, frame from `t` seconds. False when the sheets
## are missing: the caller draws its placeholder shape.
static func draw_art(ci: CanvasItem, anim: StringName, t: float, tint: Color, at: Vector2 = Vector2.ZERO) -> bool:
	if not has_art(anim):
		return false
	var r: Array = ART_ROWS[anim]
	var frame := int(t * float(r[2])) % int(r[1])
	var src := Rect2(frame * ART_CELL, int(r[0]) * ART_CELL, ART_CELL, ART_CELL)
	var dst := Rect2((at - (r[3] as Vector2)).round(), Vector2(ART_CELL, ART_CELL))
	if _art_baked:
		ci.draw_texture_rect_region(_art_baked, dst, src)
	ci.draw_texture_rect_region(_art_fill, dst, src, tint)
	return true


## True when `anim` can draw from the pickup sheets (else: placeholder).
static func has_art(anim: StringName) -> bool:
	if not _art_loaded:
		_art_loaded = true
		_art_baked = load(ART_BAKED) as Texture2D if ResourceLoader.exists(ART_BAKED) else null
		_art_fill = load(ART_FILL) as Texture2D if ResourceLoader.exists(ART_FILL) else null
	return _art_fill != null and ART_ROWS.has(anim)


## Test hook: forget the cached sheets (a test pointing at missing art).
static func reset_art_cache(baked: String = ART_BAKED, fill: String = ART_FILL) -> void:
	_art_loaded = true
	_art_baked = load(baked) as Texture2D if ResourceLoader.exists(baked) else null
	_art_fill = load(fill) as Texture2D if ResourceLoader.exists(fill) else null


func _draw() -> void:
	if draw_art(self, &"scrap_spin", _age + float(get_instance_id() % 7) * 0.08, Palette.color(&"currency")):
		return
	var s := 2.0 if value == 1 else 3.0
	draw_rect(Rect2(Vector2(-s, -s) * 0.5, Vector2(s, s)), COLOR)
