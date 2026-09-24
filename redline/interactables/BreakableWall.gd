@tool
class_name BreakableWall
extends StaticBody2D
## Solid wall that breaks after enough damage (bible §21 breakable walls,
## §22 destruction). Breaking is saved by persist_id. Its surface shows
## faint cracks: secrets are hinted, never invisible. Origin: top-left.

@export var size: Vector2 = Vector2(16, 48):
	set(v):
		size = v
		_rebuild()
@export var persist_id: String = ""
@export var max_health: float = 30.0
## Only guard-breaking attacks (heavies, spikes) crack it.
@export var needs_heavy: bool = false
@export var scrap_inside: int = 0

var health: float
var _shape_node: CollisionShape2D
var _hurtbox: Hurtbox
var _flash: float = 0.0


func _ready() -> void:
	collision_layer = CombatLayers.WORLD
	collision_mask = 0
	health = max_health
	_rebuild()
	if Engine.is_editor_hint():
		return
	if Game.is_collected(persist_id):
		queue_free()
		return
	_hurtbox = Hurtbox.new()
	_hurtbox.receiver = self
	_hurtbox.collision_layer = CombatLayers.ENEMY_HURTBOX
	var hs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size + Vector2(4, 4)
	hs.shape = r
	hs.position = size * 0.5
	_hurtbox.add_child(hs)
	add_child(_hurtbox)


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _shape_node == null:
		_shape_node = CollisionShape2D.new()
		add_child(_shape_node)
	var rect := RectangleShape2D.new()
	rect.size = size
	_shape_node.shape = rect
	_shape_node.position = size * 0.5
	queue_redraw()


func receive_hit(hit: HitInfo) -> int:
	if needs_heavy and not hit.attack.breaks_guard:
		_flash = 0.08
		queue_redraw()
		AudioManager.play_sfx(&"block")
		return CombatResult.BLOCKED
	health -= hit.damage() * Game.circuit_mult(&"environmental_damage")
	_flash = 0.08
	queue_redraw()
	if health <= 0.0:
		_break()
	return CombatResult.HIT


func _break() -> void:
	Game.mark_collected(persist_id)
	AudioManager.play_sfx(&"wall_break")
	EventBus.camera_shake_requested.emit(0.2)
	var center := global_position + size * 0.5
	for i in 3:
		HitSpark.spawn(get_parent(), center + Vector2(0, (i - 1) * size.y * 0.3), Vector2(randf_range(-1, 1), -1), Color("8a8398"), 10, 140.0)
	if scrap_inside > 0:
		ScrapPickup.burst(get_parent(), center, scrap_inside)
	EventBus.secret_found.emit(persist_id)
	queue_free()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		queue_redraw()


func _draw() -> void:
	var base := GrayboxBlock.COLOR_SOLID.lightened(0.06)
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE if _flash > 0.0 else base)
	# Hairline cracks: readable to a curious eye, not a flashing marker.
	var crack := Color(0, 0, 0, 0.35)
	var y := 6.0
	while y < size.y - 4.0:
		draw_line(Vector2(size.x * 0.3, y), Vector2(size.x * 0.6, y + 5.0), crack, 1.0)
		draw_line(Vector2(size.x * 0.6, y + 5.0), Vector2(size.x * 0.4, y + 10.0), crack, 1.0)
		y += 16.0
