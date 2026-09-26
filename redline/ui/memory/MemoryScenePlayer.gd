class_name MemoryScenePlayer
extends CanvasLayer
## Plays memory vignettes (M8, bible §18 memories, §24 cinematic skip and
## pause): a short, player-paced tableau per scene, requested through
## EventBus.memory_playback_requested by Anchor rests and the journal (never
## by a pickup, D-112).
##
## Design intent:
## - The world is paused behind a vignette, so every beat waits for a tap
##   (PLAY); AUTO advances on the beat's auto time; INSTANT (headless default)
##   resolves the whole request inside play(), so no test or probe can hang.
## - Advance and skip follow the shared SkipGate rule: a tap advances a beat,
##   a hold of cinematic_skip skips (and still remembers, D-116).
## - The player owns its pause: the `pause` action opens a small panel here
##   (menus cannot open over a paused tree).
## - End order is binding: mark_seen + memory_scene_finished per scene; after
##   the last scene the tree is unpaused (only if this player paused it), the
##   HUD owner is popped, and only then memory_playback_finished fires, so a
##   listener that opens a menu never has the world running behind it.

enum Phase { IDLE, TITLE, BEAT, TEAR }

const MEMORY_BLUE := Color("9fd8ff")
const MUTED_BLUE := Color("5f93b3")
const HUD_OWNER := &"memory"
const VIEW_HALF := 240.0
const PANEL_ROWS := 3

## The instance in Main.tscn (or a test's). The Anchor falls back to the
## loadout when there is none.
static var active_instance: MemoryScenePlayer = null

var cfg: MemoryConfig
var _queue: Array[MemorySceneData] = []
var _source: StringName = &""
var _scene: MemorySceneData
var _phase: Phase = Phase.IDLE
var _beat: int = 0
var _beat_time: float = 0.0
var _phase_time: float = 0.0
var _shown: float = 0.0
var _view_x: float = VIEW_HALF
var _target_x: float = VIEW_HALF
var _detail_time: float = 0.0
var _detail_found: bool = false
var _detail_show: float = 0.0
var _seconds: float = 0.0
var _beats_seen: int = 0
var _first_view: bool = true
var _gate: SkipGate
var _paused_by_me: bool = false
var _panel_open: bool = false
var _panel_index: int = 0
var _panel_opened_frame: int = -1
var _t: float = 0.0
var _tableau: MemoryTableauView
var _ui: Control


func _ready() -> void:
	layer = 85
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	cfg = MemoryLibrary.config()
	_tableau = MemoryTableauView.new()
	_tableau.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tableau.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tableau)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.draw.connect(_draw_ui)
	add_child(_ui)
	active_instance = self
	EventBus.memory_playback_requested.connect(play)
	CinematicMode.register_teardown(Callable(MemoryScenePlayer, &"abort_active"))


func _exit_tree() -> void:
	if active_instance == self:
		active_instance = null


func is_playing() -> bool:
	return _phase != Phase.IDLE


## Plays `ids` in order. A request during playback joins the queue; unknown
## ids are dropped (an empty request still reports finished, so an Anchor
## listener always gets its loadout).
func play(ids: PackedStringArray, source: StringName) -> void:
	var scenes: Array[MemorySceneData] = []
	for id in ids:
		var s := MemoryLibrary.scene(id)
		if s:
			scenes.append(s)
	if is_playing():
		_queue.append_array(scenes)
		return
	if scenes.is_empty():
		EventBus.memory_playback_finished.emit(source)
		return
	_source = source
	if CinematicMode.current() == CinematicMode.Mode.INSTANT:
		# Resolved in this call: remembered, reported, never paused.
		for s in scenes:
			var first := not MemoryLibrary.is_seen(s.id)
			EventBus.memory_scene_started.emit(s.id, source)
			MemoryLibrary.mark_seen(s.id)
			EventBus.memory_scene_finished.emit(s.id, source, false, 0.0, s.beats.size(), false, first)
		EventBus.memory_playback_finished.emit(source)
		return
	_queue = scenes
	_paused_by_me = not get_tree().paused
	if _paused_by_me:
		get_tree().paused = true
	CinematicMode.push_hud_hide(HUD_OWNER)
	EventBus.interact_prompt_changed.emit("")
	visible = true
	_start(_queue.pop_front())


