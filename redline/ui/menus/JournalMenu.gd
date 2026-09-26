extends MenuScreen
## Journal (bible §20, §21): quests in progress and done, remembered memories,
## and discovery counts. Reads everything from flags/state.
##
## M8: a "Memories…" mode shows the memory gallery (a timeline strip with
## gaps, replay for remembered memories, "Remember now" for recovered ones).
## Every gallery string lives in data/memories/memory_config.tres (§37.3).
## The journal hides itself while a memory plays (the tree stays paused:
## the player sees it was already paused) and comes back on
## memory_playback_finished with focus restored.
##
## M8 T05: a "People…" button (once any character arc has a reached stage)
## switches to a PEOPLE mode, one line per arc: the person and the note of
## their latest stage (§18: consequences through people, never a score). A
## sub-mode keeps the main page inside the 270 px canvas (MenuScreen has no
## scroll); Back/ui_cancel returns to the main page with focus on the row.

var _mode: StringName = &"main"
var _card: Label
var _detail: Label
var _resume_focus: int = 0
## Main-page row to refocus when PEOPLE closes (-1 = none).
var _people_return_focus: int = -1


func open_menu() -> void:
	_mode = &"main"
	super.open_menu()


func rebuild() -> void:
	clear_body()
	_card = null
	_detail = null
	_panel.custom_minimum_size = Vector2(380, 0)
	if _mode == &"memories":
		_build_gallery()
		return
	if _mode == &"people":
		_build_people()
		return
	add_label("JOURNAL", UiTheme.ACCENT, UiTheme.FONT_SIZE + 2)
	add_label("QUESTS", UiTheme.ACCENT)
	var active := Game.quests.active_quests()
	var done := Game.quests.completed_quests()
	if active.is_empty() and done.is_empty():
		add_label("Nothing yet. People at the Relay need help.", UiTheme.MUTED)
	for q in active:
		var i := q.current_stage()
		var prog := q.stage_progress(i) if i < q.stages.size() else Vector2i.ZERO
		var tail := "  (%d/%d)" % [prog.x, prog.y] if prog.y > 1 else ""
		add_label("• %s  —  %s%s" % [q.title, q.stages[i].description, tail])
	for q in done:
		add_label("✓ %s" % q.title, UiTheme.MUTED)
	if not _people_arcs().is_empty():
		add_button("People…", show_people)
	_build_memories_section()
	var t := SliceStats.totals()
	add_label("Secrets %d/%d    Core Shards %d    Scrap %d    Time %s    Deaths %d" % [
		SliceStats.secrets_found(), (t["secret_ids"] as Array).size(), Game.state.core_shards,
		Game.state.total_scrap(), SliceStats.format_time(Game.state.play_time_sec), Game.state.deaths], UiTheme.MUTED)
	var completion: String = load("res://ui/menus/MapMenu.gd").completion_text()
	if completion != "":
		add_label(completion, UiTheme.MUTED, UiTheme.FONT_SIZE - 1)
	add_button("Close", close_menu)
	focus_index(0)


## Main-page MEMORIES: "Fragments remembered N / M" (fragment scenes only,
## once a fragment is recovered) and the gallery button.
func _build_memories_section() -> void:
	var cfg := MemoryLibrary.config()
	add_label("MEMORIES", UiTheme.ACCENT)
	var recovered := Game.state.memory_fragments.size()
	if recovered >= 1:
		add_label(cfg.remembered_line % [MemoryLibrary.remembered_fragment_count(), recovered])
	if _listed_scenes().is_empty():
		add_label(cfg.empty_text, UiTheme.MUTED)
	else:
		add_button(cfg.gallery_button, show_gallery)


## Scenes the gallery lists: remembered, or recovered and waiting. Scenes
## not yet recovered only show as a dot on the strip (never where they are).
func _listed_scenes() -> Array[MemorySceneData]:
	var out: Array[MemorySceneData] = []
	for s in MemoryLibrary.all_scenes():
		if MemoryLibrary.is_seen(s.id) or MemoryLibrary.is_unlocked(s):
			out.append(s)
	return out


func show_gallery() -> void:
	_mode = &"memories"
	rebuild()


func show_main() -> void:
	_mode = &"main"
	rebuild()
	if _people_return_focus >= 0:
		focus_index(_people_return_focus)
		_people_return_focus = -1


func show_people() -> void:
	_people_return_focus = focused_index()
	_mode = &"people"
	rebuild()


## Arcs with a reached spine stage, in tracker order.
func _people_arcs() -> Array[NpcArc]:
	var out: Array[NpcArc] = []
	if Game.arcs == null:
		return out
	for a in Game.arcs.arcs:
		if a.has_reached_any() and a.journal_note() != "":
			out.append(a)
	return out


