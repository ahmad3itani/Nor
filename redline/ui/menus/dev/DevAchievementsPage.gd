class_name DevAchievementsPage
extends RefCounted
## Dev console "Achievements…" page (M9 D1 §4.8, T07): the tool rows first
## (unlock all, reset with a confirming second press, evaluate now, the
## dev-profile earn override, a test toast), then one "[x] title" row per
## achievement that toggles it. Rows paginate through DevConsole.add_rows
## (PAGE_ROWS, "More…"). Dev text is English only.


static func build(c: DevConsole) -> void:
	c.add_label(AchievementDevActions.summary(), UiTheme.MUTED, UiTheme.FONT_SIZE - 2)
	var rows: Array = []
	rows.append(["Unlock all achievements", func() -> void:
		var n := AchievementDevActions.unlock_all()
		c._refresh()
		c.set_detail("%d unlocked" % n)])
	var reset_label := "Reset achievements + lifetime stats: press again to confirm" if AchievementDevActions.reset_armed \
		else "Reset achievements + lifetime stats"
	rows.append([reset_label, func() -> void:
		var done := AchievementDevActions.reset_pressed()
		c._refresh()
		c.set_detail("achievements and lifetime stats reset" if done else "press again to reset")])
	rows.append(["Evaluate now", func() -> void:
		AchievementDevActions.evaluate_now()
		c.set_detail("evaluating on the next frame")])
	rows.append(["Dev profiles earn: %s" % ("on" if Platform.dev_allow_tainted else "off"), func() -> void:
		AchievementDevActions.set_dev_earn(not Platform.dev_allow_tainted)
		c._refresh()])
	rows.append(["Test toast", func() -> void:
		c.set_detail("toast queued (shows once the console closes)" if AchievementDevActions.test_toast() else "no toast")])
	for r: Array in AchievementDevActions.rows():
		var id: String = r[0]
		rows.append([r[1], func() -> void:
			AchievementDevActions.toggle(id)
			c._refresh()])
	c.add_rows(rows)
