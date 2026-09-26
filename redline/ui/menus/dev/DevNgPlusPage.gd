class_name DevNgPlusPage
extends RefCounted
## Dev console "NG+…" page (M9 D3 §3.12): start NG+ now with or without the
## remix, flip the live remix option or force every remix on, print the
## remix report, and put an archived cycle back. Dev text is English only.

const MAX_ARCHIVE_ROWS := 4


static func build(c: DevConsole) -> void:
	c.add_label("Cycle %d (%s) · remix %s%s · early Dash %s" % [NewGamePlus.cycle(), NewGamePlus.cycle_label(NewGamePlus.cycle()),
		"on" if NewGamePlus.remix_on() else "off", " (forced)" if RemixLibrary.force_active else "",
		"on" if NewGamePlus.keep_dash_on() else "off"], UiTheme.MUTED, UiTheme.FONT_SIZE - 2)
	for remix: bool in [true, false]:
		c.add_button("NG+ now (remix %s)" % ("on" if remix else "off"), func() -> void:
			c.close_menu()
			if not NgPlusDevActions.start_now(remix):
				push_warning("NG+ refused: %s" % NewGamePlus.last_refusal))
	c.add_button("Remix option: %s" % ("on" if NewGamePlus.remix_on() else "off"), func() -> void:
		NgPlusDevActions.toggle_remix()
		c._refresh())
	c.add_button("Force every remix: %s" % ("on" if RemixLibrary.force_active else "off"), func() -> void:
		NgPlusDevActions.toggle_force()
		c._refresh())
	c.add_button("Print remix report", func() -> void:
		NgPlusDevActions.print_remix_report())
	# The newest few only: the page must stay inside DevConsole.PAGE_ROWS.
	var arch := NgPlusDevActions.archives()
	for a: Array in arch.slice(maxi(arch.size() - MAX_ARCHIVE_ROWS, 0)):
		var n: int = a[0]
		c.add_button("Restore archived cycle %d" % n, func() -> void:
			c.close_menu()
			if NgPlusDevActions.restore_archive(n):
				SceneRouter.transition_to(Game.respawn_room(), Game.respawn_entry()))
