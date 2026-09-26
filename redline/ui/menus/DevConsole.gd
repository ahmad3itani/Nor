extends MenuScreen
## Dev console (bible §34 internal tools), ` (backquote) in debug builds.
## Controller-navigable like every menu; pages: main, teleport, spawn,
## save-state inspector, and (M8) Story… with its theatres.
##
## M8 rules for the Story pages:
## - A row that plays a sequence or an ending closes the console FIRST and
##   plays deferred: the console pauses the tree, SequencePlayer is PAUSABLE
##   and the cinematic overlay (layer 65) sits under menus (80), so a play
##   started under the open console would stay frozen and hidden.
## - A memory row keeps the console: MemoryScenePlayer runs ALWAYS at layer
##   85. The console hides itself (the tree stays paused by the console, so
##   the player will not unpause it) and comes back, rebuilt and focused on
##   the row that started it, on memory_playback_finished (as JournalMenu).
## - Every page stays inside the 270 px viewport: more than PAGE_ROWS rows
##   paginate behind a "More…" row.

## Rows per page, "More…" included (title, Back and Close come on top):
## 11 rows + 2 at the button height of UiTheme is the most that fits 270 px.
const PAGE_ROWS := 11
## Sub-page -> the page its Back returns to.
const PARENT := {
	&"seq": &"story", &"mem": &"story", &"presets": &"story", &"arcs": &"story",
	&"endings": &"story", &"intros": &"story",
}
const VIEW_NAMES := ["full", "repeat", "auto"]
const BOSSES := [["collector_drone", "Collector Drone"], ["warden_krail", "Warden Krail"]]

var page: StringName = &"main"
## Page of a paginated list (reset when the page changes).
var list_page: int = 0
## Sequence theatre view: 0 full (first view), 1 repeat, 2 auto (seen flag).
var view_mode: int = 0
## Sequence theatre lists data/sequences/test_* too.
var show_test_sequences: bool = false
static var hitboxes: HitboxView
static var perf: PerfGraph
static var inspector: SequenceInspector

var _detail: Label
var _resume_focus: int = 0


func open_menu() -> void:
	page = &"main"
	list_page = 0
	super.open_menu()
	focus_index(0)


func rebuild() -> void:
	clear_body()
	_detail = null
	_panel.custom_minimum_size = Vector2(420, 0)
	add_label("DEV CONSOLE  —  %s" % _title(), UiTheme.ACCENT, UiTheme.FONT_SIZE + 1)
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
		&"story":
			_story_page()
		&"seq":
			_sequence_page()
		&"mem":
			_memory_page()
		&"presets":
			_preset_page()
		&"arcs":
			_arcs_page()
		&"endings":
			_endings_page()
		&"intros":
			_intros_page()
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
			add_button("Story…", _go.bind(&"story"))
			add_button("Hitboxes: %s" % ("on" if is_instance_valid(hitboxes) else "off"), _toggle_hitboxes)
			add_button("Performance graph: %s" % ("on" if is_instance_valid(perf) else "off"), _toggle_perf)
	if page != &"main":
		add_button("Back", _go.bind(PARENT.get(page, &"main")))
	add_button("Close", close_menu)


func _title() -> String:
	match page:
		&"seq":
			return "SEQUENCE THEATRE"
		&"mem":
			return "MEMORY THEATRE"
		&"presets":
			return "STORY STATE"
		&"arcs":
			return "ARCS"
		&"endings":
			return "ENDING THEATRE"
		&"intros":
			return "BOSS INTROS"
	return String(page).to_upper()


func _go(p: StringName) -> void:
	page = p
	list_page = 0
	rebuild()
	focus_index(0)


