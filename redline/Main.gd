extends Node
## Boot scene: hosts the pixel gameplay viewport and native-res UI layers,
## then loads the starting room. F12 swaps between the lab rooms.

@export_file("*.tscn") var start_room: String = "res://world/rooms/CombatLab.tscn"
@export var lab_rooms: Array[String] = [
	"res://world/rooms/CombatLab.tscn",
	"res://world/rooms/MovementLab.tscn",
]

var _room_index: int = 0

@onready var game_viewport: SubViewport = $GameView/GameViewport


func _ready() -> void:
	SceneRouter.register_world_root(game_viewport)
	SceneRouter.register_fade($FadeLayer/Fade)
	_room_index = maxi(lab_rooms.find(start_room), 0)
	SceneRouter.goto_room(start_room)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("debug_switch_lab") and not lab_rooms.is_empty():
		_room_index = (_room_index + 1) % lab_rooms.size()
		SceneRouter.goto_room(lab_rooms[_room_index])
