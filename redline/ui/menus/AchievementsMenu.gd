class_name AchievementsMenu
extends MenuScreen
## The Achievements list and Records page (M9 D1 §4.7, T07; MenuHost id
## "achievements"). Opened from the title (ctx {"from": "title"}) and from
## the Journal's "Achievements…" row (ctx {"return_to": &"journal", "row": n}).
## Controller-first: every entry is a focusable button, the filter is an
## option row, ui_cancel backs out one level.
##
## Design intent:
## - Never shame (§24): the list shows what was earned and what is left, no
##   deaths and no failure words; deaths are not on Records either (R07.9).
## - No spoilers (R07.3): a row whose reveal_when does not hold reads "???"
##   with its category only; a hidden achievement reads "Hidden achievement"
##   with its nudge, until the per-open "Show hidden details" toggle (not
##   saved) says otherwise. Unlocked rows always show in full.
## - Unlocks are global (D-143); reveal conditions and "This save" read the
##   profile: the held one during a run, and from the title the saved one
##   (Game.state is not loaded there, R07.2).
## - Demo builds list only the demo's achievements plus anything unlocked.

const LOC_FIELDS := {}
const LOC_EXEMPT := []
const STYLE_PATH := "res://data/style/default_style.tres"
const CATEGORY_NAMES: PackedStringArray = ["Story", "Exploration", "People", "Mastery"]
const FILTER_NAMES: PackedStringArray = ["All", "Unlocked", "Locked"]
const MARK_DONE := "✓"
const MARK_OPEN := "○"
const NO_VALUE := "—"
## Lines kept for the focused entry's detail under the list.
const FOOTER_LINES := 2

enum Filter { ALL, UNLOCKED, LOCKED }

## &"list" or &"records".
var page: StringName = &"list"
var filter: Filter = Filter.ALL
var list_page: int = 0
## Spoiler opt-in for hidden achievements; reset on every open (never saved).
var show_hidden: bool = false

## The profile reveal conditions and "This save" read, built on open.
var _profile: GameState = null
var _has_save: bool = true
var _records_return_focus: int = -1


func _ready() -> void:
	super._ready()
	_panel.custom_minimum_size = Vector2(380, 0)


func open_menu() -> void:
	page = &"list"
	filter = Filter.ALL
	list_page = 0
	show_hidden = false
	_records_return_focus = -1
	_load_profile()
	super.open_menu()
	focus_index(first_entry_index())


func from_title() -> bool:
	return str(ctx.get("from", "")) == "title"


func returns_to_journal() -> bool:
	return StringName(str(ctx.get("return_to", ""))) == &"journal"


## The profile state for reveal conditions and "This save" (R07.2, R07.7):
## the saved profile from the title, else the held profile during a run,
## else the live one. Rebuilt on open, read on every rebuild.
func _load_profile() -> void:
	if from_title():
		var data := SaveManager.load_profile(Game.profile_id)
		_has_save = not data.is_empty()
		_profile = GameState.from_dict(data) if _has_save else GameState.new()
	else:
		_has_save = true
		_profile = Game.held_profile if Game.held_profile != null else Game.state


## Runs `fn` with Game.state swapped to the chosen profile (conditions and
## derived stats read Game.state), without any signal.
func _with_profile(fn: Callable) -> Variant:
	if _profile == null or _profile == Game.state:
		return fn.call()
	var saved_state := Game.state
	var saved_abilities := Game.abilities
	Game.state = _profile
	Game.abilities = ProfileSandbox.kit_abilities(_profile)
	var r: Variant = fn.call()
	Game.state = saved_state
	Game.abilities = saved_abilities
	return r


func holds(expr: String) -> bool:
	return bool(_with_profile(func() -> bool: return Game.check_condition(expr)))


# --- Input ---------------------------------------------------------------------------

## ui_cancel: Records -> list; the list -> Back.
func _process(_delta: float) -> void:
	if not visible or Engine.get_process_frames() == _opened_frame or not cancel_pressed():
		return
	if page == &"records":
		show_list()
	else:
		back()


## Leaves the menu: to the Journal on its row, else closed (the title gets
## its focus back from MenuHost).
func back() -> void:
	var journal := returns_to_journal()
	var row := int(ctx.get("row", -1))
	close_menu()
	if journal:
		MenuHost.context = {"row": row}
		EventBus.menu_requested.emit(&"journal")


func show_list() -> void:
	page = &"list"
	_opened_frame = Engine.get_process_frames()
	rebuild()
	focus_index(_records_return_focus if _records_return_focus >= 0 else first_entry_index())
	_records_return_focus = -1


func show_records() -> void:
	_records_return_focus = focused_index()
	page = &"records"
	_opened_frame = Engine.get_process_frames()
	rebuild()
	focus_index(0)


