class_name AmbientLife
extends Node2D
## Small life in a room (ART_DIRECTION 4.6): moths orbiting lamp and neon
## glows, rats and gulls that flee from Rook, an eel ripple on flooded
## floors, drips from ceiling undersides, steam puffs. Visual only: plain
## sprites with no collision, no Hurtbox and no group any system reads
## (EncounterDirector, RouteBot, map). Every critter sits behind enemies
## (absolute z CRITTER_Z); rats and gulls hide while a fight is on
## (EncounterDirector attackers, or a living enemy within 160 px).
##
## Caps: 8 moths, 2 rats, 4 gulls, 6 drips, 3 steam vents, scaled by
## Motion.count_scale(); nothing at ambient motion Off. Positions come from
## the room's GrayboxBlocks and glows and a seeded RandomNumberGenerator,
## never the global one, so routes and ghosts stay byte-stable.

const SPEC_PATH := "res://assets/props/life_critters.tres"
const CRITTER_Z := -1
const CAPS := {&"moth": 8, &"rat": 2, &"gull": 4, &"drip": 6, &"steam": 3}
const MOTHS_PER_GLOW := 3
const RAT_FLEE := 64.0
const GULL_FLEE := 80.0
const FIGHT_RADIUS := 160.0
const MOTH_SCARE := 48.0
const SCARY_STATES: Array[StringName] = [&"dash", &"dodge", &"melee", &"slide"]
const DRIP_GRAVITY := 380.0

var kinds: Array[StringName] = []
var room: Node2D
var tint: Color = Color.WHITE

var _spec: SpriteSheetSpec
var _frames: SpriteFrames
var _rng := RandomNumberGenerator.new()
var _seed: int = 0
## Critter records: {kind, sprite, state, ...}.
var _critters: Array[Dictionary] = []
## Falling drops: {pos: Vector2, vel: float, floor: float}.
var _drops: Array[Dictionary] = []
var _floors: Array[Rect2] = []
var _ceilings: Array[Vector2] = []
var _vents: Array[Vector2] = []
var _drip_timer: float = 1.0
var _steam_timer: float = 2.0
var _eel_timer: float = 8.0
var _built: bool = false


static func create(p_room: Node2D, p_kinds: Array[StringName], seed_value: int, p_tint: Color = Color.WHITE) -> AmbientLife:
	var life := AmbientLife.new()
	life.name = "AmbientLife"
	life.room = p_room
	life.kinds = p_kinds.duplicate()
	life.tint = p_tint
	life._seed = seed_value
	return life


## The Room a node sits in (or null).
static func room_of(n: Node) -> Node2D:
	var p := n
	while p:
		if p is Room:
			return p as Node2D
		p = p.get_parent()
	return null


## The room's player, or null.
static func player_near(n: Node) -> CharacterBody2D:
	var r := room_of(n)
	if r == null or not ("player" in r):
		return null
	var p: Variant = r.get("player")
	return p as CharacterBody2D if p is CharacterBody2D and is_instance_valid(p) else null


func _ready() -> void:
	z_as_relative = false
	z_index = CRITTER_Z
	if ResourceLoader.exists(SPEC_PATH):
		_spec = load(SPEC_PATH) as SpriteSheetSpec
		_frames = _spec.build_frames() if _spec else null
	EventBus.settings_changed.connect(rebuild)
	# Lamp and neon glows attach deferred; build after them.
	rebuild.call_deferred()


func _exit_tree() -> void:
	if EventBus.settings_changed.is_connected(rebuild):
		EventBus.settings_changed.disconnect(rebuild)


