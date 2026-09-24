extends MenuScreen
## Anchor loadout (bible §7, §11): choose melee and ranged weapons and slot
## Circuits within Core Capacity. Changes apply immediately.

var _desc: Label
var _transit_page: bool = false


func open_menu() -> void:
	_transit_page = false
	super.open_menu()


func rebuild() -> void:
	var keep := focused_index()
	clear_body()
	if _transit_page:
		_build_transit()
		return
	add_label("ANCHOR  —  LOADOUT", UiTheme.ACCENT, UiTheme.FONT_SIZE + 1)
	add_label("Rested. Health, injectors and Core restored. Progress saved.", UiTheme.MUTED)
	var st := Game.state
	add_label("WEAPONS", UiTheme.ACCENT)
	for id in st.owned_weapons:
		var w := Game.catalog.weapon(id)
		if w == null:
			continue
		var equipped := id == st.melee_weapon or id == st.ranged_weapon
		var kind := "Melee" if w.kind == WeaponData.Kind.MELEE else "Ranged"
		add_button("%s %s  (%s)" % ["●" if equipped else "○", w.display_name, kind], _equip_weapon.bind(id),
			_describe_text.bind("%s weapon. Select to equip." % kind))
	add_label("CIRCUITS   capacity %d / %d" % [Game.capacity_used(), Game.core_capacity()], UiTheme.ACCENT)
	if st.owned_circuits.is_empty():
		add_label("None yet. Vell at the Relay deals in Circuits.", UiTheme.MUTED)
	for id in st.owned_circuits:
		var c := Game.catalog.circuit(id) as CircuitData
		if c == null:
			continue
		var on := st.equipped_circuits.has(id)
		var fits := on or Game.can_equip(id)
		add_button("%s %s  [%d]" % ["●" if on else "○", c.display_name, c.cost], _toggle.bind(id),
			_describe_text.bind(c.description + ("" if fits else "   (not enough capacity)")))
	# Transit (bible §13 Nix / §7 "later fast travel"): between rested Anchors.
	if Game.transit_unlocked():
		add_button("Transit  →", _show_transit, _describe_text.bind("Travel to any Anchor you have rested at."))
	elif Game.has_flag("met_nix"):
		add_label("Transit: Nix sells passes for the old lines.", UiTheme.MUTED)
	add_button("Leave", close_menu, _describe_text.bind(""))
	_desc = add_label("", UiTheme.MUTED)
	_desc.custom_minimum_size = Vector2(340, 24)
	focus_index(keep)


func _describe_text(text: String) -> void:
	if _desc:
		_desc.text = text


func _equip_weapon(id: String) -> void:
	Game.equip_weapon(id)
	AudioManager.play_sfx(&"ui_tick")
	rebuild()


func _toggle(id: String) -> void:
	AudioManager.play_sfx(&"ui_tick" if Game.toggle_circuit(id) else &"empty")
	rebuild()


func _show_transit() -> void:
	_transit_page = true
	rebuild()
	focus_index(0)


func _build_transit() -> void:
	add_label("ANCHOR  —  TRANSIT", UiTheme.ACCENT, UiTheme.FONT_SIZE + 1)
	var here_room := Game.state.last_anchor_room
	var here_id := Game.state.last_anchor_id
	var dests := Game.transit_destinations(here_room, here_id)
	if dests.is_empty():
		add_label("No other Anchors on the line yet. Rest at one to add it.", UiTheme.MUTED)
	for key in dests:
		add_button(destination_label(key), _travel.bind(key))
	add_button("Back", func() -> void:
		_transit_page = false
		rebuild()
		focus_index(0))


static func destination_label(key: String) -> String:
	var room := key.get_slice("|", 0)
	var info := WorldMapIndex.room_info(room)
	return "%s  —  %s" % [info.get("district_name", ""), info.get("name", room.get_file().get_basename())]


func _travel(key: String) -> void:
	close_menu()
	var room := SceneRouter.current_room as Room
	if room and is_instance_valid(room.player):
		Game.capture_from_player(room.player)
	Game.travel_to(key)
