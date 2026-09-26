class_name DevDemoPage
extends RefCounted
## Dev console "Demo & build…" page (M9 D6 §6.3): what build this is, a demo
## session in any build, the end card, barrier drawing, the gate bypass, a
## teleport to the border and the probe line. Dev text is English only.


static func build(c: DevConsole) -> void:
	c.add_label(DemoDevActions.summary(), UiTheme.MUTED, UiTheme.FONT_SIZE - 2)
	c.add_button("Demo mode (session): %s" % ("on" if DemoDevActions.demo_session_on() else "off"), func() -> void:
		DemoDevActions.set_demo_session(not DemoDevActions.demo_session_on())
		c._refresh())
	c.add_button("Show demo end card", func() -> void:
		c.close_menu()
		DemoDevActions.show_demo_end())
	c.add_button("Barriers: %s" % ("shown" if DemoBarrier.debug_draw else "hidden"), func() -> void:
		DemoBarrier.set_debug_draw(not DemoBarrier.debug_draw)
		c._refresh())
	c.add_button("Gate bypass: %s" % ("on" if DemoGate.dev_bypass else "off"), func() -> void:
		DemoGate.dev_bypass = not DemoGate.dev_bypass
		c._refresh())
	c.add_button("Teleport to the demo border", func() -> void:
		c.close_menu()
		DemoDevActions.teleport_to_border())
	c.add_button("Print build info", func() -> void:
		DemoDevActions.print_build_info())
