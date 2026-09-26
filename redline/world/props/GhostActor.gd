class_name GhostActor
extends Node2D
## A challenge ghost drawn in the room (M9 D2 §4.4): a Rook-sized silhouette
## from a GhostPlayback, visual only (no Area2D, never collides). Challenges
## adds one per ghost to each run room and calls show_frame() every counted
## frame; the actor hides while its sample is in another room.
##
## Colour-blind safe: the two ghosts differ by tag text and outline pattern
## (personal best solid, rig ghost dashed), never by colour alone. It never
## flickers under Settings.flash_reduction; high contrast draws a 2 px
## outline with no fill.

const VISUAL := preload("res://player/animation/PlayerPlaceholderVisual.gd")
const LOC_FIELDS := {}
const STAND := Vector2(12, 28)
const LOW := Vector2(12, 16)
const FILL_ALPHA := 0.35

var playback: GhostPlayback
## The room this actor lives in (its own samples elsewhere hide it).
var room_path: String = ""
var _sample: Dictionary = {}
var _time: float = 0.0


func _init(p_playback: GhostPlayback = null, p_room_path: String = "") -> void:
	playback = p_playback
	room_path = p_room_path
	z_index = 5
	visible = false


func _process(delta: float) -> void:
	_time += delta
	if visible and not Settings.flash_reduction:
		queue_redraw()


## Moves to the ghost's sample at clock frame `f`; hidden when that sample is
## in another room (or there is none).
func show_frame(f: int) -> void:
	_sample = playback.frame_at(f) if playback else {}
	visible = not _sample.is_empty() and str(_sample.get("room", "")) == room_path
	if visible:
		position = Vector2(float(_sample["x"]), float(_sample["y"]))
		queue_redraw()


func tag_text() -> String:
	return Loc.t("PB") if playback == null or playback.kind == "pb" else Loc.t("RIG")


func _draw() -> void:
	if _sample.is_empty():
		return
	var flags := int(_sample.get("flags", 0))
	var size := LOW if flags & GhostData.FLAG_LOW else STAND
	var rect := Rect2(Vector2(-size.x * 0.5, -size.y), size)
	var state := GhostCodec.state_id(int(_sample.get("state", GhostCodec.UNKNOWN_STATE)))
	var col: Color = VISUAL.STATE_COLORS.get(state, Color.WHITE)
	# A slow breathe keeps the ghost readable over busy backdrops; static
	# under flash reduction (§24).
	var a := 1.0 if Settings.flash_reduction else 0.85 + 0.15 * sin(_time * 3.0)
	var hc := Settings.high_contrast
	if not hc:
		draw_rect(rect, Color(col, FILL_ALPHA * a))
	var width := 2.0 if hc else 1.0
	var outline := Color(col, a)
	if playback == null or playback.kind == "pb":
		draw_rect(rect, outline, false, width)
	else:
		_dashed_rect(rect, outline, width)
	# Facing mark (a visor tick), so the ghost's direction reads at a glance.
	var fx := rect.end.x - 3.0 if flags & GhostData.FLAG_RIGHT else rect.position.x + 1.0
	draw_rect(Rect2(fx, rect.position.y + 4.0, 2.0, 2.0), outline)
	var font := ThemeDB.fallback_font
	var tag := tag_text()
	var w := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x
	draw_string(font, Vector2(-w * 0.5, rect.position.y - 3.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, outline)
	if bool(_sample.get("finished", false)):
		draw_line(Vector2(-6, 2), Vector2(6, 2), outline, width)


func _dashed_rect(r: Rect2, c: Color, width: float) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in 4:
		draw_dashed_line(pts[i], pts[i + 1], c, width, 3.0)
