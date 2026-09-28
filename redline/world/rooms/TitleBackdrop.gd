extends Node2D
## The city behind the title screen (ART_DIRECTION 4.5): the painted title
## set (title_sky screen-fixed, far spires 0.12, fog, mid rooftops 0.3),
## a ledge in the right third with Rook standing in the wind
## (`title_stand`), rain in front, a far lightning tint and a train about
## every 20 s. The camera keeps its slow 12 px/s drift and adds a 0.5 px
## vertical bob (held still at ambient motion Off). Without the painted set
## the old Lowlight skyline shows, and without the Rook sheet the ledge
## stands empty. The logo and menu are the TitleMenu's: the left two thirds
## stay clear.

const KIND := &"title"
const LEDGE_PATH := "res://assets/title/title_near_ledge.png"
const LEDGE_JSON := "res://assets/title/title_near_ledge.json"
const ROOK_SPEC := "res://assets/rook/rook_sheet.tres"
const LEDGE_MOTION := 0.6
const BOB_PX := 0.5
const BOB_HZ := 0.25
## Screen x of Rook's feet: right of the TitleMenu panel (x 60..420), so he
## reads on the ledge's far end while the menu is open.
const ROOK_X := 452.0

@export var theme: DistrictTheme = preload("res://data/districts/lowlight.tres")

var _camera: Camera2D
var _backdrop: DistrictBackdrop
var _ledge_layer: CanvasLayer
var _ledge_root: Node2D
var _ledge_plane: Sprite2D
var _rook: SpriteActor
var _t: float = 0.0
var _ledge_base: Vector2 = Vector2.ZERO


func _ready() -> void:
	_camera = Camera2D.new()
	add_child(_camera)
	_camera.make_current()
	_backdrop = DistrictBackdrop.new()
	_backdrop.backdrop_kind = KIND
	_backdrop.ref_camera_y = 0.0
	_backdrop.setup(theme, _camera)
	add_child(_backdrop)
	_build_ledge()


## The ledge (right third) and Rook on it, between the backdrop (-20) and
## the world; graded and dimmed like the backdrop planes.
func _build_ledge() -> void:
	if not ResourceLoader.exists(LEDGE_PATH):
		return
	var tex := load(LEDGE_PATH) as Texture2D
	_ledge_layer = CanvasLayer.new()
	_ledge_layer.name = "Ledge"
	_ledge_layer.layer = -19
	add_child(_ledge_layer)
	_ledge_root = Node2D.new()
	_ledge_layer.add_child(_ledge_root)
	var ledge := Sprite2D.new()
	ledge.name = "LedgePlane"
	ledge.texture = tex
	ledge.centered = false
	ledge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ledge_root.add_child(ledge)
	_ledge_plane = ledge
	var info := UiKit.read_json(LEDGE_JSON)
	var stand_x: Array = info.get("stand_x", [24, 140])
	var stand_y := float(info.get("stand_y", 44))
	# Rook stands near the ledge's far end; the ledge runs off the right edge.
	var foot_x := float(stand_x[1]) - 16.0
	_ledge_base = Vector2(ROOK_X - foot_x, DistrictBackdrop.VIEW.y - tex.get_height())
	_ledge_root.position = _ledge_base
	if ResourceLoader.exists(ROOK_SPEC):
		var spec := load(ROOK_SPEC) as SpriteSheetSpec
		_rook = SpriteActor.create(spec) if spec else null
		if _rook:
			_rook.name = "TitleRook"
			_rook.position = Vector2(foot_x, stand_y)
			_rook.face(-1)
			_ledge_root.add_child(_rook)
			_rook.play_first([&"title_stand", &"idle"])
	_apply_look()
	EventBus.settings_changed.connect(_apply_look)


func _exit_tree() -> void:
	if EventBus.settings_changed.is_connected(_apply_look):
		EventBus.settings_changed.disconnect(_apply_look)


func _apply_look() -> void:
	if _ledge_root == null:
		return
	var grade := _backdrop.backdrop_set.grade if _backdrop and _backdrop.backdrop_set else Color.WHITE
	# Grade and dim go on the ledge plane only (F11 / D-172): Rook, a
	# character with a reserved-red mask overlay (D-178), stays ungraded.
	_ledge_plane.modulate = grade * DistrictBackdrop.dim_modulate(Settings.background_dim)
	_ledge_root.modulate = Color.WHITE


## The Rook on the ledge (null when the sheet is missing).
func title_rook() -> SpriteActor:
	return _rook


func _process(delta: float) -> void:
	_camera.position.x += 12.0 * delta
	var bob := 0.0
	if Motion.animate_ambient():
		_t += delta
		bob = sin(_t * TAU * BOB_HZ) * BOB_PX
	_camera.position.y = bob
	if _ledge_root:
		_ledge_root.position = _ledge_base + Vector2(0.0, -bob * LEDGE_MOTION)