## Clears and re-places everything for the current motion level.
func rebuild() -> void:
	if not is_inside_tree():
		return
	for c in _critters:
		var s: Node = c["sprite"]
		if is_instance_valid(s):
			s.queue_free()
	_critters.clear()
	_drops.clear()
	_rng.seed = _seed
	_scan_room()
	_built = true
	if not Motion.animate_ambient():
		queue_redraw()
		return
	if kinds.has(&"moth"):
		_place_moths()
	if kinds.has(&"rat"):
		for i in cap(&"rat"):
			_add_ground(&"rat")
	if kinds.has(&"gull"):
		for i in cap(&"gull"):
			_add_ground(&"gull")
	if kinds.has(&"eel") and _frames and not _floors.is_empty():
		var s := _sprite(&"eel_ripple")
		s.visible = false
		_critters.append({"kind": &"eel", "sprite": s})
	queue_redraw()


## The live cap for `kind` at the current motion level.
static func cap(kind: StringName) -> int:
	return int(floor(int(CAPS.get(kind, 0)) * Motion.count_scale()))


func count(kind: StringName) -> int:
	var n := 0
	for c in _critters:
		if c["kind"] == kind:
			n += 1
	if kind == &"drip":
		return _drops.size()
	return n


func critter_sprites() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for c in _critters:
		if is_instance_valid(c["sprite"]):
			out.append(c["sprite"])
	return out


func _scan_room() -> void:
	_floors.clear()
	_ceilings.clear()
	_vents.clear()
	if room == null or not is_instance_valid(room):
		return
	var blocks: Array[GrayboxBlock] = []
	for n in room.find_children("*", "GrayboxBlock", true, false):
		blocks.append(n as GrayboxBlock)
	for b in blocks:
		var r := Rect2(b.global_position - global_position, b.size)
		if not b.one_way and r.size.x >= 32.0:
			_floors.append(Rect2(r.position.x + 8.0, r.position.y, r.size.x - 16.0, 0))
	# Ceiling undersides: a solid block with open floor 24+ px below it.
	for b in blocks:
		if b.one_way:
			continue
		var r := Rect2(b.global_position - global_position, b.size)
		var x := r.position.x + 8.0
		while x < r.end.x - 8.0:
			var f := _floor_under(Vector2(x, r.end.y + 1.0))
			if not is_nan(f) and f - r.end.y >= 24.0:
				_ceilings.append(Vector2(x, r.end.y))
			x += 48.0
	for n in room.find_children("*", "Decor", true, false):
		var d := n as Decor
		if d and (d.kind == Decor.Kind.PIPES or d.kind == Decor.Kind.AC_UNIT):
			_vents.append(d.global_position - global_position + Vector2(0, -d.size.y))


## The first floor top below `p` (NAN when none).
func _floor_under(p: Vector2) -> float:
	var best := NAN
	for f in _floors:
		if p.x >= f.position.x - 8.0 and p.x <= f.end.x + 8.0 and f.position.y >= p.y:
			if is_nan(best) or f.position.y < best:
				best = f.position.y
	return best


func _sprite(anim: StringName) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = _frames
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.animation = anim
	s.offset = _spec.offset_for(anim)
	s.modulate = tint
	add_child(s)
	s.play(anim)
	return s


func _place_moths() -> void:
	if _frames == null:
		return
	var left := cap(&"moth")
	for g in get_tree().get_nodes_in_group(LampGlow.GROUP):
		var glow := g as Node2D
		if left <= 0 or glow == null or not room.is_ancestor_of(glow):
			continue
		for i in mini(MOTHS_PER_GLOW, left):
			if _rng.randf() < 0.45 and i > 0:
				continue
			var s := _sprite(&"moth_flutter")
			var c := {"kind": &"moth", "sprite": s, "glow": glow, "angle": _rng.randf_range(0, TAU),
				"speed": _rng.randf_range(1.6, 3.2) * (1 if _rng.randf() < 0.5 else -1),
				"rx": _rng.randf_range(6, 14), "ry": _rng.randf_range(3, 8), "flee": 0.0, "dir": Vector2.ZERO}
			s.position = _moth_home(c)
			_critters.append(c)
			left -= 1


func _moth_home(c: Dictionary) -> Vector2:
	var glow := c["glow"] as Node2D
	if not is_instance_valid(glow):
		return (c["sprite"] as Node2D).position
	var a: float = c["angle"]
	return glow.global_position - global_position + Vector2(cos(a) * c["rx"], sin(a * 1.3) * c["ry"] + 7.0)


