class_name HitboxView
extends Node2D
## Hitbox visualization (bible §34): hurtboxes in blue, live attack hitboxes
## in red (enemies and Rook), drawn in world space over everything.
## Toggled from the dev console; debug builds only.

const HURT := Color(0.5, 0.85, 1.0, 0.8)
const HIT := Color(1.0, 0.23, 0.31, 0.9)


func _ready() -> void:
	z_index = 100
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var room := SceneRouter.current_room
	if room == null:
		return
	for n in room.find_children("*", "Hurtbox", true, false):
		var h := n as Hurtbox
		for s in h.get_children():
			if s is CollisionShape2D and (s as CollisionShape2D).shape is RectangleShape2D:
				var size := ((s as CollisionShape2D).shape as RectangleShape2D).size
				draw_rect(Rect2((s as Node2D).global_position - size * 0.5, size), HURT, false, 1.0)
	for n in room.find_children("*", "Enemy", true, false):
		var e := n as Enemy
		if e.current_attack and e.ai == Enemy.AI.ACTIVE and not e.current_attack.projectile:
			draw_rect(e.current_attack.world_hitbox(e.global_position, e.facing), HIT, false, 1.0)
	var r := room as Room
	if r and is_instance_valid(r.player) and r.player.combat.current_attack:
		draw_rect(r.player.combat.current_attack.world_hitbox(r.player.global_position, r.player.facing), HIT, false, 1.0)
