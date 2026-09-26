class_name MenuHost
extends Node
## Routes EventBus.menu_requested to the right screen: a registry of menu ids
## (IDS). Shop ids map to ShopData resources in data/shops/<id>.tres.
##
## M9: screens a later task adds (M9_SCREENS) are instantiated at runtime from
## ui/menus/<Name>.gd when the script exists, so no task edits Main.tscn.
## A caller may pass context with open_with(); each screen gets its own copy
## (MenuScreen.ctx) before it builds, and reads only that copy afterwards.

## Every menu id besides shop_<id> (ContentValidator.MENU_IDS mirrors it).
const IDS: PackedStringArray = ["loadout", "pause", "journal", "settings", "slice_end", "moment", "survey", "map",
	"dev", "achievements", "challenges", "challenge_result", "ng_plus", "assist_suggest", "demo_end"]
## M9 screens built at runtime when their script exists (id -> script name).
const M9_SCREENS := {&"achievements": "AchievementsMenu", &"challenges": "ChallengesMenu",
	&"challenge_result": "ChallengeResultMenu", &"ng_plus": "NgPlusMenu", &"assist_suggest": "AssistSuggestMenu",
	&"demo_end": "DemoEndMenu"}
## Menus that take focus on their first row when opened by id.
const FOCUS_FIRST: Array[StringName] = [&"loadout", &"pause", &"settings"]

## Set by open_with; copied into the screen's ctx by open(), then cleared.
## e.g. {"from": "title"}, {"return_to": &"journal"}, {"page": &"quick"}.
static var context: Dictionary = {}

## Forwarded from any screen that can leave the game (PauseMenu's Save &
## Quit, DemoEndMenu): Main connects this once.
signal quit_to_title

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

## StringName id -> MenuScreen.
var _screens: Dictionary = {}
## [id, ctx] waiting for every menu to close (open_when_free).
var _queued: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"menu_host")
	_screens = {&"loadout": loadout, &"pause": pause, &"journal": journal, &"settings": settings,
		&"slice_end": slice_end, &"moment": moment, &"survey": survey, &"map": map_menu, &"dev": dev_console}
	for id: StringName in M9_SCREENS:
		var path := "res://ui/menus/%s.gd" % M9_SCREENS[id]
		if ResourceLoader.exists(path):
			var s := (load(path) as GDScript).new() as MenuScreen
			s.name = M9_SCREENS[id]
			add_child(s)
			_screens[id] = s
	for c in get_children():
		if c is MenuScreen and c != title:
			var s := c as MenuScreen
			s.closed.connect(_on_screen_closed)
			if s.has_signal("quit_to_title"):
				s.connect("quit_to_title", quit_to_title.emit)
	EventBus.menu_requested.connect(open)
	EventBus.slice_completed.connect(func() -> void: open(BuildInfo.slice_card_id()))
	EventBus.demo_boundary_reached.connect(func(_from: String, _to: String) -> void:
		if has_screen(&"demo_end"):
			open(&"demo_end"))


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
## M9: no map inside a challenge run (D-151); no pause between a run's end
## and its result card.
static func can_open(action: StringName, tree_paused: bool, menu_open: bool) -> bool:
	var room := SceneRouter.current_room as Room
	if room == null or SceneRouter.transitioning or tree_paused or menu_open:
		return false
	match action:
		&"map":
			return room.world_room and not Cinematics.locks_input() and not Challenges.active()
		&"debug_console":
			return DevActions.available() and not Cinematics.locks_input()
		&"pause":
			return not Challenges.finishing()
	return true


func any_open() -> bool:
	for c in get_children():
		if c is MenuScreen and (c as MenuScreen).is_open() and c != title:
			return true
	return false


func has_screen(id: StringName) -> bool:
	return _screens.has(id)


func screen(id: StringName) -> MenuScreen:
	return _screens.get(id) as MenuScreen


func open_with(id: StringName, ctx: Dictionary) -> void:
	context = ctx
	open(id)


## Opens now if no menu is open, otherwise once the last one closes (the
## challenge result card must never be dropped).
func open_when_free(id: StringName, ctx: Dictionary = {}) -> void:
	if not any_open():
		open_with(id, ctx)
		return
	_queued.append([id, ctx])


## Returns whether a screen opened. Refused (another menu is open, unknown
## id): the context is cleared so it never leaks into the next open.
func open(menu_id: StringName) -> bool:
	if any_open():
		context = {}
		return false
	if String(menu_id).begins_with("shop_"):
		context = {}
		var data := load("res://data/shops/%s.tres" % menu_id) as ShopData
		if data:
			shop.open_shop(data)
			return true
		return false
	var s := _screens.get(menu_id) as MenuScreen
	if s == null:
		context = {}
		return false
	s.ctx = context.duplicate(true)
	context = {}
	s.open_menu()
	if FOCUS_FIRST.has(menu_id):
		s.focus_index(0)
	return true


func _on_screen_closed() -> void:
	if any_open():
		return
	if not _queued.is_empty():
		var next: Array = _queued.pop_front()
		open_with(next[0], next[1])
		return
	if title.visible:
		title.call("focus_index", title.get("last_focus"))


static func clear_cache() -> void:
	context = {}
