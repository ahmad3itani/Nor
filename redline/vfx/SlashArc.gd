class_name SlashArc
extends Node2D
## Placeholder slash smear: a crescent swept across the attack's hitbox for
## its active window, then fading. Readable at 480x270 without sprites.

const LIFETIME := 0.12

var rect: Rect2
var facing: int = 1
var color: Color = Color("ffffff")
var heavy: bool = false
var _age: float = 0.0


## Presentation overhaul T06: attack id -> vfx/slash_smears row. Exact ids
## first, then prefixes; an id with no row keeps this placeholder arc.
const SMEAR_ROWS := {
	&"blade_heavy": &"heavy", &"blade_launcher": &"launcher", &"blade_air_light": &"air",
	&"blade_air_heavy": &"spike", &"katar_spin": &"katar_spin",
}
const SMEAR_PREFIXES := {"blade_light_": &"light", "katar_": &"katar"}


## The smear row for an attack id, or &"" (unknown ids keep the arc).
static func smear_row(attack_id: StringName) -> StringName:
	if SMEAR_ROWS.has(attack_id):
		return SMEAR_ROWS[attack_id]
	for prefix: String in SMEAR_PREFIXES:
		if String(attack_id).begins_with(prefix):
			return SMEAR_PREFIXES[prefix]
	return &""


## True when the sprite smear for this attack can play (row known, sheet
## loaded): the caller then waits for the active window instead of drawing
## the arc at the swing's start.
static func has_smear(attack_id: StringName) -> bool:
	var row := smear_row(attack_id)
	if row == &"":
		return false
	var frames := VfxLibrary.frames(&"slash_smears")
	return frames != null and frames.has_animation(row)


## The sprite smear centred on the attack's world hitbox (the sheet's cells
## are built around it), flipped by facing and carried with the swing.
static func smear(parent: Node, attack_id: StringName, world_rect: Rect2, p_facing: int, follow: Node2D = null) -> VfxOneShot:
	var row := smear_row(attack_id)
	if row == &"":
		return null
	var opts := {"facing": p_facing}
	if follow:
		opts["follow"] = follow
	return VfxOneShot.spawn(parent, &"slash_smears", row, world_rect.get_center(), opts)


static func spawn(parent: Node, world_rect: Rect2, p_facing: int, p_color: Color, p_heavy: bool) -> SlashArc:
	var s := SlashArc.new()
	s.rect = world_rect
	s.facing = p_facing
	s.color = p_color
	s.heavy = p_heavy
	parent.add_child(s)
	return s


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := _age / LIFETIME
	var c := rect.get_center()
	var radius := Vector2(rect.size.x * 0.55, rect.size.y * 0.55)
	var start_angle := -PI * 0.55
	var sweep := PI * 1.1 * clampf(t * 2.5, 0.0, 1.0)
	var steps := 10
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var thickness := (4.0 if heavy else 2.5) * (1.0 - t)
	for i in steps + 1:
		var a := start_angle + sweep * float(i) / steps
		var dir := Vector2(cos(a) * facing, sin(a))
		outer.append(c + dir * radius)
		inner.append(c + dir * (radius - Vector2.ONE * thickness))
	var poly := outer.duplicate()
	inner.reverse()
	poly.append_array(inner)
	var col := color
	col.a = 1.0 - t
	if poly.size() >= 3:
		draw_colored_polygon(poly, col)