func _build_people() -> void:
	add_label("PEOPLE", UiTheme.ACCENT, UiTheme.FONT_SIZE + 2)
	for a in _people_arcs():
		add_label("%s — %s" % [_display_name(a.npc_id), a.journal_note()], UiTheme.MUTED)
	add_button("Back", show_main)
	focus_index(0)


## The owning profile's display name (data/npcs/<npc_id>.tres).
func _display_name(npc_id: String) -> String:
	var path := "%s/%s.tres" % [NpcArc.NPC_DIR, npc_id]
	var p: NpcProfile = null
	if ResourceLoader.exists(path):
		p = load(path) as NpcProfile
	return p.display_name if p else npc_id.capitalize()


func _build_gallery() -> void:
	var cfg := MemoryLibrary.config()
	var listed := _listed_scenes()
	var acts: Array[int] = []
	for s in MemoryLibrary.all_scenes():
		if not acts.has(s.act):
			acts.append(s.act)
	acts.sort()
	for act in acts:
		var in_act := MemoryLibrary.all_scenes().filter(func(s: MemorySceneData) -> bool: return s.act == act)
		if not listed.any(func(s: MemorySceneData) -> bool: return s.act == act):
			continue
		add_label(cfg.gallery_title % cfg.act_name(act), UiTheme.ACCENT, UiTheme.FONT_SIZE + 1)
		add_label(_strip(in_act), Color("9fd8ff"))
		for s: MemorySceneData in in_act:
			if not listed.has(s):
				continue
			if MemoryLibrary.is_seen(s.id):
				add_button("%s %s" % [cfg.glyph_seen, s.display_title()], _play.bind(s.id, &"journal"), _show_card.bind(s.id))
			else:
				add_button("%s %s  %s" % [cfg.glyph_pending, s.display_title(), cfg.pending_hint], _play.bind(s.id, &"journal_first"), _show_card.bind(s.id))
	if listed.is_empty():
		add_label(cfg.empty_text, UiTheme.MUTED)
	_card = add_label("", UiTheme.TEXT, UiTheme.FONT_SIZE - 1)
	_detail = add_label("", UiTheme.MUTED, UiTheme.FONT_SIZE - 1)
	add_button(cfg.back_label, show_main)
	focus_index(0)


## "?  ◆  ?  ◇  ?  ·  ?": remembered / waiting / not yet recovered, with a
## gap between every memory and at both ends, and never a total.
func _strip(scenes: Array) -> String:
	var cfg := MemoryLibrary.config()
	var parts := PackedStringArray([cfg.glyph_gap])
	for s: MemorySceneData in scenes:
		if MemoryLibrary.is_seen(s.id):
			parts.append(cfg.glyph_seen)
		elif MemoryLibrary.is_unlocked(s):
			parts.append(cfg.glyph_pending)
		else:
			parts.append(cfg.glyph_locked)
		parts.append(cfg.glyph_gap)
	return "  ".join(parts)


## The focused row's card: the memory text and its detail line once
## remembered; nothing for a memory still waiting (its row says where).
func _show_card(id: String) -> void:
	if _card == null:
		return
	var cfg := MemoryLibrary.config()
	var s := MemoryLibrary.scene(id)
	if s == null or not MemoryLibrary.is_seen(id):
		_card.text = ""
		_detail.text = ""
		return
	_card.text = s.card_text()
	if MemoryLibrary.is_detail_found(id):
		_detail.text = cfg.detail_line % s.detail_text
	elif s.has_detail():
		_detail.text = cfg.detail_unfound_text
	else:
		_detail.text = ""


func _play(id: String, source: StringName) -> void:
	if not is_instance_valid(MemoryScenePlayer.active_instance):
		# No player in this tree: "Remember now" still counts.
		if source == &"journal_first":
			MemoryLibrary.mark_seen(id)
		rebuild()
		return
	_resume_focus = focused_index()
	# Hidden, so MenuScreen ignores ui_cancel and the vignette's input wins.
	visible = false
	get_viewport().gui_release_focus()
	if not EventBus.memory_playback_finished.is_connected(_on_memory_done):
		EventBus.memory_playback_finished.connect(_on_memory_done, CONNECT_ONE_SHOT)
	EventBus.memory_playback_requested.emit(PackedStringArray([id]), source)


func _on_memory_done(_source: StringName) -> void:
	visible = true
	rebuild()
	focus_index(_resume_focus)


func _process(delta: float) -> void:
	# In the gallery or PEOPLE, cancel steps back to the main page instead of
	# closing.
	if visible and (_mode == &"memories" or _mode == &"people") and Engine.get_process_frames() != _opened_frame and cancel_pressed():
		show_main()
		return
	super._process(delta)
