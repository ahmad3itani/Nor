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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.menu_requested.connect(open)
	EventBus.slice_completed.connect(func() -> void: open(&"slice_end"))
	settings.closed.connect(func() -> void:
		if title.visible:
			title.focus_index(0))


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("pause") and not any_open() and not get_tree().paused \
			and SceneRouter.current_room is Room and not SceneRouter.transitioning:
		open(&"pause")


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
	elif String(menu_id).begins_with("shop_"):
		var data := load("res://data/shops/%s.tres" % menu_id) as ShopData
		if data:
			shop.open_shop(data)
