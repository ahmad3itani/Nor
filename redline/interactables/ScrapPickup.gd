class_name ScrapPickup
extends Node2D
## Scrap from kills and breakables. Pops out, then homes onto Rook after a
## short delay so collecting never interrupts movement (pillar §2.1).

const HOME_DELAY := 0.35
const COLLECT_DISTANCE := 10.0
const COLOR := Color("ffd36b")

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


func _draw() -> void:
	var s := 2.0 if value == 1 else 3.0
	draw_rect(Rect2(Vector2(-s, -s) * 0.5, Vector2(s, s)), COLOR)
