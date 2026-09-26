@tool
class_name WeaponPickup
extends Area2D
## A weapon found in the world (bible §42 onboarding: the campaign starts
## unarmed; the Pulse Blade hangs on a Medical Ruin rack, the Service Pistol
## spills from the Collector's cargo). Walking through it grants the weapon;
## Game.grant_weapon equips it into an empty slot and shows the one
## "WEAPON ACQUIRED" banner, so this node adds no text of its own.
## Origin is bottom-centre. The trigger is tall on purpose: Rook's feet never
## rise above -56, so he cannot jump over a 72 px trigger by accident.

enum Look { RACK, CRATE }

@export var weapon_id: String = ""
## Set when taken. "" = "got_<weapon_id>".
@export var flag_id: String = ""
@export var size: Vector2 = Vector2(16, 72):
	set(v):
		size = v.snapped(Vector2.ONE)
		_rebuild()
## Placeholder silhouette (D-026): a wall rack or a spilled cargo crate.
@export var look: Look = Look.RACK

const GLINT_PERIOD := 1.5
const METAL := Color("c9c3d6")
const FRAME := Color("4a4458")
const FRAME_LIGHT := Color("6b6380")
const ACCENT := Color("e8283c")

var _shape_node: CollisionShape2D
var _t: float = 0.0


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = CombatLayers.PLAYER_BODY
	_rebuild()
	if Engine.is_editor_hint():
		return
	# A boss reward respawned on revisit, or a rack already emptied: gone.
	if Game.has_flag(effective_flag()) or Game.state.owned_weapons.has(weapon_id):
		# D-153: NG+ carries the kit but resets the story, so the rack or drop
		# of a weapon already owned only records that it was reached (its
		# flag gates CollectorBay's exit). No grant, no banner, no SFX. Cycle
		# 0 is unchanged: an owned weapon there never sets the flag.
		if NewGamePlus.cycle() >= 1 and not Game.has_flag(effective_flag()):
			Game.set_flag(effective_flag())
		queue_free()
		return
	body_entered.connect(_on_body_entered)


func effective_flag() -> String:
	return flag_id if flag_id != "" else "got_" + weapon_id


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _shape_node == null:
		_shape_node = CollisionShape2D.new()
		add_child(_shape_node)
	var rect := RectangleShape2D.new()
	rect.size = size
	_shape_node.shape = rect
	_shape_node.position = Vector2(0, -size.y * 0.5)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if not body is Player or is_queued_for_deletion():
		return
	Game.grant_weapon(weapon_id)
	Game.set_flag(effective_flag())
	AudioManager.play_sfx(&"ability_unlock")
	HitSpark.spawn(get_parent(), global_position + Vector2(0, -16), Vector2.UP, ACCENT, 16, 120.0)
	EventBus.camera_shake_requested.emit(0.2)
	queue_free()


## Content protocol (ContentValidator._check_protocol). Must not depend on
## _ready: rooms are validated without entering the tree.
func content_flags() -> Dictionary:
	return {"produces": [effective_flag()]}


func content_errors(_room: Node) -> PackedStringArray:
	var catalog := load("res://data/catalog.tres") as ItemCatalog
	if weapon_id == "" or catalog.weapon(weapon_id) == null:
		return PackedStringArray(["WeaponPickup weapon '%s' is not in the item catalog" % weapon_id])
	return PackedStringArray()


func _draw() -> void:
	if look == Look.RACK:
		# Wall rack at chest height with the blade hung across it.
		draw_rect(Rect2(-9, -40, 18, 3), FRAME_LIGHT)
		draw_rect(Rect2(-8, -37, 2, 10), FRAME)
		draw_rect(Rect2(6, -37, 2, 10), FRAME)
		draw_rect(Rect2(-10, -34, 16, 2), METAL)
		draw_rect(Rect2(6, -35, 4, 4), ACCENT)
	else:
		# Spilled cargo crate, the pistol lying on its lid.
		draw_rect(Rect2(-10, -10, 20, 10), FRAME)
		draw_rect(Rect2(-10, -10, 20, 2), FRAME_LIGHT)
		draw_line(Vector2(-10, 0), Vector2(10, -10), FRAME_LIGHT, 1.0)
		draw_rect(Rect2(-5, -14, 9, 3), METAL)
		draw_rect(Rect2(-5, -12, 3, 4), METAL)
		draw_rect(Rect2(3, -14, 2, 2), ACCENT)
	# A glint sweeps across the weapon every GLINT_PERIOD s: readable at a glance.
	var phase := fmod(_t, GLINT_PERIOD) / 0.25
	if phase < 1.0:
		var y := -33.0 if look == Look.RACK else -13.0
		var x := lerpf(-10.0, 9.0, phase)
		draw_rect(Rect2(x, y - 1, 2, 3), Color(1, 1, 1, 0.9 * (1.0 - phase)))
