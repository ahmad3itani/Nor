extends MenuScreen
## Vendor screen (bible §13): buy Circuits, weapons and upgrades with Scrap.
## Items you can't afford stay focusable so you can read what they do.

var shop: ShopData
var _desc: Label
var _entries: Array[ShopItem] = []


func open_shop(p_shop: ShopData) -> void:
	shop = p_shop
	open_menu()
	focus_index(0)


func rebuild() -> void:
	var keep := focused_index()
	clear_body()
	_entries.clear()
	add_label(shop.title.to_upper(), UiTheme.ACCENT, UiTheme.FONT_SIZE + 1)
	add_label("SCRAP  %d" % Game.state.total_scrap(), Color("ffd36b"))
	for item in shop.items:
		if item.requires_flag != "" and not Game.has_flag(item.requires_flag):
			continue
		_entries.append(item)
		var owned := is_owned(item)
		var label := "%s    %s" % [item_name(item), "OWNED" if owned else "%d" % item_price(item)]
		add_button(label, _buy.bind(item), _describe.bind(item), not owned)
	add_button("Leave", close_menu)
	_desc = add_label("", UiTheme.MUTED)
	_desc.custom_minimum_size = Vector2(340, 30)
	if _entries.size() > 0:
		_describe(_entries[0])
	focus_index(keep)


func item_name(item: ShopItem) -> String:
	match item.kind:
		ShopItem.Kind.CIRCUIT:
			var c := Game.catalog.circuit(item.item_id) as CircuitData
			return "Circuit: " + (c.display_name if c else item.item_id)
		ShopItem.Kind.WEAPON:
			var w := Game.catalog.weapon(item.item_id)
			return w.display_name if w else item.item_id
	return item.display_name


func item_price(item: ShopItem) -> int:
	if item.price > 0:
		return item.price
	var c := Game.catalog.circuit(item.item_id) as CircuitData
	return c.price if c else 0


func is_owned(item: ShopItem) -> bool:
	match item.kind:
		ShopItem.Kind.CIRCUIT:
			return Game.state.owned_circuits.has(item.item_id)
		ShopItem.Kind.WEAPON:
			return Game.state.owned_weapons.has(item.item_id)
	return Game.flag_int(item.upgrade_flag) >= item.max_purchases


func _describe(item: ShopItem) -> void:
	if _desc == null:
		return
	match item.kind:
		ShopItem.Kind.CIRCUIT:
			var c := Game.catalog.circuit(item.item_id) as CircuitData
			_desc.text = "%s  (uses %d capacity)" % [c.description, c.cost] if c else ""
		ShopItem.Kind.WEAPON:
			_desc.text = "Equip at an Anchor."
		_:
			_desc.text = item.description


## Returns true if bought. Public so tests and scripted runs can buy directly.
func buy(item: ShopItem) -> bool:
	var price := item_price(item)
	if is_owned(item) or not Game.state.spend_scrap(price):
		AudioManager.play_sfx(&"empty")
		return false
	match item.kind:
		ShopItem.Kind.CIRCUIT:
			Game.grant_circuit(item.item_id)
		ShopItem.Kind.WEAPON:
			Game.grant_weapon(item.item_id)
		ShopItem.Kind.UPGRADE:
			Game.set_flag(item.upgrade_flag, Game.flag_int(item.upgrade_flag) + 1)
	AudioManager.play_sfx(&"purchase")
	EventBus.scrap_changed.emit(Game.state.total_scrap())
	EventBus.item_purchased.emit(shop.id if shop else &"", item.item_id, price)
	return true


func _buy(item: ShopItem) -> void:
	buy(item)
	rebuild()
