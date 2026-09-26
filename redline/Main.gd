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
	# `--print-build-info`: one JSON line for the build script, then quit.
	if "--print-build-info" in OS.get_cmdline_user_args():
		BuildProbe.run(get_tree())
		return
	if BuildInfo.is_demo():
		add_child(DemoGate.new())
	# Optional M9 systems, added when their task has landed (T11, T12).
	for n: String in ["AssistAdvisor", "Haptics"]:
		var p := "res://accessibility/%s.gd" % n
		if ResourceLoader.exists(p):
			var node: Node = (load(p) as GDScript).new()
			node.name = n
			add_child(node)
	SceneRouter.register_world_root(game_viewport)
	SceneRouter.register_fade($FadeLayer/Fade)
	var title: MenuScreen = menus.get_node("TitleMenu")
	title.lab_requested.connect(func(path: String) -> void:
		title.close_menu()
		SceneRouter.transition_to(path))
	# MenuHost forwards every screen's quit_to_title (Pause, the demo end
	# card): exactly one connection to _to_title.
	(menus as MenuHost).quit_to_title.connect(_to_title)
	if start_room != "":
		SceneRouter.goto_room(start_room)
	else:
		SceneRouter.goto_room("res://world/rooms/TitleBackdrop.tscn")
		title.open_menu()


func _to_title() -> void:
	# A result card queued behind the closing menu must not open over the fade
	# or the title.
	(menus as MenuHost).drop_queued()
	Playtest.end_session("quit_to_title")
	await SceneRouter.transition_to("res://world/rooms/TitleBackdrop.tscn")
	(menus.get_node("TitleMenu") as MenuScreen).open_menu()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("debug_switch_lab") and BuildInfo.enabled(&"lab_cycle") and not lab_rooms.is_empty() and not get_tree().paused:
		_room_index = (_room_index + 1) % lab_rooms.size()
		SceneRouter.goto_room(lab_rooms[_room_index])