func _start(s: MemorySceneData) -> void:
	_scene = s
	_phase = Phase.TITLE
	_phase_time = 0.0
	_beat = 0
	_beat_time = 0.0
	_shown = 0.0
	_view_x = s.start_view_x
	_target_x = s.start_view_x
	_detail_time = 0.0
	_detail_found = false
	_detail_show = 0.0
	_seconds = 0.0
	_beats_seen = 0
	_first_view = not MemoryLibrary.is_seen(s.id)
	_gate = SkipGate.new(_first_view)
	_panel_open = false
	_tableau.setup(s, cfg)
	_update_view()
	AudioManager.play_sfx(&"memory_open")
	EventBus.memory_scene_started.emit(s.id, _source)


func _process(delta: float) -> void:
	if _phase == Phase.IDLE:
		return
	if _panel_open:
		# Everything (beat clock, pan, dwell, gate) is frozen behind the panel.
		_process_panel()
		_ui.queue_redraw()
		return
	if Input.is_action_just_pressed(&"pause"):
		_open_panel()
		_ui.queue_redraw()
		return
	_t += delta
	_seconds += delta
	var out := SkipGate.poll(_gate, delta)
	if out == SkipGate.Out.SKIP:
		_finish(true)
		return
	match _phase:
		Phase.TITLE:
			_phase_time += delta
			if _phase_time >= cfg.title_seconds:
				_enter_beat(0)
		Phase.BEAT:
			_process_beat(delta, out == SkipGate.Out.TAP)
		Phase.TEAR:
			_phase_time += delta
			if _phase_time >= cfg.tear_seconds:
				_finish(false)
				return
	_pan(delta)
	_check_detail(delta)
	_update_view()


func _process_beat(delta: float, tap: bool) -> void:
	_beat_time += delta
	var b := _scene.beats[_beat]
	var n := float(b.text.length())
	_shown = minf(_shown + cfg.chars_per_second * delta, n)
	if tap:
		# A tap first completes the line (never skips unread text), then
		# advances once the beat has been up min_seconds.
		if _shown < n:
			_shown = n
		elif _beat_time >= b.min_seconds:
			_advance()
			return
	if CinematicMode.current() == CinematicMode.Mode.AUTO and _beat_time >= _auto_seconds(b):
		_advance()


func _auto_seconds(b: MemoryBeat) -> float:
	var base := cfg.auto_advance_base + b.text.length() * cfg.auto_advance_per_char
	return base * SubtitleStyle.time_scale() / maxf(CinematicMode.auto_speed, 0.01)


func _advance() -> void:
	_detail_show = 0.0
	if _beat + 1 < _scene.beats.size():
		_enter_beat(_beat + 1)
	else:
		_phase = Phase.TEAR
		_phase_time = 0.0
		AudioManager.play_sfx(&"memory_tear")


func _enter_beat(i: int) -> void:
	_phase = Phase.BEAT
	_beat = i
	_beat_time = 0.0
	_shown = 0.0
	_beats_seen = maxi(_beats_seen, i + 1)
	var b := _scene.beats[i]
	if b.view_x >= 0.0:
		_target_x = b.view_x
	if b.sfx != &"":
		AudioManager.play_sfx(b.sfx)
	elif i > 0:
		AudioManager.play_sfx(&"memory_beat")


## move_left/right pans the tableau (player look); otherwise the view eases
## towards the beat's authored view_x.
func _pan(delta: float) -> void:
	var hi := _scene.max_view_x()
	var dir := Input.get_axis(&"move_left", &"move_right")
	if _phase == Phase.BEAT and absf(dir) > 0.2:
		_view_x = clampf(_view_x + signf(dir) * cfg.pan_speed * delta, VIEW_HALF, hi)
		_target_x = _view_x
	else:
		_view_x = lerpf(_view_x, _target_x, 1.0 - exp(-cfg.pan_ease * delta))
	_view_x = clampf(_view_x, VIEW_HALF, hi)


## The detail counts while the view centre stays within detail_radius of
## detail_x for detail_dwell seconds (validated reachable only by panning).
func _check_detail(delta: float) -> void:
	_detail_show = maxf(_detail_show - delta, 0.0)
	if _phase != Phase.BEAT or _detail_found or not _scene.has_detail() or _beat < _scene.detail_from_beat:
		return
	if absf(_scene.detail_x - _view_x) <= cfg.detail_radius:
		_detail_time += delta
		if _detail_time >= cfg.detail_dwell:
			_detail_found = true
			_detail_show = cfg.detail_show_seconds
			MemoryLibrary.mark_detail(_scene.id)
			AudioManager.play_sfx(&"memory_detail")
	else:
		_detail_time = 0.0