func rebuild() -> void:
	clear_body()
	if page == &"records":
		_records_page()
	else:
		_list_page()


# --- List -----------------------------------------------------------------------------

## The achievements this build lists (demo: its own plus any unlocked).
func listed() -> Array[AchievementData]:
	var all := AchievementLibrary.all()
	if not BuildInfo.is_demo():
		return all
	var demo := BuildInfo.demo()
	var ids: PackedStringArray = demo.get("achievements") if demo else PackedStringArray()
	var out: Array[AchievementData] = []
	for a in all:
		if ids.has(a.id) or Platform.is_unlocked(a.id):
			out.append(a)
	return out


func filtered() -> Array[AchievementData]:
	var out: Array[AchievementData] = []
	for a in listed():
		var done := Platform.is_unlocked(a.id)
		if filter == Filter.ALL or (filter == Filter.UNLOCKED) == done:
			out.append(a)
	return out


func rows_per_page() -> int:
	return maxi(1, Platform.config.menu_rows_per_page if Platform.config else 6)


func page_count() -> int:
	return maxi(1, ceili(float(filtered().size()) / rows_per_page()))


## Index (among the page's buttons) of the first entry: after the filter row
## and, when shown, the hidden-details toggle.
func first_entry_index() -> int:
	return 2 if _has_hidden_locked() else 1


func _has_hidden_locked() -> bool:
	return listed().any(func(a: AchievementData) -> bool:
		return a.hidden and not Platform.is_unlocked(a.id) and revealed(a))


func revealed(a: AchievementData) -> bool:
	return Platform.is_unlocked(a.id) or a.reveal_when == "" or holds(a.reveal_when)


func _list_page() -> void:
	var all := listed()
	var got := all.filter(func(a: AchievementData) -> bool: return Platform.is_unlocked(a.id)).size()
	add_label(Loc.f("ACHIEVEMENTS  {n} / {total}", {"n": got, "total": all.size()}), UiTheme.ACCENT, UiTheme.FONT_SIZE + 2)
	set_footer("", FOOTER_LINES)
	var clear_footer := set_footer.bind("", FOOTER_LINES)
	add_option_row(Loc.f("Show: {filter}", {"filter": Loc.t(FILTER_NAMES[filter])}),
		_cycle_filter.bind(1), _cycle_filter.bind(-1), _cycle_filter.bind(1), clear_footer)
	if _has_hidden_locked():
		var state := Loc.t("On") if show_hidden else Loc.t("Off")
		add_option_row(Loc.f("Show hidden details: {state}", {"state": state}),
			_toggle_hidden, _toggle_hidden, _toggle_hidden, clear_footer)
	var rows := filtered()
	var pages := page_count()
	list_page = posmod(list_page, pages)
	var per := rows_per_page()
	if rows.is_empty():
		add_label(Loc.t("Nothing here yet.") if filter == Filter.UNLOCKED else Loc.t("Everything here is unlocked."), UiTheme.MUTED)
	for a: AchievementData in rows.slice(list_page * per, (list_page + 1) * per):
		_add_entry(a)
	if pages > 1:
		_add_row(Loc.f("More… ({page}/{pages})", {"page": list_page + 1, "pages": pages}), _next_page)
	_add_row(Loc.t("Records…"), show_records)
	_add_row(Loc.t("Back"), back)


## One entry: a focusable button (the title line); its detail line (the
## description, date or nudge) shows in the pinned footer while it has
## focus, like Settings' row descriptions, so six rows fit 270 px.
func _add_entry(a: AchievementData) -> void:
	var t := entry_text(a)
	add_button(t[0], func() -> void: pass, set_footer.bind(t[1], FOOTER_LINES))


## Rows that are not entries clear the detail line (the space stays).
func _add_row(text: String, on_press: Callable) -> Button:
	return add_button(text, on_press, set_footer.bind("", FOOTER_LINES))


## [title line, detail line] for `a` as the list shows it now.
func entry_text(a: AchievementData) -> PackedStringArray:
	if Platform.is_unlocked(a.id):
		var rec := Platform.unlock_record(a.id)
		var detail := Loc.t(a.description)
		if rec.has("t"):
			detail += "  ·  " + Time.get_date_string_from_unix_time(int(rec["t"]))
		return PackedStringArray(["%s %s" % [MARK_DONE, Loc.t(a.title)], detail])
	if not revealed(a):
		return PackedStringArray(["%s %s" % [MARK_OPEN, Loc.t("???")], Loc.t(category_name(a.category))])
	if a.hidden and not show_hidden:
		var hint := Loc.t(a.hint_when_hidden) if a.hint_when_hidden != "" else Loc.t("Keep exploring.")
		return PackedStringArray(["%s %s" % [MARK_OPEN, Loc.t("Hidden achievement")], hint])
	var line := Loc.t(a.description)
	var prog := progress_text(a)
	if prog != "":
		line += "  (" + prog + ")"
	return PackedStringArray(["%s %s" % [MARK_OPEN, Loc.t(a.title)], line])


