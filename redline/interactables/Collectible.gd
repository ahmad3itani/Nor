@tool
class_name Collectible
extends Area2D
## Persistent pickup (bible §21): Memory Fragment, Core Shard or a Scrap
## bundle. Its `persist_id` is remembered in the save so it never respawns.

enum Kind { SCRAP_BUNDLE, MEMORY_FRAGMENT, CORE_SHARD }

@export var persist_id: String = ""
@export var kind: Kind = Kind.SCRAP_BUNDLE:
	set(v):
		kind = v
		queue_redraw()
@export var scrap_amount: int = 25
@export var fragment: MemoryFragmentData

var _t: float = 0.0
## NG+ (R09.2): a Core Shard spot found in an earlier cycle draws a dim
## "recovered" husk (no pickup, no sound) instead of vanishing, so the spot
## still reads as found.
var _husk: bool = false


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
			_husk = true
			collision_mask = 0
			monitoring = false
			return
		queue_free()
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
			EventBus.hint_requested.emit("CORE SHARD  —  Core Capacity +1", 3.0)
	# After the counts change, so listeners (arcs, telemetry) read the new totals.
	EventBus.collectible_taken.emit(persist_id, kind)
	AudioManager.play_sfx(&"collect")
	HitSpark.spawn(get_parent(), global_position + Vector2(0, -9), Vector2.UP, _color(), 14, 90.0)
	queue_free()


func _color() -> Color:
	match kind:
		Kind.MEMORY_FRAGMENT:
			return Color("9fd8ff")
		Kind.CORE_SHARD:
			return Color("e8283c")
	return Color("ffd36b")


func _draw() -> void:
	var bob := sin(_t * 2.5) * 2.0
	var c := _color()
	if _husk:
		# The empty socket of a recovered shard: an outline, no glint, no bob.
		c.a = 0.35
		draw_rect(Rect2(-3, -14, 6, 8), c, false, 1.0)
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