func _finish(skipped: bool) -> void:
	var s := _scene
	MemoryLibrary.mark_seen(s.id)
	EventBus.memory_scene_finished.emit(s.id, _source, skipped, _seconds, _beats_seen, _detail_found, _first_view)
	if not _queue.is_empty():
		_start(_queue.pop_front())
		return
	_end_playback(true)


## Binding order: unpause (only a tree this player paused), pop the HUD
## owner, then (unless aborting) report the playback finished.
func _end_playback(report: bool) -> void:
	var source := _source
	_phase = Phase.IDLE
	_scene = null
	_queue.clear()
	_panel_open = false
	_gate = null
	visible = false
	if _paused_by_me:
		get_tree().paused = false
	_paused_by_me = false
	CinematicMode.pop_hud_hide(HUD_OWNER)
	if report:
		EventBus.memory_playback_finished.emit(source)
	else:
		EventBus.memory_playback_aborted.emit(source)


## Test/teardown path (registered with CinematicMode.register_teardown): stops
## the current scene without remembering it, drops the queue, restores pause
## and the HUD, and emits memory_playback_aborted instead of _finished (music
## leaves MEMORY; the Anchor drops its follow-up and opens no menu).
static func abort_active() -> void:
	if is_instance_valid(active_instance) and active_instance.is_playing():
		active_instance._end_playback(false)


# --- Pause panel (bible §24) ---

func _open_panel() -> void:
	_panel_open = true
	_panel_index = 0
	_panel_opened_frame = Engine.get_process_frames()


func _close_panel() -> void:
	_panel_open = false
	if _gate:
		# The press that closed the panel never advances or skips.
		_gate.notify_unpaused()


func _process_panel() -> void:
	# Esc is both pause and ui_cancel: the opening frame never closes it.
	if Engine.get_process_frames() == _panel_opened_frame:
		return
	if Input.is_action_just_pressed(&"ui_cancel") or Input.is_action_just_pressed(&"pause"):
		_close_panel()
		return
	if Input.is_action_just_pressed(&"ui_up"):
		_panel_index = (_panel_index + PANEL_ROWS - 1) % PANEL_ROWS
		AudioManager.play_sfx(&"ui_tick")
	elif Input.is_action_just_pressed(&"ui_down"):
		_panel_index = (_panel_index + 1) % PANEL_ROWS
		AudioManager.play_sfx(&"ui_tick")
	elif Input.is_action_just_pressed(&"ui_accept"):
		match _panel_index:
			0:
				_close_panel()
			1:
				_panel_open = false
				_finish(true)
			2:
				Settings.subtitle_size = (Settings.subtitle_size + 1) % 3
				Settings.save_settings()


func _panel_rows() -> PackedStringArray:
	var size_name: String = cfg.size_names[clampi(Settings.subtitle_size, 0, cfg.size_names.size() - 1)]
	return PackedStringArray([cfg.pause_resume, cfg.pause_skip, cfg.pause_size % size_name])


# --- Test and tooling accessors ---

func panel_open() -> bool:
	return _panel_open


func current_id() -> String:
	return _scene.id if _scene else ""


func beat_index() -> int:
	return _beat


func beat_time() -> float:
	return _beat_time


func phase() -> Phase:
	return _phase


func view_x() -> float:
	return _view_x


func skip_gate() -> SkipGate:
	return _gate


func uses_shear() -> bool:
	return _tableau.uses_shear()


## The blinking "[E]" advance cue: shown once the beat's line is fully out
## and min_seconds has passed (in PLAY every beat waits for a tap).
func cue_visible() -> bool:
	if _phase != Phase.BEAT or _panel_open or _scene == null:
		return false
	var b := _scene.beats[_beat]
	return _beat_time >= b.min_seconds and _shown >= b.text.length()


func skip_prompt_visible() -> bool:
	return _gate != null and _gate.prompt_visible and not _panel_open


# --- Drawing ---

