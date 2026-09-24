extends Node
## Boot scene: hosts the pixel gameplay viewport and native-res UI layers.
## Boots to the title screen (M3). `start_room` skips the title (dev tools,
## capture tours); F12 cycles the lab rooms.

@export_file("*.tscn") var start_room: String = ""
@export var lab_rooms: Array[String] = [
	"res://world/rooms/CombatLab.tscn",
	"res://world/rooms/MovementLab.tscn",
]

var _room_index: int = -1

@onready var game_viewport: SubViewport = $GameView/GameViewport
@onready var menus: Node = $Menus


func _ready() -> void:
	SceneRouter.register_world_root(game_viewport)
	SceneRouter.register_fade($FadeLayer/Fade)
	var title: MenuScreen = menus.get_node("TitleMenu")
	title.lab_requested.connect(func(path: String) -> void:
		title.close_menu()
		SceneRouter.transition_to(path))
	(menus.get_node("PauseMenu") as MenuScreen).quit_to_title.connect(_to_title)
	if start_room != "":
		SceneRouter.goto_room(start_room)
	else:
		SceneRouter.goto_room("res://world/rooms/TitleBackdrop.tscn")
		title.open_menu()


func _to_title() -> void:
	await SceneRouter.transition_to("res://world/rooms/TitleBackdrop.tscn")
	(menus.get_node("TitleMenu") as MenuScreen).open_menu()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("debug_switch_lab") and not lab_rooms.is_empty() and not get_tree().paused:
		_room_index = (_room_index + 1) % lab_rooms.size()
		SceneRouter.goto_room(lab_rooms[_room_index])
