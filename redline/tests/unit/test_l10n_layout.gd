extends RedlineTestCase
## M9 D5 §11.1 text fit under the pseudo-locale en_XA (accented, 35-50 %
## longer): every player menu (each Settings page, the Journal pages, the
## shops, the M9 screens) at UI size 100 % and 150 %, the HUD strings, and
## every subtitle line at subtitle size Large. A row that would ellipsize
## fails: the ellipsis is a safety net, not the design (shorten or wrap).
## Also the font rules of §10: no direct ThemeDB.fallback_font outside
## UiTheme (debug drawing exempt) and every enabled locale's glyphs in its
## font chain. The TestRunner puts the locale back to en after every test.

const H := preload("res://tests/fixtures/challenges/ChallengeHarness.gd")
const HUD := preload("res://ui/hud/CombatHud.gd")
const PSEUDO := "en_XA"
const VIEW := Vector2(480, 270)
const TMP_CFG := "user://test_l10n_layout.cfg"
## UI sizes the fit test runs at (100 % and 150 %).
const UI_SCALES := [0, 2]
## Debug-only drawing that may keep the engine font (R13.1).
const FALLBACK_EXEMPT := ["res://ui/UiTheme.gd", "res://ui/debug/PerfGraph.gd", "res://world/templates/JumpArcPreview.gd",
	"res://world/props/CeilingTracker.gd", "res://bosses/CollectorDroneBehavior.gd", "res://interactables/Breaker.gd"]
## Source roots scanned for ThemeDB.fallback_font.
const CODE_ROOTS := ["res://accessibility", "res://audio", "res://autoload", "res://bosses", "res://challenges",
	"res://cinematics", "res://circuits", "res://combat", "res://dialogue", "res://enemies", "res://input",
	"res://interactables", "res://l10n", "res://platform", "res://player", "res://progression", "res://quests",
	"res://release", "res://story", "res://ui", "res://vfx", "res://weapons", "res://world"]
## Subtitle boxes may take at most this share of the view height.
const SUBTITLE_MAX_SHARE := 0.4

var h: H
var _snap: Dictionary = {}
var _menus: Array[Node] = []
## Pages _check_page has measured (the walk is not vacuous).
var _pages: int = 0


func before_each() -> void:
	h = H.new(self, "l10n_layout")
	h.setup()
	_snap = snapshot_settings()
	Settings.remove_settings_files(TMP_CFG)
	# SettingsMenu.close_menu saves: point it at a temp file.
	Settings.load_settings(TMP_CFG)
	Settings.apply_defaults()
	Settings.first_run = false
	InputBindings.apply({})
	ChallengeLibrary.data_dir = ChallengeLibrary.DEFAULT_DIR
	ChallengeLibrary.clear_cache()
	AchievementLibrary.clear_cache()
	UiTheme.invalidate()
	_menus.clear()


func after_each() -> void:
	for m in _menus:
		if is_instance_valid(m):
			if m is MenuScreen and (m as MenuScreen).is_open():
				(m as MenuScreen).close_menu()
			m.queue_free()
	_menus.clear()
	MenuHost.context = {}
	get_tree().paused = false
	Settings.remove_settings_files(TMP_CFG)
	restore_settings(_snap)
	await h.teardown()
	Platform.reset_after_tests()
	UiTheme.invalidate()


func _pseudo() -> void:
	Loc.set_locale(PSEUDO)
	check(Loc.locale() == PSEUDO and Loc.t("Resume") != "Resume", "the pseudo-locale is active")


# --- Menus ---------------------------------------------------------------------------

func _screen(script: String, ctx: Dictionary = {}) -> MenuScreen:
	var m: MenuScreen = (load(script) as GDScript).new()
	add_child(m)
	_menus.append(m)
	m.ctx = ctx
	return m


func _open(script: String, ctx: Dictionary = {}) -> MenuScreen:
	var m := _screen(script, ctx)
	m.open_menu()
	return m


