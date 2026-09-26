extends RedlineTestCase
## M9 T12 (bible §24, D4 §7.3, D-161): the colour-blind palettes. Every
## palette is complete and readable on the UI background, keeps its state
## colours apart for the eyes it targets, and the default palette is exactly
## the old per-file constants (so CaptureTour does not move with the setting
## off).

var _snap: Dictionary = {}


func before_each() -> void:
	_snap = snapshot_settings()
	Palette.invalidate()


func after_each() -> void:
	restore_settings(_snap)
	Palette.invalidate()


func test_palettes_complete() -> void:
	var pals := Palette.all()
	check(pals.size() == 3, "three palettes (default, protan_deutan, tritan)")
	var ids := []
	for p in pals:
		ids.append(p.id)
		for k in AccessPalette.SEMANTIC_KEYS:
			check(p.colors.has(k), "%s has %s" % [p.id, k])
		var errs := AccessRules.completeness_errors(p, p.id == &"default")
		check(errs.is_empty(), "%s complete: %s" % [p.id, ", ".join(errs)])
	check(ids == [&"default", &"protan_deutan", &"tritan"], "palette order follows Settings.colorblind_mode (%s)" % [ids])
	# A role falls back to its semantic key in a palette that leaves it out.
	var pd := Palette.palette(1)
	check(not pd.colors.has(&"scanner_full") and pd.resolve(&"scanner_full") == pd.resolve(&"danger"), "roles fall back to their semantic key")
	# The rule module flags a missing key.
	var broken := AccessPalette.new()
	broken.id = &"broken"
	broken.colors = {&"danger": Color.RED}
	check(not AccessRules.completeness_errors(broken, false).is_empty(), "AC-1 reports a missing key")


func test_contrast_vs_bg() -> void:
	var bg := Color(UiTheme.BG, 1.0)
	for p in Palette.all():
		for k in p.keys():
			var ratio := ColorVision.contrast(p.resolve(k), bg)
			check(ratio >= AccessRules.MIN_CONTRAST, "%s.%s contrast %.2f >= 3" % [p.id, k, ratio])
		check(AccessRules.contrast_errors(p).is_empty(), "AC-2 clean for %s" % p.id)
	check_near(ColorVision.contrast(Color.WHITE, Color.BLACK), 21.0, 0.01, "WCAG contrast of white on black")
	var dim := AccessPalette.new()
	dim.id = &"dim"
	dim.colors = {&"danger": Color(0.1, 0.05, 0.08)}
	check(not AccessRules.contrast_errors(dim).is_empty(), "AC-2 reports a colour lost on the background")


func test_cvd_state_distance_per_mode() -> void:
	# The simulation leaves greys alone and is identity for an unknown mode.
	var grey := Color(0.5, 0.5, 0.5)
	for m in ColorVision.modes():
		var g := ColorVision.simulate(grey, m)
		check_near(g.r, 0.5, 0.02, "%s keeps grey (r)" % m)
		check_near(g.b, 0.5, 0.02, "%s keeps grey (b)" % m)
	check(ColorVision.simulate(Color.RED, &"none") == Color.RED, "unknown mode is identity")
	for p in Palette.all():
		var errs := AccessRules.state_distance_errors(p)
		check(errs.is_empty(), "AC-3 %s: %s" % [p.id, ", ".join(errs)])
		for row: Array in AccessRules.state_distances(p):
			check(float(row[3]) >= p.min_state_distance, "%s under %s: %s/%s %.3f" % [p.id, row[0], row[1], row[2], row[3]])
	check(Palette.palette(1).simulations == PackedStringArray(["protan", "deutan"]), "red-green palette is checked for protan and deutan")
	check(Palette.palette(2).simulations == PackedStringArray(["tritan"]), "blue-yellow palette is checked for tritan")
	# Documented, not a failure: the default danger red and warning amber keep
	# their lightness apart under protan simulation, but their hue difference
	# (OKLab a/b) collapses; that is why the red-green palette exists.
	var d := Palette.palette(0)
	var a := ColorVision.oklab(ColorVision.simulate(d.resolve(&"danger"), &"protan"))
	var b := ColorVision.oklab(ColorVision.simulate(d.resolve(&"warning"), &"protan"))
	var a0 := ColorVision.oklab(d.resolve(&"danger"))
	var b0 := ColorVision.oklab(d.resolve(&"warning"))
	var hue_sim := Vector2(a.y, a.z).distance_to(Vector2(b.y, b.z))
	var hue_typical := Vector2(a0.y, a0.z).distance_to(Vector2(b0.y, b0.z))
	check(hue_sim < hue_typical, "protan sight loses part of the red/amber hue gap (%.3f < %.3f)" % [hue_sim, hue_typical])
	# Palette.color follows the setting.
	Settings.colorblind_mode = 1
	check(Palette.color(&"danger") == Palette.palette(1).resolve(&"danger"), "mode 1 reads the red-green palette")
	Settings.colorblind_mode = 2
	check(Palette.color(&"warning") == Palette.palette(2).resolve(&"warning"), "mode 2 reads the blue-yellow palette")
	Settings.colorblind_mode = 0
	check(Palette.color(&"warning") == Palette.palette(0).resolve(&"warning"), "mode 0 reads the default palette")