func _update_view() -> void:
	if _scene == null:
		return
	var burn := 0.05
	var tear := 0.0
	match _phase:
		Phase.BEAT:
			burn = _scene.beats[_beat].burn
		Phase.TEAR:
			burn = _scene.beats[_scene.beats.size() - 1].burn
			tear = clampf(_phase_time / maxf(cfg.tear_seconds, 0.01), 0.0, 1.0)
	_tableau.modulate.a = clampf(_phase_time / maxf(cfg.title_seconds, 0.01), 0.0, 1.0) if _phase == Phase.TITLE else 1.0
	_tableau.set_state(_beat, _view_x, burn, tear, _t, minf(_detail_show, 1.0))
	_ui.queue_redraw()


func _draw_ui() -> void:
	if _scene == null:
		return
	var view := _ui.size
	var font := SubtitleStyle.font()
	var lb := float(cfg.letterbox_px)
	_ui.draw_rect(Rect2(0, 0, view.x, lb), Color.BLACK)
	_ui.draw_rect(Rect2(0, view.y - lb, view.x, lb), Color.BLACK)
	if _phase == Phase.TITLE:
		var a := clampf(_phase_time * 3.0, 0.0, 1.0)
		_ui.draw_string(font, Vector2(0, view.y * 0.5 - 8), cfg.title_label, HORIZONTAL_ALIGNMENT_CENTER, view.x, 7, Color(MEMORY_BLUE, a))
		_ui.draw_string(font, Vector2(0, view.y * 0.5 + 6), _scene.display_title(), HORIZONTAL_ALIGNMENT_CENTER, view.x, 9, Color(MEMORY_BLUE, a))
	elif _phase == Phase.BEAT:
		_draw_subtitle(view, font)
	if skip_prompt_visible():
		var text := _gate.prompt_text()
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x
		var pos := Vector2(view.x - tw - 8, lb - 8)
		_ui.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(1, 1, 1, 0.7))
		_ui.draw_rect(Rect2(pos.x, pos.y + 2, tw * _gate.progress_ratio(), 1), MEMORY_BLUE)
	if _panel_open:
		_draw_panel(view, font)


func _draw_subtitle(view: Vector2, font: Font) -> void:
	var b := _scene.beats[_beat]
	var width := view.x - 48.0
	var h := SubtitleStyle.box_height(b.text, width)
	var box := Rect2(24, view.y - 16 - h, width, h)
	SubtitleStyle.draw_line(_ui, box, b.speaker, b.text.substr(0, int(_shown)), MEMORY_BLUE)
	var fs := SubtitleStyle.font_size()
	if cue_visible() and int(Time.get_ticks_msec() / 400) % 2 == 0:
		_ui.draw_string(font, box.end - Vector2(24, 6), "[%s]" % InputGlyphs.label(&"interact"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 1, Color(1, 1, 1, 0.7))
	if _detail_show > 0.0 and _scene.has_detail():
		var lines := SubtitleStyle.line_count(_scene.detail_text, width)
		var y := box.position.y - 4.0 - (lines - 1) * SubtitleStyle.line_spacing()
		var c := Color(MUTED_BLUE, clampf(_detail_show * 2.0, 0.0, 1.0))
		SubtitleStyle.draw_text(_ui, font, Vector2(24, y), _scene.detail_text, width, fs, c)


func _draw_panel(view: Vector2, font: Font) -> void:
	var rows := _panel_rows()
	var w := 150.0
	var h := 16.0 + rows.size() * 12.0 + 6.0
	var r := Rect2((view.x - w) * 0.5, (view.y - h) * 0.5, w, h)
	_ui.draw_rect(r, UiTheme.BG)
	_ui.draw_rect(Rect2(r.position, Vector2(w, 1)), UiTheme.ACCENT)
	_ui.draw_string(font, r.position + Vector2(6, 11), cfg.pause_title, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_SIZE + 1, UiTheme.ACCENT)
	for i in rows.size():
		var row := Rect2(r.position.x + 4, r.position.y + 16 + i * 12, w - 8, 11)
		var focused := i == _panel_index
		_ui.draw_rect(row, Color(0.18, 0.06, 0.1, 1.0) if focused else UiTheme.PANEL)
		if focused:
			_ui.draw_rect(Rect2(row.position, Vector2(2, row.size.y)), UiTheme.ACCENT)
		_ui.draw_string(font, row.position + Vector2(6, 8), rows[i], HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_SIZE, Color.WHITE if focused else UiTheme.TEXT)
