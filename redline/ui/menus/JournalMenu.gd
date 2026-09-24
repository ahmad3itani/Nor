extends MenuScreen
## Journal (bible §20, §21): quests in progress and done, recovered memories,
## and discovery counts. Reads everything from flags/state.


func rebuild() -> void:
	clear_body()
	_panel.custom_minimum_size = Vector2(380, 0)
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
	add_label("MEMORIES", UiTheme.ACCENT)
	if Game.state.memory_fragments.is_empty():
		add_label("No fragments recovered.", UiTheme.MUTED)
	for id in Game.state.memory_fragments:
		var frag := load("res://data/lore/%s.tres" % id) as MemoryFragmentData
		if frag:
			add_label("%s  —  %s" % [frag.title, frag.text], UiTheme.TEXT, UiTheme.FONT_SIZE - 1)
	var t := SliceStats.totals()
	add_label("Secrets %d/%d    Core Shards %d    Scrap %d    Time %s    Deaths %d" % [
		SliceStats.secrets_found(), (t["secret_ids"] as Array).size(), Game.state.core_shards,
		Game.state.total_scrap(), SliceStats.format_time(Game.state.play_time_sec), Game.state.deaths], UiTheme.MUTED)
	add_button("Close", close_menu)
	focus_index(0)