func test_default_palette_identical_to_old_constants() -> void:
	Settings.colorblind_mode = 0
	var enemy_visual := (load("res://enemies/base/EnemyVisual.gd") as GDScript).get_script_constant_map()
	var collector := (load("res://bosses/CollectorDroneBehavior.gd") as GDScript).get_script_constant_map()
	var hud := (load("res://ui/hud/CombatHud.gd") as GDScript).get_script_constant_map()
	var pairs := [
		[&"danger", enemy_visual["TELEGRAPH_COLOR"], "EnemyVisual.TELEGRAPH_COLOR"],
		[&"danger", collector["RED"], "CollectorDroneBehavior.RED"],
		[&"collector_warning", collector["AMBER"], "CollectorDroneBehavior.AMBER"],
		[&"warning", ScannerBeam.COLOR_LOW, "ScannerBeam.COLOR_LOW"],
		[&"warning", ScannerBeam.COLOR_LAMP_ON, "ScannerBeam.COLOR_LAMP_ON"],
		[&"info", ScannerBeam.COLOR_HIGH, "ScannerBeam.COLOR_HIGH"],
		[&"scanner_full", ScannerBeam.COLOR_FULL, "ScannerBeam.COLOR_FULL"],
		[&"chase_warning", ChaseDirector.AMBER, "ChaseDirector.AMBER"],
		[&"chase_danger", ChaseDirector.RED, "ChaseDirector.RED"],
		[&"chase_danger", Pursuer.RED, "Pursuer.RED"],
		[&"accent", hud["RED"], "CombatHud.RED"],
		[&"heal", hud["INJECTOR_COLOR"], "CombatHud injector"],
		[&"ammo", hud["AMMO_COLOR"], "CombatHud ammo"],
		[&"currency", hud["SCRAP_COLOR"], "CombatHud Scrap"],
		[&"safe", MapView.COL_ANCHOR, "MapView.COL_ANCHOR"],
		[&"map_gate", MapView.COL_GATE, "MapView.COL_GATE"],
		[&"map_note", MapView.COL_NOTE, "MapView.COL_NOTE"],
		[&"accent", UiTheme.ACCENT, "UiTheme.ACCENT"],
	]
	for row: Array in pairs:
		var got := Palette.color(row[0])
		var want: Color = row[1]
		# 8 bits per channel is what reaches the screen.
		check(got.to_html(true) == want.to_html(true), "%s: palette %s is %s, constant %s" % [row[2], row[0], got.to_html(), want.to_html()])
	check(ScannerBeam.color_for(ScannerData.Mode.FULL).to_html() == ScannerBeam.COLOR_FULL.to_html(), "scanner FULL colour unchanged")
	var focus := UiTheme.get_theme().get_stylebox("focus", "Button") as StyleBoxFlat
	check(focus.border_color.to_html() == UiTheme.ACCENT.to_html(), "default theme accent unchanged")
	# A colour-blind palette moves the theme accent too (the cache is keyed by mode).
	Settings.colorblind_mode = 1
	var focus_pd := UiTheme.get_theme().get_stylebox("focus", "Button") as StyleBoxFlat
	check(focus_pd.border_color.to_html() == Palette.palette(1).resolve(&"accent").to_html(), "red-green accent in the theme")