static func category_name(c: int) -> String:
	return CATEGORY_NAMES[clampi(c, 0, CATEGORY_NAMES.size() - 1)]


## "3 / 10" for a counter with a target above 1; "" otherwise (ranks and
## one-off feats read better without a bar).
func progress_text(a: AchievementData) -> String:
	if a.stat_id == &"" or a.stat_target <= 1.0:
		return ""
	var def := Platform.stats.catalog.stat(a.stat_id) if Platform.stats else null
	if def == null or def.kind != StatDef.Kind.COUNTER:
		return ""
	var v := _stat_value(def, a.stat_scope == AchievementData.Scope.LIFETIME)
	return Loc.f("{now} / {target}", {"now": int(minf(v, a.stat_target)), "target": int(a.stat_target)})


func _cycle_filter(step: int) -> void:
	var i := focused_index()
	filter = posmod(filter + step, FILTER_NAMES.size()) as Filter
	list_page = 0
	rebuild()
	focus_index(i)


func _toggle_hidden() -> void:
	var i := focused_index()
	show_hidden = not show_hidden
	rebuild()
	focus_index(i)


func _next_page() -> void:
	var i := focused_index()
	list_page += 1
	rebuild()
	# Stay on the "More…" row (its index moves when the last page is short).
	var buttons := _body.get_children().filter(func(n: Node) -> bool: return n is Button)
	for j in buttons.size():
		if (buttons[j] as Button).text.begins_with(Loc.t("More…").trim_suffix("…")):
			focus_index(j)
			return
	focus_index(i)


# --- Records ----------------------------------------------------------------------

## Stats the Records page lists now: shown, and revealed on the profile
## (StatDef.revealed: a value, or its condition holds).
func record_stats() -> Array[StatDef]:
	var out: Array[StatDef] = []
	if Platform.stats == null:
		return out
	for def in Platform.stats.catalog.stats:
		if def == null or not def.shown:
			continue
		var value := maxf(_stat_value(def, false) if def.profile else 0.0, _stat_value(def, true) if def.lifetime else 0.0)
		if bool(_with_profile(func() -> bool: return def.revealed(value))):
			out.append(def)
	return out


func _stat_value(def: StatDef, lifetime: bool) -> float:
	if lifetime:
		return Platform.stat(def.id, true)
	if not _has_save:
		return 0.0
	return float(_with_profile(func() -> float: return Platform.stats.profile_value(def.id)))


## One value cell: "—" when the scope does not keep this stat, or a MIN
## stat has no value yet.
func value_text(def: StatDef, lifetime: bool) -> String:
	if (lifetime and not def.lifetime) or (not lifetime and (not def.profile or not _has_save)):
		return NO_VALUE
	var v := _stat_value(def, lifetime)
	if def.kind == StatDef.Kind.MIN and v <= 0.0:
		return NO_VALUE
	match def.format:
		StatDef.Format.TIME:
			return SliceStats.format_time(v)
		StatDef.Format.RANK:
			var style := load(STYLE_PATH) as StyleConfig
			var names: PackedStringArray = style.rank_names if style else PackedStringArray()
			var i := clampi(int(v), 0, maxi(names.size() - 1, 0))
			return names[i] if not names.is_empty() else str(int(v))
	return str(int(v))


func _records_page() -> void:
	set_footer("")
	add_label(Loc.t("RECORDS"), UiTheme.ACCENT, UiTheme.FONT_SIZE + 2)
	_add_cells(PackedStringArray(["", Loc.t("This save"), Loc.t("All time")]), UiTheme.ACCENT)
	for def in record_stats():
		_add_cells(PackedStringArray([Loc.t(def.label), value_text(def, false), value_text(def, true)]), UiTheme.TEXT)
	add_button(Loc.t("Back"), show_list)


## A label row with two right-aligned value columns.
func _add_cells(cells: PackedStringArray, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for i in cells.size():
		var l := Label.new()
		l.text = cells[i]
		l.add_theme_color_override("font_color", UiTheme.label_color(color if i == 0 or color == UiTheme.ACCENT else UiTheme.MUTED))
		l.add_theme_font_size_override("font_size", UiTheme.scaled(UiTheme.FONT_SIZE - 1))
		if i == 0:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.clip_text = true
		else:
			l.custom_minimum_size.x = UiTheme.scaled(56)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(l)
	_body.add_child(row)
