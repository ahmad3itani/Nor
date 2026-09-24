extends Node
## Boot scene: hosts the pixel gameplay viewport and native-res UI layers,
## then loads the starting room. M1 boots straight into the Movement Lab.

@export_file("*.tscn") var start_room: String = "res://world/rooms/MovementLab.tscn"

@onready var game_viewport: SubViewport = $GameView/GameViewport


func _ready() -> void:
	SceneRouter.register_world_root(game_viewport)
	SceneRouter.goto_room(start_room)