## Rows of `m` whose text would not fit (the row would ellipsize), and a
## panel wider than the canvas.
func misfits(m: MenuScreen) -> PackedStringArray:
	for i in 2:
		await get_tree().process_frame
	var out := PackedStringArray()
	for n in m._body.get_children():
		if not n is Button or n.is_queued_for_deletion() or not (n as Button).visible:
			continue
		var b := n as Button
		var f := b.get_theme_font(&"font")
		var fs := b.get_theme_font_size(&"font_size")
		var sb := b.get_theme_stylebox(&"normal")
		var pad := sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT) if sb else 0.0
		var need := f.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + pad
		if need > b.size.x + 0.5:
			out.append("\"%s\" needs %.0f px, row is %.0f" % [b.text, need, b.size.x])
	var w := m._panel.get_combined_minimum_size().x
	if w > VIEW.x:
		out.append("panel %.0f px wider than the canvas" % w)
	return out


## Checks one open page: rows fit, the panel fits the canvas (scrolling).
func _check_page(m: MenuScreen, what: String) -> void:
	_pages += 1
	var bad := await misfits(m)
	check(bad.is_empty(), "%s: %s" % [what, "; ".join(bad)])
	var ph := await panel_height(m)
	check(ph <= VIEW.y, "%s: panel %.0f px fits or scrolls" % [what, ph])


## Settings pages a player can reach (test_settings_menu's walk).
func _settings_pages(m: MenuScreen) -> Array:
	var out: Array = [[]]
	for p in Settings.settings_catalog().pages:
		if p.link_label != "":
			out.append([p.id])
	out.append([&"controls", &"action"])
	out.append([&"visual", &"confirm"])
	return out


func _settings_open(m: MenuScreen, path: Array) -> void:
	m.ctx = {}
	m.open_menu()
	for id: StringName in path:
		match id:
			&"action":
				m.call("_open_action", &"jump")
			&"confirm":
				for c in m._body.get_children():
					if c is Button and (c as Button).text.begins_with(Loc.t("Reset")):
						(c as Button).pressed.emit()
						break
			_:
				m.call("_go", id)


func _check_all_menus(scale_i: int) -> void:
	var tag := "ui %d" % scale_i
	# Pause, Title, Loadout, Map, SliceEnd.
	for s in ["PauseMenu", "LoadoutMenu", "MapMenu", "SliceEndMenu"]:
		var m := _open("res://ui/menus/%s.gd" % s)
		await _check_page(m, "%s %s" % [tag, s])
		m.close_menu()
	var title := _open("res://ui/menus/TitleMenu.gd")
	await _check_page(title, "%s TitleMenu" % tag)
	title.close_menu()
	# Settings: every page.
	var settings := _screen("res://ui/menus/SettingsMenu.gd")
	for path in _settings_pages(settings):
		_settings_open(settings, path)
		await _check_page(settings, "%s Settings %s" % [tag, str(path)])
		settings.close_menu()
	# Journal: main, people, memories.
	var j := _open("res://ui/menus/JournalMenu.gd")
	await _check_page(j, "%s Journal main" % tag)
	j.call("show_people")
	await _check_page(j, "%s Journal people" % tag)
	j.call("show_gallery")
	await _check_page(j, "%s Journal memories" % tag)
	j.close_menu()
	# Every shop.
	for path in DataDir.list_files("res://data/shops", "tres"):
		var shop := _screen("res://ui/menus/ShopMenu.gd")
		shop.call("open_shop", load(path))
		await _check_page(shop, "%s %s" % [tag, path.get_file()])
		shop.close_menu()
	# Achievements list and records.
	var ach := _open("res://ui/menus/AchievementsMenu.gd")
	await _check_page(ach, "%s Achievements" % tag)
	ach.call("show_records")
	await _check_page(ach, "%s Achievements records" % tag)
	ach.close_menu()
	# Challenges: the list, every detail page, the ranks page, a result card.
	var ch := _open("res://ui/menus/ChallengesMenu.gd")
	await _check_page(ch, "%s Challenges list" % tag)
	for c: ChallengeData in ChallengeLibrary.all():
		ch.call("show_detail", c)
		await _check_page(ch, "%s Challenge %s" % [tag, c.id])
	ch.call("show_ranks")
	await _check_page(ch, "%s Challenge ranks" % tag)
	ch.close_menu()
	for c: ChallengeData in ChallengeLibrary.all():
		var card := _open("res://ui/menus/ChallengeResultMenu.gd", {"result": _finished(c)})
		await _check_page(card, "%s result %s" % [tag, c.id])
		card.close_menu()
	# NG+, the assist suggestion (every rule), the demo end card.
	var ng := _open("res://ui/menus/NgPlusMenu.gd", {"from": "title"})
	await _check_page(ng, "%s NgPlus" % tag)
	ng.close_menu()
	var acfg := Settings.config()
	for r in acfg.rules if acfg else []:
		var card := _open("res://ui/menus/AssistSuggestMenu.gd", {"context": "boss:warden_krail", "title": "WARDEN KRAIL",
			"text": r.text, "keys": r.suggest, "values": r.values})
		await _check_page(card, "%s AssistSuggest %s" % [tag, r.text.left(24)])
		card.close_menu()
	var demo := _open("res://ui/menus/DemoEndMenu.gd")
	await _check_page(demo, "%s DemoEnd" % tag)
	demo.close_menu()


