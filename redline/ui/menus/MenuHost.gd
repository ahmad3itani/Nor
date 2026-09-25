extends Node
## Routes EventBus.menu_requested to the right screen. Shop ids map to
## ShopData resources in data/shops/<id>.tres.

@onready var loadout: MenuScreen = $LoadoutMenu
@onready var shop: MenuScreen = $ShopMenu
@onready var pause: MenuScreen = $PauseMenu
@onready var journal: MenuScreen = $JournalMenu
@onready var settings: MenuScreen = $SettingsMenu
@onready var slice_end: MenuScreen = $SliceEndMenu
@onready var title: MenuScreen = $TitleMenu
@onready var moment: MenuScreen = $MomentMenu
@onready var survey: MenuScreen = $SurveyMenu
@onready var map_menu: MenuScreen = $MapMenu
@onready var dev_console: MenuScreen = $DevConsole


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.menu_requested.connect(open)
	EventBus.slice_completed.connect(func() -> void: open(&"slice_end"))
	settings.closed.connect(func() -> void:
		if title.visible:
			title.focus_index(0))


func _process(_delta: float) -> void:
	var paused := get_tree().paused
	var menu_open := any_open()
	if Input.is_action_just_pressed("pause") and can_open(&"pause", paused, menu_open):
		open(&"pause")
	elif Input.is_action_just_pressed("map") and can_open(&"map", paused, menu_open):
		open(&"map")
	elif Input.is_action_just_pressed("debug_console") and can_open(&"debug_console", paused, menu_open):
		open(&"dev")


## Whether an input action may open its menu now: only in a room, never
## mid-transition, under a pause or over another menu. While a scripted
## sequence holds the lock the map and the dev console stay shut; pause still
## opens (§24: every scene can be paused, and PauseMenu offers "Skip scene").
static func can_open(action: StringName, tree_paused: bool, menu_open: bool) -> bool:
	var room := SceneRouter.current_room as Room
	if room == null or SceneRouter.transitioning or tree_paused or menu_open:
		return false
	match action:
		&"map":
			return room.world_room and not Cinematics.locks_input()
		&"debug_console":
			return DevActions.available() and not Cinematics.locks_input()
	return true


func any_open() -> bool:
	for c in get_children():
		if c is MenuScreen and (c as MenuScreen).is_open() and c != title:
			return true
	return false


func open(menu_id: StringName) -> void:
	if any_open():
		return
	if menu_id == &"loadout":
		loadout.open_menu()
		loadout.focus_index(0)
	elif menu_id == &"pause":
		pause.open_menu()
		pause.focus_index(0)
	elif menu_id == &"journal":
		journal.open_menu()
	elif menu_id == &"settings":
		settings.open_menu()
		settings.focus_index(0)
	elif menu_id == &"slice_end":
		slice_end.open_menu()
	elif menu_id == &"moment":
		moment.open_menu()
	elif menu_id == &"survey":
		survey.open_menu()
	elif menu_id == &"map":
		map_menu.open_menu()
	elif menu_id == &"dev":
		dev_console.open_menu()
	elif String(menu_id).begins_with("shop_"):
		var data := load("res://data/shops/%s.tres" % menu_id) as ShopData
		if data:
			shop.open_shop(data)
