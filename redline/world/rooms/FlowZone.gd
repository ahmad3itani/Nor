@tool
class_name FlowZone
extends Area2D
## Authored combat/Flow sector (bible §6): the Redline Core only drains while
## the player is inside one. Outside = safe exploration, no pressure.
## Origin is the top-left corner.

@export var size: Vector2 = Vector2(320, 200):
	set(v):
		size = v.snapped(Vector2.ONE)
		_rebuild()
@export var label: String = "FLOW ZONE"
## Shown the first time the player ever enters any Flow Zone (onboarding).
@export var first_entry_hint: String = "HOSTILE ZONE  —  your Core drains here. Fight and move to refill it."
## Teaching zones (M7, Undercity) drain gentler: the Core drains at the mode's
## base rate times the largest drain_scale of the zones Rook is inside.
@export_range(0.1, 1.0, 0.05) var drain_scale: float = 1.0:
	set(v):
		drain_scale = v
		queue_redraw()
## Inside this zone the Core never drains below this charge, so burnout can
## never start here in any mode; the critical heartbeat still plays (the
## lesson). Only for the one "feel the empty Core" room (D-085). 0 = none.
@export_range(0.0, 100.0, 0.5) var drain_floor: float = 0.0:
	set(v):
		drain_floor = v
		queue_redraw()

var _shape_node: CollisionShape2D


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = CombatLayers.PLAYER_BODY
	_rebuild()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)


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


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		(body as Player).reactor.enter_flow(self)
		if not Game.has_flag("hint_first_flow"):
			# The Core bar is hidden until the Core first matters (M7 onboarding).
			# set_flag, never erase: erasing emits no flag_changed, so the HUD
			# and the playtest recorder would miss the reveal.
			Game.set_flag("core_hud_hidden", false)
			if first_entry_hint != "":
				Game.set_flag("hint_first_flow")
				EventBus.hint_requested.emit(first_entry_hint, 4.0)


func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		(body as Player).reactor.exit_flow(self)


## ContentValidator protocol: drain numbers must stay in their ranges even
## when a room file is edited by hand.
func content_errors(_room: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if drain_scale <= 0.0 or drain_scale > 1.0:
		out.append("drain_scale %.2f must be in (0, 1]" % drain_scale)
	if drain_floor < 0.0 or drain_floor >= 100.0:
		out.append("drain_floor %.1f must be in [0, 100)" % drain_floor)
	return out


## Debug overlay text: the label plus any non-default drain tuning.
func debug_text() -> String:
	var t := label
	if not is_equal_approx(drain_scale, 1.0):
		t += "  x%s" % str(snappedf(drain_scale, 0.01))
	if drain_floor > 0.0:
		t += "  floor %s" % str(snappedf(drain_floor, 0.1))
	return t


## HitboxView hook: tuned zones name their numbers so playtesters can see why
## the Core drains slower here.
func debug_draw(canvas: CanvasItem) -> void:
	var font := ThemeDB.fallback_font
	canvas.draw_string(font, global_position + Vector2(2, 10), debug_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.91, 0.16, 0.24, 0.9))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.91, 0.16, 0.24, 0.05))
	# Dashed top edge reads as a "sector boundary" without hiding geometry.
	var x := 0.0
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(minf(x + 6.0, size.x), 0), Color(0.91, 0.16, 0.24, 0.5), 1.0)
		x += 10.0