func _finished(ch: ChallengeData) -> Dictionary:
	return {"challenge": ch.id, "profile": 1, "outcome": ChallengeData.Outcome.FINISHED, "value": 88888, "medal": 3,
		"new_best": true, "prev_best": 99999, "rank": 1, "attempt": 88, "tags": {"assists": ["damage_assist"]},
		"date": "2026-09-26T10:00:00", "cause": "", "stages": [], "score_kind": ch.score_kind, "title": ch.title,
		"frames": 88888, "splits": []}


func test_menus_fit_pseudo() -> void:
	# A cleared profile shows the most rows (quests, people, memories, every
	# challenge unlocked).
	StoryPresets.apply("act1_complete")
	Game.set_flag("chase_rainline_done")
	_pseudo()
	for s: int in UI_SCALES:
		Settings.ui_scale = s
		UiTheme.invalidate()
		_pages = 0
		await _check_all_menus(s)
		print("  l10n layout: ui %d measured %d pages" % [s, _pages])
		check(_pages >= 60, "ui %d: every screen was measured (%d pages)" % [s, _pages])


# --- HUD -----------------------------------------------------------------------------

## Catalogued texts whose location note starts with one of `types`, or whose
## key ends with one of `fields`.
static func _catalog(types: PackedStringArray, fields: PackedStringArray = []) -> PackedStringArray:
	var out := PackedStringArray()
	for e in ExtractStrings.build_catalog():
		var hit := false
		for n: String in e.notes:
			for t: String in types:
				if n.begins_with(t):
					hit = true
		for k: String in e.keys:
			for f: String in fields:
				if k.ends_with("." + f) or k.ends_with("::" + f):
					hit = true
		if hit and not out.has(e.msgid):
			out.append(e.msgid)
	return out


func test_hud_strings_fit_pseudo() -> void:
	_pseudo()
	var font := UiTheme.font()
	var key := InputGlyphs.label(&"interact")
	var contents: Array[Dictionary] = []
	for charge in [8888]:
		for flow in [false, true]:
			for online in [false, true]:
				contents.append({"core_label": HUD.core_label(charge, flow, online)})
	contents.append({"scrap": HUD.scrap_label(8888, 8888)})
	for path in DataDir.list_files("res://data/weapons", "tres"):
		var w := load(path)
		if w and "display_name" in w:
			contents.append({"weapon": str(w.get("display_name")), "ammo_max": 6})
	for title in ["COLLECTOR DRONE", "WARDEN KRAIL"]:
		contents.append({"boss_title": Loc.t(title), "staggered": true})
	contents.append({"rank": "REDLINE"})
	var hints := _catalog(["HintTrigger"], ["first_entry_hint", "arm_hint", "warn_hint", "repeat_hint", "more_waiting_hint", "used_text", "hint_text"])
	check(hints.size() >= 20, "the room hints are sampled (%d)" % hints.size())
	for t in hints:
		contents.append({"hint": Loc.f(t, {"action": key})})
	for t in ["NEW QUEST  —  {title}", "QUEST COMPLETE  —  {title}", "CIRCUIT ACQUIRED  —  {name}", "WEAPON ACQUIRED  —  {name}"]:
		contents.append({"hint": Loc.f(t, {"title": Loc.t("The Way Up"), "name": Loc.t("Overclock Loop")})})
	for verb in _catalog(["Interactable", "NpcProfile"], ["prompt_verb", "verb"]):
		contents.append({"prompt": Loc.f("[{key}] {prompt}", {"key": key, "prompt": Loc.t(verb)})})
	for name in _catalog(["NpcProfile"], ["display_name"]):
		contents.append({"prompt": Loc.f("[{key}] {prompt}", {"key": key,
			"prompt": Loc.f("{verb}  —  {name}", {"verb": Loc.t("Talk"), "name": Loc.t(name)})})})
	var districts := _catalog([], ["district_name"])
	var rooms := _catalog([], ["room_name"])
	for d in districts:
		for r in rooms.slice(0, 1):
			contents.append({"banner": Loc.upper(d), "banner_sub": Loc.t(r)})
	for r in rooms:
		contents.append({"banner": Loc.upper(districts[0] if not districts.is_empty() else ""), "banner_sub": Loc.t(r)})
	var bad := PackedStringArray()
	for c in contents:
		var rects: Dictionary = HUD.element_rects(VIEW, font, c)
		for id: String in rects:
			var r: Rect2 = rects[id]
			if r.position.x < 0.0 or r.end.x > VIEW.x:
				bad.append("%s %s: x %.0f..%.0f" % [id, str(c.values()[0]).left(60), r.position.x, r.end.x])
	check(bad.is_empty(), "HUD strings leave the %d px view: %s" % [int(VIEW.x), "\n".join(bad)])


