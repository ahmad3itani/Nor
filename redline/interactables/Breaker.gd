@tool
class_name Breaker
extends Area2D
## Power breaker (M7 Lowlight "Grid" thesis, D-071): strike it and everything
## wired to its `circuit` reacts (PowerShutter, GridClamp, ScannerBeam). The
## read for the player is "act, often at range, then commit": no new verb,
## just the attacks and guns Rook already has.
##
## It takes player hits only, through the same receive path as BreakableWall
## (a Hurtbox on the ENEMY_HURTBOX layer): Rook's melee query and his shots
## find it, enemy attacks and projectiles target the player layer, and a
## launched body's impact check only hurts Enemies. It never emits
## enemy_damaged, so it grants no Core charge or style and cannot be farmed.
## Origin: top-left of the box, like GrayboxBlock. Not solid.

const COLOR_BOX := Color("2b2733")
const COLOR_EDGE := Color("6b6380")
const COLOR_GLYPH := Color("b8b2c8")
const LAMP_DIM := Color("4a3a22")
const LAMP_AMBER := Color("ffb347")
const FLASH := Color(1, 1, 1, 0.9)
## Placement standard, px above the solid floor under the breaker: a floor
## breaker's box spans -40..-16 (ground light attacks), a high breaker's
## -96..-72 (jump + air light, or any gun straight up). Nothing higher.
const HIGHEST_TOP := -96.0
## Source of truth for how high a grounded attack reaches: the first light
## attack of Rook's starting blade (its hitbox y-range, feet = 0).
const REACH_WEAPON := "res://data/weapons/pulse_blade.tres"
## Fallback if that weapon cannot be read (blade_light_1's hitbox today).
const GROUNDED_REACH := Vector2(-30.0, -8.0)
## Half of Rook's standing collider (12 px wide): he can stand with his
## centre this far past a platform's end.
const PLAYER_HALF_WIDTH := 6.0
## Fallback horizontal reach past a platform's end: blade_light_1's hitbox
## end (28) + its lunge over startup + active (70 px/s * 0.11 s) + the half
## width.
const GROUNDED_REACH_X := 41.7

@export var breaker_id: String = ""
@export var circuit: StringName = &""
@export var size: Vector2 = Vector2(16, 24):
	set(v):
		size = v
		queue_redraw()
## The hurtbox is the box grown by this much on every side (forgiving aim).
@export var hurtbox_margin: float = 4.0
## Hits closer together than this are ignored (one swing = one trip).
@export var rearm_time: float = 0.5

## Successful trips so far (tests, debug overlay).
var trips: int = 0
var _hurtbox: Hurtbox
var _since_trip: float = INF
var _flash: float = 0.0
## Lamp state is driven by the consumers (they know how long the circuit is
## live); the breaker only draws it.
var _live: float = 0.0
var _pulse: float = 0.0
var _recharge: float = 0.0
var _recharge_total: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false
	add_to_group(&"breakers")
	queue_redraw()
	if Engine.is_editor_hint():
		return
	_hurtbox = Hurtbox.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.receiver = self
	_hurtbox.collision_layer = CombatLayers.ENEMY_HURTBOX
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size + Vector2.ONE * hurtbox_margin * 2.0
	shape.shape = rect
	shape.position = size * 0.5
	_hurtbox.add_child(shape)
	add_child(_hurtbox)


func hurtbox_rect() -> Rect2:
	return Rect2(global_position, size).grow(hurtbox_margin)


## Hurtbox receiver. Only Rook's hits count (anything else is IGNORED).
func receive_hit(hit: HitInfo) -> int:
	if hit == null or not is_instance_valid(hit.attacker) or not hit.attacker is Player:
		return CombatResult.IGNORED
	trip()
	return CombatResult.HIT


## Trips the breaker (also the test entry point). Returns false while it is
## re-arming. A later trip re-emits: consumers refresh their timers.
func trip() -> bool:
	if _since_trip < rearm_time:
		return false
	_since_trip = 0.0
	trips += 1
	_flash = 0.12
	AudioManager.play_sfx(&"repeater")
	EventBus.breaker_hit.emit(circuit)
	queue_redraw()
	return true


# --- Lamp (driven by consumers) --------------------------------------------------

## Amber for `seconds`: the circuit is live (a shutter's countdown).
func show_live(seconds: float) -> void:
	_live = maxf(seconds, 0.0)
	queue_redraw()


## Pulsing amber (the clamp's teaching line points at the breakers).
func pulse(seconds: float) -> void:
	_pulse = maxf(seconds, 0.0)
	queue_redraw()


## The lamp refills over `seconds` (a clamp re-arming).
func show_recharge(seconds: float) -> void:
	_recharge = maxf(seconds, 0.0)
	_recharge_total = _recharge
	queue_redraw()


func is_lit() -> bool:
	return _live > 0.0 or _pulse > 0.0


