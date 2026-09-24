extends MenuScreen
## End-of-slice card (M3): what you did, what you missed, and a pointer at
## the Dash gate. The world stays playable afterwards.


func rebuild() -> void:
	clear_body()
	var t := SliceStats.totals()
	add_label("LOWLIGHT  —  VERTICAL SLICE COMPLETE", UiTheme.ACCENT, UiTheme.FONT_SIZE + 2)
	add_label("Warden Krail is down. The Dash module hums in your chest, next to the Core.")
	add_label("Time %s    Deaths %d" % [SliceStats.format_time(Game.state.play_time_sec), Game.state.deaths])
	add_label("Secrets %d / %d    Memory fragments %d / %d    Core Shards %d / %d" % [
		SliceStats.secrets_found(), (t["secret_ids"] as Array).size(), Game.state.memory_fragments.size(),
		t["fragments"], Game.state.core_shards, t["core_shards"]])
	add_label("Dead Air: %s" % ("complete" if Game.has_flag("dead_air_complete") else "unfinished"), UiTheme.MUTED)
	add_label("Something across the Flooded Alley was always just out of reach. Try it with the Dash.", UiTheme.MUTED)
	add_label("Thanks for playtesting. Please send your answers to the checklist in Docs/M3_VERTICAL_SLICE_REPORT.md.", UiTheme.MUTED)
	add_button("Keep exploring", close_menu)
	focus_index(0)
