extends Node
## Routes EventBus.menu_requested to the right screen. Shop ids map to
## ShopData resources in data/shops/<id>.tres.

@onready var loadout: MenuScreen = $LoadoutMenu
@onready var shop: MenuScreen = $ShopMenu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.menu_requested.connect(open)


func any_open() -> bool:
	for c in get_children():
		if c is MenuScreen and (c as MenuScreen).is_open():
			return true
	return false


func open(menu_id: StringName) -> void:
	if any_open():
		return
	if menu_id == &"loadout":
		loadout.open_menu()
		loadout.focus_index(0)
	elif String(menu_id).begins_with("shop_"):
		var data := load("res://data/shops/%s.tres" % menu_id) as ShopData
		if data:
			shop.open_shop(data)