## Lamp helper for consumers: every breaker on `p_circuit` in the tree.
static func on_circuit(tree: SceneTree, p_circuit: StringName) -> Array[Breaker]:
	var out: Array[Breaker] = []
	for n in tree.get_nodes_in_group(&"breakers"):
		if n is Breaker and (n as Breaker).circuit == p_circuit:
			out.append(n as Breaker)
	return out


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_time += delta
	_since_trip += delta
	var animating := _flash > 0.0 or _live > 0.0 or _pulse > 0.0 or _recharge > 0.0
	_flash = maxf(_flash - delta, 0.0)
	_live = maxf(_live - delta, 0.0)
	_pulse = maxf(_pulse - delta, 0.0)
	_recharge = maxf(_recharge - delta, 0.0)
	if animating:
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), FLASH if _flash > 0.0 else COLOR_BOX)
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_EDGE, false, 1.0)
	# Lever glyph: a slot and a handle, so it reads as "hit me" without text.
	var cx := size.x * 0.5
	draw_line(Vector2(cx, size.y * 0.45), Vector2(cx, size.y - 3.0), COLOR_GLYPH, 1.0)
	var up := _live > 0.0
	var handle := Vector2(cx + (3.0 if up else -3.0), size.y * 0.45 + 2.0)
	draw_line(Vector2(cx, size.y - 5.0), handle, COLOR_GLYPH, 2.0)
	# Lamp: dim idle, amber live, pulsing for the clamp's teaching line, and a
	# refill bar while a clamp recharges.
	var lamp := Rect2(size.x * 0.5 - 3.0, 2.0, 6.0, 5.0)
	var c := LAMP_DIM
	if _live > 0.0:
		c = LAMP_AMBER
	elif _pulse > 0.0:
		c = LAMP_DIM.lerp(LAMP_AMBER, 0.5 + 0.5 * sin(_time * TAU * 3.0))
	draw_rect(lamp, c)
	if _recharge > 0.0 and _recharge_total > 0.0:
		var fill := 1.0 - _recharge / _recharge_total
		draw_rect(Rect2(1.0, size.y - 2.0, (size.x - 2.0) * fill, 1.0), LAMP_AMBER)


## HitboxView hook: the hurtbox and the trip state, in global coordinates.
func debug_draw(canvas: CanvasItem) -> void:
	var r := hurtbox_rect()
	canvas.draw_rect(r, Color(1.0, 0.7, 0.28, 0.9), false, 1.0)
	var armed := "armed" if _since_trip >= rearm_time else "re-arming"
	canvas.draw_string(ThemeDB.fallback_font, r.position + Vector2(0, -2), "%s %s x%d %s" % [breaker_id, circuit, trips, armed],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)


# --- Content protocol (ContentValidator) ------------------------------------------

func content_flags() -> Dictionary:
	if circuit == &"":
		return {}
	return {"produces": ["circuit:%s" % circuit]}


## Placement standard, measured against the first solid block under the box
## (one-way platforms are ignored for the floor, but a breaker a grounded
## attack from a one-way could reach defeats the "reach it from the floor"
## read, so it warns). The one-way's span is widened by the attack's
## horizontal reach: Rook can stand at its very end and swing outwards.
func content_errors(room: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if circuit == &"":
		out.append("breaker %s has no circuit" % breaker_id)
	if breaker_id == "":
		out.append("breaker has no breaker_id")
	var pos := room_position(self, room)
	var floor_y := floor_below(room, pos.x, pos.x + size.x, pos.y + size.y)
	if floor_y == INF:
		out.append("breaker %s has no solid floor under it" % breaker_id)
		return out
	var top := pos.y - floor_y
	if top < HIGHEST_TOP - 0.5:
		out.append("breaker %s box top is at floor %d, higher than the floor %d limit (not every weapon reaches it)" % [breaker_id, int(top), int(HIGHEST_TOP)])
	var hb := Rect2(pos, size).grow(hurtbox_margin)
	var reach := grounded_reach()
	var reach_x := grounded_reach_x()
	for n in room.find_children("*", "GrayboxBlock", true, false):
		var b := n as GrayboxBlock
		if not b.one_way:
			continue
		var p := room_position(b, room)
		var band_top := p.y + reach.x
		var band_bottom := p.y + reach.y
		if hb.position.x < p.x + b.size.x + reach_x and hb.end.x > p.x - reach_x and hb.position.y < band_bottom and hb.end.y > band_top:
			out.append("WARN: breaker %s is in grounded-attack reach of one-way %s" % [breaker_id, b.name])
	return out


## Band (top, bottom) above a standing surface that a grounded light attack
## hits, read from the blade's AttackData so it follows weapon tuning.
static func grounded_reach() -> Vector2:
	var w := load(REACH_WEAPON) as WeaponData
	if w == null or w.light_chain.is_empty() or w.light_chain[0] == null:
		return GROUNDED_REACH
	var box: Rect2 = w.light_chain[0].hitbox
	return Vector2(box.position.y, box.end.y)


## How far past a standing surface's end a grounded light attack reaches:
## the hitbox's far edge, the lunge it travels until its active frames end,
## and Rook's half width (read from the same AttackData as grounded_reach).
static func grounded_reach_x() -> float:
	var w := load(REACH_WEAPON) as WeaponData
	if w == null or w.light_chain.is_empty() or w.light_chain[0] == null:
		return GROUNDED_REACH_X
	var a: AttackData = w.light_chain[0]
	return a.hitbox.end.x + a.lunge_speed * (a.startup + a.active) + PLAYER_HALF_WIDTH


## Position of `n` in `room` space, summing Node2D offsets. The validator
## checks rooms that are not in the tree, so global_position can't be used.
static func room_position(n: Node, room: Node) -> Vector2:
	var p := Vector2.ZERO
	var cur := n
	while cur != null and cur != room:
		if cur is Node2D:
			p += (cur as Node2D).position
		cur = cur.get_parent()
	return p


## Top of the first solid (not one-way) GrayboxBlock under the span x0..x1,
## at or below y, in room space. INF when there is none.
static func floor_below(room: Node, x0: float, x1: float, y: float) -> float:
	var best := INF
	for n in room.find_children("*", "GrayboxBlock", true, false):
		var b := n as GrayboxBlock
		if b.one_way:
			continue
		var p := room_position(b, room)
		if p.x < x1 and p.x + b.size.x > x0 and p.y >= y - 0.5 and p.y < best:
			best = p.y
	return best
