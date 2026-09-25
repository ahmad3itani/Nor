extends MenuScreen
## Dev console (bible §34 internal tools), ` (backquote) in debug builds.
## Controller-navigable like every menu; pages: main, teleport, spawn,
## save-state inspector.

var page: StringName = &"main"
static var hitboxes: HitboxView
static var perf: PerfGraph


func open_menu() -> void:
	page = &"main"
	super.open_menu()
	focus_index(0)


func rebuild() -> void:
	clear_body()
	_panel.custom_minimum_size = Vector2(420, 0)
	add_label("DEV CONSOLE  —  %s" % String(page).to_upper(), UiTheme.ACCENT, UiTheme.FONT_SIZE + 1)
	match page:
		&"teleport":
			for t in DevActions.teleport_targets():
				add_button(t["label"], func() -> void:
					close_menu()
					DevActions.teleport(t["room"], t["entry"]))
		&"spawn":
			for path in DevActions.enemy_scenes():
				add_button(path.get_file().get_basename(), func() -> void:
					close_menu()
					DevActions.spawn_enemy(path))
		&"state":
			add_label(DevActions.state_summary(), UiTheme.TEXT, UiTheme.FONT_SIZE - 2)
			add_button("Save now", func() -> void: Game.save_game())
			add_button("Copy save JSON to clipboard", func() -> void: DisplayServer.clipboard_set(DevActions.state_json()))
		_:
			add_button("Teleport to room…", _go.bind(&"teleport"))
			add_button("Spawn enemy…", _go.bind(&"spawn"))
			add_button("Quick boss restart (Warden Krail)", func() -> void:
				close_menu()
				DevActions.quick_boss_restart("warden_krail"))
			add_button("Quick boss restart (Collector Drone)", func() -> void:
				close_menu()
				DevActions.quick_boss_restart("collector_drone"))
			add_button("Unlock-all debug profile", func() -> void:
				DevActions.unlock_all()
				EventBus.hint_requested.emit("DEV: everything unlocked", 1.5))
			add_button("Save-state inspector…", _go.bind(&"state"))
			add_button("Hitboxes: %s" % ("on" if is_instance_valid(hitboxes) else "off"), _toggle_hitboxes)
			add_button("Performance graph: %s" % ("on" if is_instance_valid(perf) else "off"), _toggle_perf)
	if page != &"main":
		add_button("Back", _go.bind(&"main"))
	add_button("Close", close_menu)


func _go(p: StringName) -> void:
	page = p
	rebuild()
	focus_index(0)


func _toggle_hitboxes() -> void:
	if is_instance_valid(hitboxes):
		hitboxes.queue_free()
		hitboxes = null
	elif SceneRouter.world_root:
		hitboxes = HitboxView.new()
		SceneRouter.world_root.add_child(hitboxes)
	rebuild()


func _toggle_perf() -> void:
	if is_instance_valid(perf):
		perf.queue_free()
		perf = null
	else:
		perf = PerfGraph.new()
		get_tree().root.add_child(perf)
	rebuild()
