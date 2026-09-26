class_name DevNullPage
extends RefCounted
## Dev console "The Null…" page (M9 D3 §3.12; the player reads "Deep Rig"):
## start any stratum or the descent (unlock and Dash requirement ignored),
## grant null_open, set or clear the depth flag (both taint the profile) and
## clear the Deep Rig records. Dev text is English only. A start row closes
## the console first (MenuHost pauses the tree under it) and starts deferred.


static func build(c: DevConsole) -> void:
	c.add_label(NullDevActions.summary(), UiTheme.MUTED, UiTheme.FONT_SIZE - 2)
	for ch in NullDevActions.challenges():
		var id := ch.id
		c.add_button("Start: %s" % ch.title, func() -> void:
			c.close_menu()
			_start_deferred.call_deferred(id))
	c.add_button("Grant null_open (taints)", func() -> void:
		NullDevActions.grant_open()
		c._refresh())
	var depth := Game.has_flag(NullDevActions.DEPTH_FLAG)
	c.add_button("Depth flag: %s (taints)" % ("set → clear" if depth else "clear → set"), func() -> void:
		NullDevActions.set_depth(not depth)
		c._refresh())
	c.add_button("Clear Deep Rig records", func() -> void:
		NullDevActions.clear_records()
		c._refresh())


static func _start_deferred(id: String) -> void:
	NullDevActions.start(id)