func _add_ground(kind: StringName) -> void:
	if _frames == null or _floors.is_empty():
		return
	var s := _sprite(&"rat_idle" if kind == &"rat" else &"gull_idle")
	var c := {"kind": kind, "sprite": s, "state": &"idle", "vel": Vector2.ZERO, "wait": 0.0, "timer": _rng.randf_range(1.0, 4.0)}
	_critters.append(c)
	_respawn_ground(c)


func _respawn_ground(c: Dictionary) -> void:
	var s := c["sprite"] as AnimatedSprite2D
	var pl := player_near(self)
	for attempt in 8:
		var f := _floors[_rng.randi() % _floors.size()]
		var p := Vector2(_rng.randf_range(f.position.x, f.end.x), f.position.y)
		if pl and (pl.global_position - global_position).distance_to(p) < FIGHT_RADIUS and attempt < 7:
			continue
		s.position = p
		break
	s.flip_h = _rng.randf() < 0.5
	s.offset = _spec.offset_for(s.animation, s.flip_h)
	s.visible = true
	c["state"] = &"idle"
	c["vel"] = Vector2.ZERO
	s.play(&"rat_idle" if c["kind"] == &"rat" else &"gull_idle")


## True while rats and gulls should keep out of sight: a fight is on.
func fight_on(near: Vector2) -> bool:
	for d in get_tree().get_nodes_in_group(&"encounter_director"):
		if room.is_ancestor_of(d) and d.has_method("active_attackers") and int(d.call("active_attackers")) > 0:
			return true
	for e in get_tree().get_nodes_in_group(&"enemies"):
		var en := e as Node2D
		if en == null or not room.is_ancestor_of(en):
			continue
		if en.has_method("is_dead") and en.call("is_dead"):
			continue
		if (en.global_position - global_position).distance_to(near) <= FIGHT_RADIUS:
			return true
	return false


func _process(delta: float) -> void:
	if not _built or not Motion.animate_ambient():
		return
	var pl := player_near(self)
	var ppos := pl.global_position - global_position if pl else Vector2.INF
	var scary := false
	if pl and pl.has_method("current_state_id"):
		scary = SCARY_STATES.has(pl.call("current_state_id")) or pl.velocity.length() > 220.0
	for c in _critters:
		var s := c["sprite"] as AnimatedSprite2D
		if not is_instance_valid(s):
			continue
		match c["kind"]:
			&"moth":
				_tick_moth(c, s, ppos, scary, delta)
			&"rat", &"gull":
				_tick_ground(c, s, ppos, delta)
			&"eel":
				_tick_eel(s, delta)
	_tick_drips(delta)
	_tick_steam(delta)


func _tick_moth(c: Dictionary, s: AnimatedSprite2D, ppos: Vector2, scary: bool, delta: float) -> void:
	if c["flee"] > 0.0:
		c["flee"] = c["flee"] - delta
		s.position += c["dir"] * 70.0 * delta
		if c["flee"] <= 1.0:
			s.visible = false
		if c["flee"] <= 0.0:
			s.visible = true
			s.position = _moth_home(c)
		return
	c["angle"] = c["angle"] + c["speed"] * delta
	var home := _moth_home(c)
	s.position = s.position.lerp(home + Vector2(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.6, 0.6)), minf(1.0, delta * 8.0))
	if scary and s.position.distance_to(ppos) < MOTH_SCARE:
		c["flee"] = 2.5
		c["dir"] = (s.position - ppos).normalized() + Vector2(0, -0.6)


