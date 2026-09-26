extends MenuScreen
## Settings (bible §24): every entry cycles on confirm, so a controller
## reaches everything with one button. Saved on close. Never shames the player.
## M8: the subtitle and scene rows (D-110) live on a "Subtitles & scenes…"
## sub-page (DevConsole page pattern) so the main page gains one row and both
## pages fit the 270 px canvas without scrolling.

const SHAKE := [0.0, 0.5, 1.0]
const HITSTOP := [0.0, 0.5, 1.0]
const VOLUME := [0.0, 0.25, 0.5, 0.75, 1.0]
const SUBTITLE_SIZES := ["Small", "Medium", "Large"]
const SUBTITLE_BACKGROUNDS := ["Outline", "Box", "Solid"]
const SUBTITLE_SPEEDS := ["Normal", "Slow", "Slower"]

## &"main" or &"subtitles".
var page: StringName = &"main"
## Focus row of "Subtitles & scenes…" on the main page (Back returns there).
var _subtitles_row: int = 0


func open_menu() -> void:
	page = &"main"
	super.open_menu()


func rebuild() -> void:
	var keep := focused_index()
	clear_body()
	if page == &"subtitles":
		_build_subtitles()
		focus_index(keep)
		return
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
	_subtitles_row = _button_count()
	add_button("Subtitles & scenes…", _go.bind(&"subtitles"))
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


## Bible §24 subtitle/scene options. Every row cycles on confirm like the
## main page and emits settings_changed so open overlays restyle at once.
func _build_subtitles() -> void:
	add_label("SUBTITLES & SCENES", UiTheme.ACCENT, UiTheme.FONT_SIZE + 2)
	add_button("Subtitle size: %s" % SUBTITLE_SIZES[Settings.subtitle_size], func() -> void:
		Settings.subtitle_size = (Settings.subtitle_size + 1) % 3
		# Editing the stored size drops a --subtitle-size capture override for the session.
		Settings._subtitle_size_override = -1
		_changed())
	add_button("Subtitle background: %s" % SUBTITLE_BACKGROUNDS[Settings.subtitle_background], func() -> void:
		Settings.subtitle_background = (Settings.subtitle_background + 1) % 3
		_changed())
	add_button("Speaker names: %s" % ("On" if Settings.speaker_labels else "Off"), func() -> void:
		Settings.speaker_labels = not Settings.speaker_labels
		_changed())
	add_button("Subtitle speed: %s" % SUBTITLE_SPEEDS[Settings.subtitle_speed], func() -> void:
		Settings.subtitle_speed = (Settings.subtitle_speed + 1) % 3
		_changed())
	add_button("Skip scenes: %s" % ("Hold" if Settings.cinematic_skip_hold else "Press twice"), func() -> void:
		Settings.cinematic_skip_hold = not Settings.cinematic_skip_hold
		_changed())
	add_button("Memories play at Anchors: %s" % ("On" if Settings.memories_at_anchors else "Off"), func() -> void:
		Settings.memories_at_anchors = not Settings.memories_at_anchors
		_changed())
	add_button("Back", _go.bind(&"main"))


func _changed() -> void:
	EventBus.settings_changed.emit()
	rebuild()


## Switch pages; returning to main focuses the row that opened the sub-page.
func _go(p: StringName) -> void:
	page = p
	rebuild()
	focus_index(_subtitles_row if p == &"main" else 0)


func _button_count() -> int:
	return _body.get_children().filter(func(n: Node) -> bool: return n is Button and not n.is_queued_for_deletion()).size()


## On the sub-page Cancel goes back to the main page instead of closing, so a
## controller user never leaves Settings by accident (save-on-close unchanged).
func _process(delta: float) -> void:
	if visible and page != &"main" and Engine.get_process_frames() != _opened_frame and cancel_pressed():
		_go(&"main")
		return
	super._process(delta)


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
