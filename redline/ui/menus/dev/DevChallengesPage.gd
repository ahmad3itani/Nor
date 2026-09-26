class_name DevChallengesPage
extends RefCounted
## Dev console "Challenges…" page (M9 D2 §8.3, T08). During a run: finish
## now as any tier, fail now (hit / attack), ghost debug, promote the PB ghost
## (editor only). Otherwise: start any challenge ignoring unlocks, clear
## records, the campaign clock. Dev text is English only. Rows that start or
## end a run close the console first (a paused tree would hold the run).


static func build(c: DevConsole) -> void:
	if Challenges.active():
		_run_rows(c)
		return
	c.add_label(ChallengeDevActions.campaign_summary(), UiTheme.MUTED, UiTheme.FONT_SIZE - 2)
	var rows: Array = []
	for ch in ChallengeLibrary.all():
		var tag := "" if ChallengeLibrary.unlocked(ch) else "  (locked)"
		rows.append(["Start %s%s" % [ch.id, tag], func() -> void:
			c.close_menu()
			# Deferred: the console's close has to unpause first.
			(func() -> void: ChallengeDevActions.start(ch.id)).call_deferred()])
	rows.append(["Clear all challenge records", func() -> void:
		ChallengeDevActions.clear_records()
		c.set_detail("records cleared")])
	rows.append(["Reset campaign clock", func() -> void:
		ChallengeDevActions.reset_campaign_clock()
		c._refresh()])
	c.add_rows(rows)


static func _run_rows(c: DevConsole) -> void:
	var ch := Challenges.current()
	c.add_label("RUN %s · attempt %d · %s" % [ch.id, Challenges.attempt(), RunClock.format(Challenges.clock.frames)],
		UiTheme.MUTED, UiTheme.FONT_SIZE - 2)
	var rows: Array = []
	if ch.score_kind != ChallengeData.ScoreKind.RANK:
		for tier in RankLadder.COUNT:
			rows.append(["Finish now: %s" % RankLadder.name(tier), func() -> void:
				c.close_menu()
				ChallengeDevActions.finish_as(tier)])
	rows.append(["Fail now: hit", func() -> void:
		c.close_menu()
		ChallengeDevActions.fail_now(&"hit")])
	rows.append(["Fail now: attack", func() -> void:
		c.close_menu()
		ChallengeDevActions.fail_now(&"attack")])
	rows.append(["Ghost debug: %s" % ("on" if ChallengeDevActions.ghost_debug else "off"), func() -> void:
		ChallengeDevActions.set_ghost_debug(not ChallengeDevActions.ghost_debug)
		c._refresh()])
	rows.append(["Clear this challenge's records", func() -> void:
		ChallengeDevActions.clear_records(ch.id)
		c.set_detail("records for %s cleared" % ch.id)])
	if OS.has_feature("editor"):
		rows.append(["Promote PB ghost to rig ghost", func() -> void:
			var path := ChallengeDevActions.promote_pb_ghost(ch.id)
			c.set_detail(("wrote " + path) if path != "" else "no PB ghost for this revision")])
	c.add_rows(rows)
