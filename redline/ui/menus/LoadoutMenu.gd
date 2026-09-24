extends MenuScreen
## Anchor loadout (bible §7, §11): choose melee and ranged weapons and slot
## Circuits within Core Capacity. Changes apply immediately.

var _desc: Label


func rebuild() -> void:
	var keep := focused_index()
	clear_body()
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
