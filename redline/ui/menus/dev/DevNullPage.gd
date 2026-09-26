class_name DevNullPage
extends RefCounted
## Dev console "The Null…" page (M9 D3 §3.12; the player reads "Deep Rig"):
## start any stratum or the descent (unlock and Dash requirement ignored),
## grant null_open, set or clear the depth flag (both taint the profile) and
## clear the Deep Rig records. The flag rows are disabled mid-run. Dev text is English only. A start row closes
## the console first (MenuHost pauses the tree under it) and starts deferred.


static func build(c: DevConsole) -> void:
	c.add_label(NullDevActions.summary(), UiTheme.MUTED, UiTheme.FONT_SIZE - 2)
	for ch in NullDevActions.challenges():
		var id := ch.id
		c.add_button("Start: %s" % ch.title, func() -> void:
			c.close_menu()
			_start_deferred.call_deferred(id))
	# Mid-run the flags would land in the sandbox and be thrown away.
	var editable := NullDevActions.flags_editable()
	var note := "taints" if editable else "not mid-run"
	c.add_button("Grant null_open (%s)" % note, func() -> void:
		NullDevActions.grant_open()
		c._refresh(), Callable(), editable)
	var depth := ChallengeLibrary.profile_holds("flag:" + NullDevActions.DEPTH_FLAG)
	c.add_button("Depth flag: %s (%s)" % ["set → clear" if depth else "clear → set", note], func() -> void:
		NullDevActions.set_depth(not depth)
		c._refresh(), Callable(), editable)
	c.add_button("Clear Deep Rig records", func() -> void:
		NullDevActions.clear_records()
		c._refresh())


static func _start_deferred(id: String) -> void:
	NullDevActions.start(id)