# --- Subtitles ---------------------------------------------------------------------------

func test_subtitles_fit_pseudo() -> void:
	_pseudo()
	Settings.subtitle_size = 2
	Settings._subtitle_size_override = -1
	var lines := _catalog(["SeqLine", "DialogueLine", "MemoryBeat"])
	check(lines.size() >= 150, "every subtitle line is sampled (%d)" % lines.size())
	var width := minf(CinematicOverlay.LINE_MAX_WIDTH, VIEW.x - 48.0)
	var cap := VIEW.y * SUBTITLE_MAX_SHARE
	var bad := PackedStringArray()
	for t in lines:
		var hh := SubtitleStyle.box_height(Loc.t(t), width)
		if hh > cap:
			bad.append("%.0f px: %s" % [hh, t.left(50)])
	check(bad.is_empty(), "subtitle boxes over %.0f px at size Large: %s" % [cap, "\n".join(bad)])


# --- Fonts -------------------------------------------------------------------------------

func test_no_direct_fallback_font() -> void:
	var hits := PackedStringArray()
	for root: String in CODE_ROOTS:
		for path in ExtractStrings.files_under(PackedStringArray([root]), "gd"):
			if FALLBACK_EXEMPT.has(path):
				continue
			if FileAccess.get_file_as_string(path).contains("ThemeDB.fallback_font"):
				hits.append(path)
	check(hits.is_empty(), "text draws with UiTheme.font(), not ThemeDB.fallback_font: %s" % [hits])
	check(UiTheme.font() is FontVariation and (UiTheme.font() as FontVariation).base_font == UiTheme.base_font(),
		"UiTheme.font() is the chain over the engine face")
	check(SubtitleStyle.font() == UiTheme.font(), "subtitles use the same font")


func test_glyph_coverage_per_locale() -> void:
	# Marks the catalog skips (exempt, never translated) are still drawn.
	var cfg := MemoryLibrary.config()
	var marks := cfg.glyph_seen + cfg.glyph_pending + cfg.glyph_locked + cfg.glyph_gap + "".join(cfg.act_names)
	var sources := ""
	for e in PoFile.load_file(ExtractStrings.POT_PATH).entries:
		sources += str(e["msgid"]) + str(e["msgid_plural"])
	for row in LocaleTable.shared().rows:
		if row == null or not row.enabled:
			continue
		var text := row.endonym + row.coverage_sample + marks
		if row.code == Loc.SOURCE_LOCALE:
			text += sources
		else:
			var path := "%s/%s.po" % [LocaleTable.CATALOG_DIR, row.code]
			for e in PoFile.load_file(path).entries:
				text += str(e["msgstr"]) + "".join(e["msgstr_plural"])
		var missing := Pseudo.missing_glyphs(text, row)
		check(missing == "", "%s: every glyph is in the font chain (missing: %s)" % [row.code, missing])
