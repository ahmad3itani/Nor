class_name DevAccessibilityPage
extends RefCounted
## Dev console "Accessibility…" page (M9 D4 §12): presets for the §24
## options, the adaptive-assist advisor and the controls. Every row is an
## AccessibilityDevActions function. Dev text is English only.


static func build(c: DevConsole) -> void:
	c.add_label(AccessibilityDevActions.summary(), UiTheme.MUTED, UiTheme.FONT_SIZE - 2)
	c.add_rows([
		["Preset: all assists on", func() -> void:
			AccessibilityDevActions.apply_all_assists()
			c._refresh()],
		["Preset: high contrast + 150 % + strong dim", func() -> void:
			AccessibilityDevActions.apply_readable_preset()
			c._refresh()],
		["Cycle colour-blind mode", func() -> void:
			AccessibilityDevActions.cycle_colorblind()
			c._refresh()],
		["Restore default settings", func() -> void:
			AccessibilityDevActions.restore_defaults()
			c._refresh()],
		["Trigger assist suggestion here", func() -> void:
			# The console closes first: MenuHost refuses while a menu is open.
			c.close_menu()
			AccessibilityDevActions.trigger_suggestion_here.call_deferred()],
		["Advisor quiet: %s" % ("on" if AssistAdvisor.dev_quiet else "off"), func() -> void:
			AccessibilityDevActions.toggle_advisor_quiet()
			c._refresh()],
		["Reset controls to defaults", func() -> void:
			AccessibilityDevActions.reset_controls()
			c._refresh()],
		["Print bindings", func() -> void:
			AccessibilityDevActions.print_bindings()],
	])