## Adds `rows` ([text, on_press, on_focus, enabled]) as buttons, PAGE_ROWS
## per page; a longer list gets a "More…" row that turns the page.
func _add_rows(rows: Array) -> void:
	var shown := rows
	if rows.size() > PAGE_ROWS:
		var per := PAGE_ROWS - 1
		var pages := ceili(float(rows.size()) / per)
		list_page = posmod(list_page, pages)
		shown = rows.slice(list_page * per, (list_page + 1) * per)
		shown.append(["More…  (%d/%d)" % [list_page + 1, pages], _next_list_page, Callable(), true])
	for r: Array in shown:
		var press: Callable = r[1]
		if not press.is_valid():
			press = func() -> void: pass
		add_button(r[0], press, r[2] if r.size() > 2 else Callable(), r[3] if r.size() > 3 else true)


func _next_list_page() -> void:
	var i := focused_index()
	list_page += 1
	rebuild()
	focus_index(i)


# --- Story pages (M8, T09) -------------------------------------------------------

func _story_page() -> void:
	add_button("Sequence theatre…", _go.bind(&"seq"))
	add_button("Memory theatre…", _go.bind(&"mem"))
	add_button("Story state ▸", _go.bind(&"presets"))
	add_button("Arcs…", _go.bind(&"arcs"))
	add_button("Ending theatre…", _go.bind(&"endings"))
	add_button("Replay boss intro (full)…", _go.bind(&"intros"))
	add_button("Sequence inspector: %s" % ("on" if is_instance_valid(inspector) else "off"), _toggle_inspector)
	add_button("Theatre test fixtures: %s" % ("shown" if show_test_sequences else "hidden"), _toggle_test_sequences)


## A view-mode row, then one row per sequence: the Act I scenes, the barks,
## the endings (and data/sequences/test_* only with the fixture toggle).
func _sequence_page() -> void:
	var rows: Array = []
	rows.append(["View: %s" % VIEW_NAMES[view_mode], _cycle_view])
	var list := DevActions.sequences(show_test_sequences)
	list.sort_custom(func(a: SequenceData, b: SequenceData) -> bool:
		var ga := _sequence_group(a)
		var gb := _sequence_group(b)
		return ga < gb if ga != gb else a.id < b.id)
	for seq in list:
		var tag := ""
		match _sequence_group(seq):
			0:
				tag = "  (%s)" % seq.room.get_file().get_basename()
			1:
				tag = "  [bark]"
			2:
				tag = "  [ending]"
		rows.append(["%s%s" % [seq.id, tag], _play_sequence_row.bind(seq.id)])
	_add_rows(rows)


## 0 Act I scene, 1 bark, 2 ending, 3 test fixture (theatre row order).
static func _sequence_group(seq: SequenceData) -> int:
	if seq.id.begins_with("test_"):
		return 3
	if DevActions.ending_for_sequence(seq.id):
		return 2
	return 0 if seq.lock_input else 1


func _cycle_view() -> void:
	var i := focused_index()
	view_mode = (view_mode + 1) % VIEW_NAMES.size()
	rebuild()
	focus_index(i)


func _toggle_test_sequences() -> void:
	var i := focused_index()
	show_test_sequences = not show_test_sequences
	list_page = 0
	rebuild()
	focus_index(i)


func _play_sequence_row(id: String) -> void:
	close_menu()
	var ending := DevActions.ending_for_sequence(id)
	if ending:
		(func() -> void: DevActions.play_ending(ending.id)).call_deferred()
		return
	var view: int = [1, 0, -1][view_mode]
	(func() -> void: DevActions.preview_sequence(id, view)).call_deferred()


func _memory_page() -> void:
	var rows: Array = []
	for s in MemoryLibrary.all_scenes():
		var state := "◆ remembered" if MemoryLibrary.is_seen(s.id) else ("◇ waiting" if MemoryLibrary.is_unlocked(s) else "· locked")
		rows.append(["%s  %s" % [s.id, state], _play_memory_row.bind(s.id)])
	rows.append(["Grant all fragments", func() -> void:
		DevActions.grant_all_fragments()
		_refresh()])
	rows.append(["Reset memories", func() -> void:
		DevActions.reset_memories()
		_refresh()])
	_add_rows(rows)


