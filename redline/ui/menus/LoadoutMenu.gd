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
	add_label(Loc.t("ANCHOR  —  LOADOUT"), UiTheme.ACCENT, UiTheme.FONT_SIZE + 1)
	add_label(Loc.t("Rested. Health, injectors and Core restored. Progress saved."), UiTheme.MUTED)
	var st := Game.state
	add_label(Loc.t("WEAPONS"), UiTheme.ACCENT)
	# Both slots always show, "—" while empty (the campaign starts unarmed).
	add_label(Loc.f("Melee: {melee}    Ranged: {ranged}", {"melee": _slot_name(st.melee_weapon), "ranged": _slot_name(st.ranged_weapon)}),
		UiTheme.MUTED)
	for id in st.owned_weapons:
		var w := Game.catalog.weapon(id)
		if w == null:
			continue
		var equipped := id == st.melee_weapon or id == st.ranged_weapon
		var melee := w.kind == WeaponData.Kind.MELEE
		var kind := Loc.t("Melee") if melee else Loc.t("Ranged")
		add_button(Loc.f("{mark} {name}  ({kind})", {"mark": "●" if equipped else "○", "name": Loc.t(w.display_name), "kind": kind}),
			_equip_weapon.bind(id),
			_describe_text.bind(Loc.t("Melee weapon. Select to equip.") if melee else Loc.t("Ranged weapon. Select to equip.")))
	add_label(Loc.f("CIRCUITS   capacity {used} / {max}", {"used": Game.capacity_used(), "max": Game.core_capacity()}), UiTheme.ACCENT)
	if st.owned_circuits.is_empty():
		add_label(Loc.t("None yet. Vell at the Relay deals in Circuits."), UiTheme.MUTED)
	for id in st.owned_circuits:
		var c := Game.catalog.circuit(id) as CircuitData
		if c == null:
			continue
		var on := st.equipped_circuits.has(id)
		var fits := on or Game.can_equip(id)
		var desc := Loc.t(c.description) if fits else Loc.f("{text}   (not enough capacity)", {"text": Loc.t(c.description)})
		add_button(Loc.f("{mark} {name}  [{cost}]", {"mark": "●" if on else "○", "name": Loc.t(c.display_name), "cost": c.cost}),
			_toggle.bind(id), _describe_text.bind(desc))
	# Transit (bible §13 Nix / §7 "later fast travel"): between rested Anchors.
	if Game.transit_unlocked():
		add_button(Loc.t("Transit  »"), _show_transit, _describe_text.bind(Loc.t("Travel to any Anchor you have rested at.")))
	elif Game.has_flag("met_nix"):
		add_label(Loc.t("Transit: Nix sells passes for the old lines."), UiTheme.MUTED)
	add_button(Loc.t("Leave"), close_menu, _describe_text.bind(""))
	_desc = add_label("", UiTheme.MUTED)
	_desc.custom_minimum_size = Vector2(340, 24)
	focus_index(keep)


static func _slot_name(id: String) -> String:
	var w := Game.catalog.weapon(id) if id != "" else null
	return Loc.t(w.display_name) if w else "—"


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
	add_label(Loc.t("ANCHOR  —  TRANSIT"), UiTheme.ACCENT, UiTheme.FONT_SIZE + 1)
	var here_room := Game.state.last_anchor_room
	var here_id := Game.state.last_anchor_id
	var dests := Game.transit_destinations(here_room, here_id)
	if dests.is_empty():
		add_label(Loc.t("No other Anchors on the line yet. Rest at one to add it."), UiTheme.MUTED)
	for key in dests:
		add_button(destination_label(key), _travel.bind(key))
	add_button(Loc.t("Back"), func() -> void:
		_transit_page = false
		rebuild()
		focus_index(0))


static func destination_label(key: String) -> String:
	var room := key.get_slice("|", 0)
	var info := WorldMapIndex.room_info(room)
	return Loc.f("{district}  —  {room}", {"district": Loc.t(str(info.get("district_name", ""))),
		"room": Loc.t(str(info.get("name", room.get_file().get_basename())))})


func _travel(key: String) -> void:
	close_menu()
	var room := SceneRouter.current_room as Room
	if room and is_instance_valid(room.player):
		Game.capture_from_player(room.player)
	Game.travel_to(key)
