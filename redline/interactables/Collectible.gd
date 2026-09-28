@tool
class_name Collectible
extends Area2D
## Persistent pickup (bible §21): Memory Fragment, Core Shard, a Scrap
## bundle or a Schematic (D-184). Its `persist_id` is remembered in the save
## so it never respawns.

## Append only: scenes store the index (SCHEMATIC = 3).
enum Kind { SCRAP_BUNDLE, MEMORY_FRAGMENT, CORE_SHARD, SCHEMATIC }

## The PW4 pickup sheet, when it exists (else the code-drawn plate).
const SCHEMATIC_SHEET := "schematic_pickup"

@export var persist_id: String = ""
@export var kind: Kind = Kind.SCRAP_BUNDLE:
	set(v):
		kind = v
		queue_redraw()
@export var scrap_amount: int = 25
@export var fragment: MemoryFragmentData
## SCHEMATIC: the SchematicList id; pickup sets sch_<id>. Persist ids are
## "schem_<id>" (never the sch_ flag prefix).
@export var schematic_id: String = ""

var _t: float = 0.0
## NG+ (R09.2): a Core Shard spot found in an earlier cycle draws a dim
## "recovered" husk (no pickup, no sound) instead of vanishing, so the spot
## still reads as found.
var _husk: bool = false


## One rule for every secret count (repair 3): Scrap stashes and schematics
## are the loot inside secrets, never secrets themselves. SliceStats,
## DemoRules and the tests all ask here.
static func counts_as_secret(k: int) -> bool:
	return k != Kind.SCRAP_BUNDLE and k != Kind.SCHEMATIC


func schematic_flag() -> String:
	return "sch_" + schematic_id


func _make_husk() -> void:
	_husk = true
	collision_mask = 0
	monitoring = false


## Node content protocol: a schematic produces its sch_ flag.
func content_flags() -> Dictionary:
	if kind == Kind.SCHEMATIC and schematic_id != "":
		return {"produces": [schematic_flag()]}
	return {}


func content_errors(_room: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if kind != Kind.SCHEMATIC:
		return out
	if schematic_id == "" or not SchematicList.shared().has_id(schematic_id):
		out.append("schematic '%s' is not in data/upgrades/schematics.tres" % schematic_id)
	elif persist_id != "schem_" + schematic_id:
		out.append("a schematic's persist_id is 'schem_%s' (has '%s')" % [schematic_id, persist_id])
	return out


func _ready() -> void:
	collision_layer = 0
	collision_mask = CombatLayers.PLAYER_BODY
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12, 14)
	shape.shape = rect
	shape.position = Vector2(0, -9)
	add_child(shape)
	if Engine.is_editor_hint():
		return
	if Game.is_collected(persist_id):
		if kind == Kind.CORE_SHARD and NewGamePlus.cycle() >= 1:
			_make_husk()
			return
		queue_free()
		return
	# NG+ (repair 2): sch_ carries but the schem_<id> collected id does not,
	# so a schematic found in an earlier cycle is a husk: no pickup, no banner.
	if kind == Kind.SCHEMATIC and schematic_id != "" and Game.has_flag(schematic_flag()):
		_make_husk()
		return
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _husk:
		return
	_t += delta
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if not body is Player:
		return
	Game.mark_collected(persist_id)
	match kind:
		Kind.SCRAP_BUNDLE:
			# R09.2: a secret stash refilled by NG+ pays a share of its Scrap.
			var amount := NewGamePlus.stash_payout(scrap_amount) if NewGamePlus.cycle() >= 1 and NewGamePlus.is_secret_bundle(self) else scrap_amount
			if amount > 0:
				ScrapPickup.burst(get_parent(), global_position + Vector2(0, -8), amount)
		Kind.MEMORY_FRAGMENT:
			if fragment and not Game.state.memory_fragments.has(fragment.id):
				Game.state.memory_fragments.append(fragment.id)
			EventBus.memory_fragment_found.emit(fragment)
		Kind.CORE_SHARD:
			Game.state.core_shards += 1
			EventBus.hint_requested.emit(Loc.t("CORE SHARD  —  Core Capacity +1"), 3.0)
		Kind.SCHEMATIC:
			Game.set_flag(schematic_flag())
			var nm := SchematicList.shared().name_of(schematic_id)
			EventBus.hint_requested.emit(Loc.f("SCHEMATIC FOUND  —  {name}", {"name": Loc.t(nm) if nm != "" else schematic_id}), 4.0)
	# After the counts change, so listeners (arcs, telemetry) read the new totals.
	EventBus.collectible_taken.emit(persist_id, kind)
	AudioManager.play_sfx(&"collect")
	_take_vfx(body)
	queue_free()


