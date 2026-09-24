extends Node2D
## Lowlight skyline and rain behind the title screen; the camera drifts
## slowly so the city feels alive before you press anything.

@export var theme: DistrictTheme = preload("res://data/districts/lowlight.tres")

var _camera: Camera2D


func _ready() -> void:
	_camera = Camera2D.new()
	add_child(_camera)
	_camera.make_current()
	var backdrop := DistrictBackdrop.new()
	backdrop.setup(theme, _camera)
	add_child(backdrop)


func _process(delta: float) -> void:
	_camera.position.x += 12.0 * delta
