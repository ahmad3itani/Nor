extends MenuScreen
## The Act I card (M3 card, reworded in M7, driven by ActData in M8, D-131):
## "ACT I COMPLETE  —  RUN", what you did, what you missed, where things
## stand with the people (no score, bible §18), and a pointer at the three
## Dash gates. The world stays playable afterwards, and the §44 kit flow
## (survey button, Keep exploring) is unchanged.
##
## Height: the panel must fit the 270 px canvas with Playtest recording on
## and every optional line present (MenuScreen does not scroll). If an edit
## breaks that, lower act1.tres max_standing; never drop the survey button.

const ACT := 1


func rebuild() -> void:
	clear_body()
	var t := SliceStats.totals()
	var act := ActLibrary.act(ACT)
	var header := "ACT %s COMPLETE  —  %s" % [ActData.roman(ACT), act.name if act else "RUN"]
	add_label(header, UiTheme.ACCENT, UiTheme.FONT_SIZE + 2)
	add_label("Warden Krail is down. The Dash module hums in your chest, next to the Core.")
	add_label("Time %s    Deaths %d" % [SliceStats.format_time(Game.state.play_time_sec), Game.state.deaths])
	add_label("Secrets %d / %d    Memory fragments %d / %d    Core Shards %d / %d" % [
		SliceStats.secrets_found(), (t["secret_ids"] as Array).size(), Game.state.memory_fragments.size(),
		t["fragments"], Game.state.core_shards, t["core_shards"]])
	# Same fragment-only count as the journal, so N never exceeds the
	# fragments recovered.
	var recovered := Game.state.memory_fragments.size()
	if recovered >= 1:
		add_label(MemoryLibrary.config().remembered_line % [MemoryLibrary.remembered_fragment_count(), recovered])
	add_label("Dead Air: %s" % ("complete" if Game.has_flag("dead_air_complete") else "unfinished"), UiTheme.MUTED)
	var standing := ActLibrary.standing_lines(act)
	if not standing.is_empty():
		add_label("WHERE THINGS STAND", UiTheme.ACCENT)
		for line in standing:
			add_label(line, UiTheme.MUTED)
	add_label("Three ledges were always just out of reach: the Flooded Alley, the Escape Tunnel, the Smuggler Route. Try them with the Dash.", UiTheme.MUTED)
	if Playtest.is_recording():
		add_label("Thanks for playtesting! Two minutes of questions help more than anything else.", UiTheme.MUTED)
		add_button("Answer the playtest survey", func() -> void:
			close_menu()
			EventBus.menu_requested.emit(&"survey"))
	else:
		add_label("Thanks for playtesting. Please answer the checklist in Docs/PLAYTEST_KIT.md.", UiTheme.MUTED)
	add_button("Keep exploring", close_menu)
	focus_index(0)