## Presentation (T06): the pickup's colour streams into Rook as Pulse motes;
## the old sparks are the placeholder.
func _take_vfx(body: Node2D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(persist_id)
	if PulseMotes.spawn(get_parent(), global_position + Vector2(0, -9), body, 8, rng, _color()) == null:
		HitSpark.spawn(get_parent(), global_position + Vector2(0, -9), Vector2.UP, _color(), 14, 90.0)


func _color() -> Color:
	match kind:
		Kind.MEMORY_FRAGMENT:
			return Color("9fd8ff")
		Kind.CORE_SHARD:
			return Color("e8283c")
		Kind.SCHEMATIC:
			return Color("d9a25f")
	return Color("ffd36b")


## The sprite and its tint (T06): scrap takes Palette currency, a memory
## shard its own colour (_color, as before), a Core shard Palette accent.
func art() -> Array:
	match kind:
		Kind.MEMORY_FRAGMENT:
			return [&"memory_shard", _color()]
		Kind.CORE_SHARD:
			return [&"core_shard", Palette.color(&"accent")]
		Kind.SCHEMATIC:
			return [&"schematic", _color()]
	return [&"scrap_spin", Palette.color(&"currency")]


func _draw() -> void:
	var bob := sin(_t * 2.5) * 2.0
	var c := _color()
	if _husk:
		# The empty socket of a recovered shard (or the plate's outline): no
		# glint, no bob.
		c.a = 0.35
		if kind == Kind.SCHEMATIC:
			draw_rect(Rect2(-6, -15, 12, 9), c, false, 1.0)
		else:
			draw_rect(Rect2(-3, -14, 6, 8), c, false, 1.0)
		return
	if kind == Kind.SCHEMATIC:
		if not _draw_sheet(bob):
			_draw_plate(bob)
		return
	var a := art()
	if ScrapPickup.draw_art(self, a[0], _t, a[1], Vector2(0, roundf(-9.0 + bob))):
		return
	match kind:
		Kind.MEMORY_FRAGMENT:
			var pts := PackedVector2Array([Vector2(0, -16 + bob), Vector2(5, -9 + bob), Vector2(0, -2 + bob), Vector2(-5, -9 + bob)])
			draw_colored_polygon(pts, c)
			draw_rect(Rect2(-1, -10 + bob, 2, 2), Color.WHITE)
		Kind.CORE_SHARD:
			draw_rect(Rect2(-3, -14 + bob, 6, 8), c)
			draw_rect(Rect2(-1, -12 + bob, 2, 4), Color.WHITE)
		_:
			for i in 3:
				draw_rect(Rect2(-5 + i * 3, -8 - (i % 2) * 3 + bob, 3, 3), c)



## [SpriteSheetSpec, Texture2D] once looked up (per instance: no static
## Resource cache outlives the scene).
var _sheet: Array = []


## The PW4 sheet (SpriteSheetSpec at assets/props/<SCHEMATIC_SHEET>.tres),
## first animation, when it exists. False = draw the code plate.
func _draw_sheet(bob: float) -> bool:
	if _sheet.is_empty():
		var path := "res://assets/props/%s.tres" % SCHEMATIC_SHEET
		var sp: SpriteSheetSpec = load(path) as SpriteSheetSpec if ResourceLoader.exists(path) else null
		_sheet = [sp, sp.load_texture() if sp else null]
	var pair: Array = _sheet
	var spec := pair[0] as SpriteSheetSpec
	var tex := pair[1] as Texture2D
	if spec == null or tex == null or spec.animations.is_empty():
		return false
	var a := spec.animations[0]
	var frame := a.first_frame + int(_t * a.fps) % maxi(1, a.frame_count)
	var cell := Vector2(spec.cell_size)
	var src := Rect2(Vector2(frame * cell.x, a.row * cell.y), cell)
	var o := Vector2(spec.origin_for(a.name))
	draw_texture_rect_region(tex, Rect2((Vector2(0, roundf(bob)) - o).round(), cell), src)
	return true


## The code-drawn schematic (placeholder until the PW4 sheet): a folded
## brass plate with an etched pattern, corner rivets, a soft ember glow
## under it and a glint that crosses it every couple of seconds. Pixel
## steps only (no smooth shapes), dark outline first, like the pickup sheet.
func _draw_plate(bob: float) -> void:
	var y := roundf(-15.0 + bob)
	var base := _color()
	var dark := base.darkened(0.62)
	var mid := base.darkened(0.25)
	var hi := base.lightened(0.35)
	# Glow: two stepped halos that breathe.
	var breathe := 0.5 + 0.5 * sin(_t * 2.2)
	var glow := Color(base.r, base.g * 0.8, base.b * 0.5, 0.10 + 0.08 * breathe)
	draw_rect(Rect2(-9, y - 2, 18, 13), glow)
	draw_rect(Rect2(-8, y - 3, 16, 15), Color(glow, glow.a * 0.6))
	# Outline, body, a darker folded corner.
	draw_rect(Rect2(-7, y - 1, 14, 11), dark)
	draw_rect(Rect2(-6, y, 12, 9), mid)
	draw_rect(Rect2(-6, y, 12, 1), hi)
	draw_rect(Rect2(-6, y, 1, 9), base)
	draw_rect(Rect2(3, y + 6, 3, 3), dark)
	draw_rect(Rect2(3, y + 6, 2, 2), base)
	# The etched pattern: a gear-tooth line and two traces.
	var etch := dark.lightened(0.1)
	draw_rect(Rect2(-4, y + 2, 7, 1), etch)
	draw_rect(Rect2(-4, y + 4, 4, 1), etch)
	draw_rect(Rect2(1, y + 4, 1, 3), etch)
	for i in 3:
		draw_rect(Rect2(-4 + i * 2, y + 6, 1, 1), etch)
	# Rivets.
	for p in [Vector2(-5, y + 1), Vector2(4, y + 1), Vector2(-5, y + 7)]:
		draw_rect(Rect2(p, Vector2.ONE), hi)
	# The glint: a 2 px diagonal that sweeps across, then rests.
	var phase := fmod(_t, 2.4) / 0.6
	if phase < 1.0:
		var gx := roundf(lerpf(-7.0, 7.0, phase))
		for k in 3:
			var px := gx + k - 1
			if px >= -6.0 and px <= 5.0:
				draw_rect(Rect2(px, y + 1 + k * 2, 1, 2), Color(1, 0.95, 0.8, 0.8))