func _tick_ground(c: Dictionary, s: AnimatedSprite2D, ppos: Vector2, delta: float) -> void:
	var rat: bool = c["kind"] == &"rat"
	if c["state"] == &"gone":
		c["wait"] = c["wait"] - delta
		if c["wait"] <= 0.0 and not fight_on(s.position):
			_respawn_ground(c)
		return
	if fight_on(s.position):
		s.visible = false
		c["state"] = &"gone"
		c["wait"] = _rng.randf_range(4.0, 8.0)
		return
	var dist := s.position.distance_to(ppos)
	if c["state"] == &"idle":
		if dist < (RAT_FLEE if rat else GULL_FLEE):
			var away := signf(s.position.x - ppos.x)
			if away == 0.0:
				away = 1.0
			c["state"] = &"flee"
			c["vel"] = Vector2(away * 95.0, 0.0) if rat else Vector2(away * 70.0, -60.0)
			s.flip_h = away < 0.0
			s.play(&"rat_run" if rat else &"gull_fly")
			s.offset = _spec.offset_for(s.animation, s.flip_h)
			return
		c["timer"] = c["timer"] - delta
		if not rat and c["timer"] <= 0.0:
			c["timer"] = _rng.randf_range(2.0, 5.0)
			s.play(&"gull_peck")
		elif not rat and s.animation == &"gull_peck" and not s.is_playing():
			s.play(&"gull_idle")
		return
	# Fleeing: rats run along the floor, gulls arc up and away.
	var v: Vector2 = c["vel"]
	if not rat:
		v.y -= 20.0 * delta
		c["vel"] = v
	s.position += v * delta
	if s.position.distance_to(ppos) > 220.0:
		s.visible = false
		c["state"] = &"gone"
		c["wait"] = _rng.randf_range(15.0, 30.0) if rat else _rng.randf_range(20.0, 40.0)


func _tick_eel(s: AnimatedSprite2D, delta: float) -> void:
	if s.visible and not s.is_playing():
		s.visible = false
	_eel_timer -= delta
	if _eel_timer > 0.0:
		return
	_eel_timer = _rng.randf_range(10.0, 20.0)
	var f := _floors[_rng.randi() % _floors.size()]
	s.position = Vector2(_rng.randf_range(f.position.x, f.end.x), f.position.y)
	s.visible = true
	s.play(&"eel_ripple")
	s.frame = 0


func _tick_drips(delta: float) -> void:
	if not kinds.has(&"drip") or _ceilings.is_empty():
		return
	_drip_timer -= delta
	if _drip_timer <= 0.0:
		_drip_timer = _rng.randf_range(1.5, 4.5)
		if _drops.size() < cap(&"drip"):
			var at := _ceilings[_rng.randi() % _ceilings.size()]
			var fl := _floor_under(at + Vector2(0, 1))
			if not is_nan(fl):
				_drops.append({"pos": at, "vel": 0.0, "floor": fl})
	var i := _drops.size() - 1
	while i >= 0:
		var d := _drops[i]
		d["vel"] = d["vel"] + DRIP_GRAVITY * delta
		var p: Vector2 = d["pos"] + Vector2(0, d["vel"] * delta)
		d["pos"] = p
		if p.y >= d["floor"]:
			VfxOneShot.spawn(self, &"splash", &"drip", Vector2(p.x, d["floor"]), {"tint": tint, "z_index": 0})
			_drops.remove_at(i)
		i -= 1
	queue_redraw()


func _tick_steam(delta: float) -> void:
	if not kinds.has(&"steam") or cap(&"steam") <= 0:
		return
	_steam_timer -= delta
	if _steam_timer > 0.0:
		return
	_steam_timer = _rng.randf_range(2.5, 5.0)
	var spots := _vents
	if spots.is_empty():
		for k in mini(3, _floors.size()):
			var f := _floors[posmod(k * 7919 + _seed, _floors.size())]
			spots.append(Vector2(f.position.x + f.size.x * 0.5, f.position.y))
		_vents = spots
	if spots.is_empty():
		return
	var at := spots[_rng.randi() % mini(spots.size(), cap(&"steam"))]
	VfxOneShot.spawn(self, &"steam", &"puff", at, {"tint": Color(1, 1, 1, 0.5), "z_index": 0})


func _draw() -> void:
	for d in _drops:
		var p: Vector2 = d["pos"]
		draw_rect(Rect2(p.floor(), Vector2(1, 2)), Color(tint, 0.8))