func _play_memory_row(id: String) -> void:
	if not is_instance_valid(MemoryScenePlayer.active_instance):
		EventBus.hint_requested.emit("DEV: no memory player in this tree", 1.5)
		return
	_resume_focus = focused_index()
	# Hidden (MenuScreen then ignores ui_cancel, so the vignette's input
	# wins); the tree stays paused by the console.
	visible = false
	get_viewport().gui_release_focus()
	if not EventBus.memory_playback_finished.is_connected(_on_memory_done):
		EventBus.memory_playback_finished.connect(_on_memory_done, CONNECT_ONE_SHOT)
	DevActions.play_memory(id)


func _on_memory_done(_source: StringName) -> void:
	visible = true
	rebuild()
	focus_index(_resume_focus)


func _preset_page() -> void:
	var rows: Array = []
	for p in StoryPresets.all():
		rows.append(["Apply: %s" % (p.label if p.label != "" else p.id), func() -> void:
			DevActions.apply_story_preset(p.id)
			EventBus.hint_requested.emit("DEV: story state %s" % p.id, 1.5)
			_refresh()])
	_add_rows(rows)


func _arcs_page() -> void:
	add_label(DevActions.arc_summary(), UiTheme.TEXT, UiTheme.FONT_SIZE - 2)
	var rows: Array = []
	if Game.arcs:
		for a in Game.arcs.arcs:
			var i := a.current_index()
			if i < a.stages.size():
				var stage_id := a.stages[i].id
				rows.append(["%s: force %s" % [a.npc_id, stage_id], func() -> void:
					DevActions.force_arc_stage(a.npc_id, stage_id)
					_refresh()])
			else:
				rows.append(["%s: at its last stage" % a.npc_id, Callable(), Callable(), false])
	rows.append(["Reset arcs", func() -> void:
		DevActions.reset_arcs()
		_refresh()])
	_add_rows(rows)


func _endings_page() -> void:
	var rows: Array = []
	for e in EndingResolver.all():
		rows.append(["%s%s" % [e.title, "  [hidden]" if e.hidden else ""], _play_ending_row.bind(e.id), _show_explain.bind(e.id)])
	var resolved := EndingResolver.resolve()
	if resolved:
		rows.append(["Play resolved ending (%s)" % resolved.title, _play_ending_row.bind(resolved.id)])
	else:
		rows.append(["Play resolved ending: none in Act I", Callable(), Callable(), false])
	rows.append(["Replay Act I close + card", func() -> void:
		close_menu()
		(func() -> void: DevActions.replay_act1_close()).call_deferred()])
	_add_rows(rows)
	_detail = add_label("", UiTheme.MUTED, UiTheme.FONT_SIZE - 2)
	var all := EndingResolver.all()
	if not all.is_empty():
		_show_explain(all[0].id)


func _show_explain(id: String) -> void:
	if is_instance_valid(_detail):
		var e := EndingResolver.by_id(id)
		_detail.text = "%s: %s\n%s" % [e.title, e.tagline, DevActions.ending_explain(id)] if e else ""


func _play_ending_row(id: String) -> void:
	close_menu()
	(func() -> void: DevActions.play_ending(id)).call_deferred()


func _intros_page() -> void:
	for b: Array in BOSSES:
		add_button("%s (full intro)" % b[1], func() -> void:
			close_menu()
			(func() -> void: DevActions.replay_boss_intro(b[0])).call_deferred())


## Rebuild in place, keeping the focused row.
func _refresh() -> void:
	var i := focused_index()
	rebuild()
	focus_index(i)


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


func _toggle_inspector() -> void:
	var i := focused_index()
	if is_instance_valid(inspector):
		inspector.queue_free()
		inspector = null
	else:
		inspector = SequenceInspector.new()
		get_tree().root.add_child(inspector)
	rebuild()
	focus_index(i)
