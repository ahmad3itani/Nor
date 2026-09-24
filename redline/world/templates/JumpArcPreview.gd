@tool
class_name JumpArcPreview
extends Node2D
## Editor-only level-design gizmo: drop it on a ledge to see where each
## technique really lands (recorded arcs, TraversalMetrics), including the
## body width. Hidden in the running game.

@export var show_run_jump: bool = true:
	set(v):
		show_run_jump = v
		queue_redraw()
@export var show_slide_jump: bool = true:
	set(v):
		show_slide_jump = v
		queue_redraw()
@export var show_dodge_jump: bool = true:
	set(v):
		show_dodge_jump = v
		queue_redraw()
@export var show_dash_jump: bool = false:
	set(v):
		show_dash_jump = v
		queue_redraw()
@export_enum("Right:1", "Left:-1") var facing: int = 1:
	set(v):
		facing = v
		queue_redraw()

const COLORS := {"run_jump": Color(1, 1, 1, 0.8), "slide_jump": Color("58e0e8"), "dodge_jump": Color("ffcf5a"), "dash_jump": Color("e8283c")}


func _ready() -> void:
	visible = Engine.is_editor_hint()


func arcs() -> Dictionary:
	var m := load(RoomTemplate.METRICS_PATH) as TraversalMetrics
	var out := {}
	for t in TraversalMetrics.TECHNIQUES:
		if get("show_" + t):
			var pts := PackedVector2Array()
			for p in m.trajectory(t):
				pts.append(Vector2(p.x * facing, p.y))
			out[t] = pts
	return out


func _draw() -> void:
	var arcs_now := arcs()
	var half := 6.0
	for t: String in arcs_now:
		var pts: PackedVector2Array = arcs_now[t]
		if pts.size() < 2:
			continue
		var c: Color = COLORS[t]
		draw_polyline(pts, c, 1.0)
		# Feet band: the collider's width around the path's landing point.
		var land := pts[pts.size() - 1]
		draw_line(land + Vector2(-half, 0), land + Vector2(half, 0), c, 2.0)
		draw_string(ThemeDB.fallback_font, land + Vector2(4, -4), t.replace("_", " "), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, c)
