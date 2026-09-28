class_name PowerFlourish
extends Node2D
## The "power gained" beat (presentation overhaul T06; the hook the later
## power-effects + upgrades phase reuses): a ring shockwave, Pulse motes
## streaming into Rook's seam, and for weapons the weapon sprite rising and
## flashing into him. Kinds are data (KINDS), so a new power adds an entry,
## not code:
##
##   PowerFlourish.spawn(room, at, &"circuit", player)
##   PowerFlourish.spawn(room, at, &"weapon", player, {"weapon_id": "scattergun"})
##
## Flash-safe: rings and motes are tinted (value-scaled under flash
## reduction), the weapon "flash" is an overbright modulate that flash
## reduction removes, and nothing draws a full-white frame. Without the
## shockwave sheet the kind's old HitSpark burst plays instead. Visual only:
## no collision; screen shake stays with the callers (EventBus only).

## kind -> {rings, ring_gap (s), motes, item (draws the weapon sprite),
## palette_key (ring + mote red), fallback_color/amount/speed (the old
## HitSpark placeholder), duration (s)}
const KINDS := {
	&"circuit": {"rings": 1, "ring_gap": 0.0, "motes": 8, "item": false, "palette_key": &"accent",
		"fallback_color": Color("e8283c"), "fallback_amount": 16, "fallback_speed": 120.0, "duration": 0.7},
	&"weapon": {"rings": 1, "ring_gap": 0.0, "motes": 6, "item": true, "palette_key": &"accent",
		"fallback_color": Color("e8283c"), "fallback_amount": 16, "fallback_speed": 120.0, "duration": 0.9},
	&"ability": {"rings": 2, "ring_gap": 0.14, "motes": 12, "item": false, "palette_key": &"accent",
		"fallback_color": Color("e8283c"), "fallback_amount": 24, "fallback_speed": 160.0, "duration": 0.9},
}
const WEAPON_SPRITE := "res://assets/rook/weapons/weapon_%s.png"
const ITEM_RISE := 14.0
const ITEM_RISE_TIME := 0.4
const ITEM_DIVE_TIME := 0.22
## The weapon glows this bright while rising (1.0 under flash reduction).
const ITEM_FLASH := 1.6

## kind -> live flourishes (so a pickup can skip its own placeholder burst).
static var _live: Dictionary = {}

var kind: StringName = &""
var spec: Dictionary = {}
var target: Node2D
var item: Sprite2D
## True when the placeholder HitSpark burst played instead of the sprites.
var placeholder: bool = false
var _age: float = 0.0
var _rings_left: int = 0
var _ring_timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _counted: bool = false


static func spawn(parent: Node, at: Vector2, p_kind: StringName, p_target: Node2D = null, opts: Dictionary = {}) -> PowerFlourish:
	if parent == null or not is_instance_valid(parent) or not KINDS.has(p_kind):
		return null
	var f := PowerFlourish.new()
	f.name = "PowerFlourish"
	f.kind = p_kind
	f.spec = KINDS[p_kind]
	f.target = p_target
	f.position = at
	f.z_index = 5
	f._rng.seed = hash([p_kind, at.round()])
	parent.add_child(f)
	f._start(opts)
	return f


static func live_count(p_kind: StringName) -> int:
	return int(_live.get(p_kind, 0))


func _enter_tree() -> void:
	if not _counted:
		_live[kind] = live_count(kind) + 1
		_counted = true


func _exit_tree() -> void:
	if _counted:
		_live[kind] = maxi(0, live_count(kind) - 1)
		_counted = false


func _start(opts: Dictionary) -> void:
	_rings_left = int(spec["rings"])
	if not _ring():
		placeholder = true
		_rings_left = 0
		HitSpark.spawn(get_parent(), position, Vector2.UP, spec["fallback_color"], int(spec["fallback_amount"]),
			float(spec["fallback_speed"]))
	PulseMotes.spawn(get_parent(), position, target, int(spec["motes"]), _rng, PulseMotes.TINT)
	if bool(spec["item"]):
		var path := WEAPON_SPRITE % str(opts.get("weapon_id", ""))
		if ResourceLoader.exists(path):
			item = Sprite2D.new()
			item.name = "Item"
			item.texture = load(path) as Texture2D
			item.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			add_child(item)


## One ring; false when the shockwave sheet cannot spawn it.
func _ring() -> bool:
	if _rings_left <= 0:
		return false
	_rings_left -= 1
	_ring_timer = float(spec["ring_gap"])
	var fx := VfxOneShot.spawn(get_parent(), &"shockwave", &"ring", position, {"palette_key": spec["palette_key"]})
	return fx != null


func _process(delta: float) -> void:
	_age += delta
	if _age >= float(spec["duration"]):
		queue_free()
		return
	if _rings_left > 0:
		_ring_timer -= delta
		if _ring_timer <= 0.0:
			_ring()
	if item:
		_move_item()


## The weapon rises and brightens, then dives into Rook's seam and shrinks.
func _move_item() -> void:
	var glow := 1.0 if Settings.flash_reduction else ITEM_FLASH
	if _age < ITEM_RISE_TIME:
		var t := _age / ITEM_RISE_TIME
		item.position = Vector2(0, -ITEM_RISE * (1.0 - (1.0 - t) * (1.0 - t))).round()
		var g := lerpf(1.0, glow, t)
		item.modulate = Color(g, g, g, 1.0)
		return
	var k := clampf((_age - ITEM_RISE_TIME) / ITEM_DIVE_TIME, 0.0, 1.0)
	if k >= 1.0:
		item.visible = false
		return
	var start := Vector2(0, -ITEM_RISE)
	var goal := start
	if is_instance_valid(target) and target.is_inside_tree():
		goal = to_local(target.global_position + PulseMotes.SEAM_OFFSET)
	item.position = start.lerp(goal, k * k).round()
	item.scale = Vector2.ONE * lerpf(1.0, 0.5, k)
	item.modulate = Color(glow, glow, glow, 1.0 - k * 0.5)
