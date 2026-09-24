extends MenuScreen
## Settings (bible §24): every entry cycles on confirm, so a controller
## reaches everything with one button. Saved on close. Never shames the player.

const SHAKE := [0.0, 0.5, 1.0]
const HITSTOP := [0.0, 0.5, 1.0]
const VOLUME := [0.0, 0.25, 0.5, 0.75, 1.0]


func rebuild() -> void:
	var keep := focused_index()
	clear_body()
	add_label("SETTINGS", UiTheme.ACCENT, UiTheme.FONT_SIZE + 2)
	add_button("Screen shake: %d%%" % roundi(Settings.screen_shake_scale * 100), _cycle_shake)
	add_button("Hitstop (freeze frames): %d%%" % roundi(Settings.hitstop_scale * 100), _cycle_hitstop)
	add_button("Flash reduction: %s" % ("On" if Settings.flash_reduction else "Off"), func() -> void:
		Settings.flash_reduction = not Settings.flash_reduction
		rebuild())
	add_button("Drop Scrap on death: %s" % ("On" if Settings.currency_loss else "Off"), func() -> void:
		Settings.currency_loss = not Settings.currency_loss
		rebuild())
	add_button("Core mode: %s" % ["Normal", "Story / Assist", "Redline Challenge"][Settings.reactor_mode], _cycle_mode)
	add_button("Master volume: %d%%" % roundi(Settings.master_volume * 100), _cycle_volume.bind("master_volume"))
	add_button("Music volume: %d%%" % roundi(Settings.music_volume * 100), _cycle_volume.bind("music_volume"))
	add_button("Effects volume: %d%%" % roundi(Settings.sfx_volume * 100), _cycle_volume.bind("sfx_volume"))
	add_button("Debug overlay: %s" % ("On" if Settings.show_debug_overlay else "Off"), func() -> void:
		Settings.show_debug_overlay = not Settings.show_debug_overlay
		EventBus.settings_changed.emit()
		rebuild())
	add_button("Playtest recording (local file): %s" % ("On" if Settings.playtest_recording else "Off"), func() -> void:
		Settings.playtest_recording = not Settings.playtest_recording
		if not Settings.playtest_recording:
			Playtest.end_session("recording_disabled")
		rebuild())
	add_button("Playtest variant: %s" % _variant_label(), _cycle_variant)
	add_button("Back", close_menu)
	focus_index(keep)


## Facilitators can pin an experiment arm; "Auto" rotates per session.
## Takes effect from the next New Game / Continue.
func _variant_label() -> String:
	var v := Playtest.config.variant(Settings.playtest_variant)
	return v.label if v else "Auto (rotates)"


func _cycle_variant() -> void:
	var ids: Array[String] = [""]
	for v in Playtest.config.variants:
		ids.append(v.id)
	var i := ids.find(Settings.playtest_variant)
	Settings.playtest_variant = ids[(i + 1) % ids.size()]
	rebuild()


func close_menu() -> void:
	Settings.save_settings()
	AudioManager.apply_volume()
	EventBus.settings_changed.emit()
	super.close_menu()


func _next(values: Array, current: float) -> float:
	for i in values.size():
		if is_equal_approx(values[i], current):
			return values[(i + 1) % values.size()]
	return values[0]


func _cycle_shake() -> void:
	Settings.screen_shake_scale = _next(SHAKE, Settings.screen_shake_scale)
	EventBus.camera_shake_requested.emit(0.4)
	rebuild()


func _cycle_hitstop() -> void:
	Settings.hitstop_scale = _next(HITSTOP, Settings.hitstop_scale)
	rebuild()


func _cycle_mode() -> void:
	Settings.reactor_mode = (Settings.reactor_mode + 1) % 3
	var room := SceneRouter.current_room as Room
	if room and is_instance_valid(room.player):
		room.player.reactor.apply_mode(Settings.reactor_mode)
	rebuild()


func _cycle_volume(key: String) -> void:
	Settings.set(key, _next(VOLUME, Settings.get(key)))
	AudioManager.apply_volume()
	AudioManager.play_sfx(&"ui_tick")
	rebuild()
