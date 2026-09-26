class_name ChallengesMenu
extends MenuScreen
## The Challenges list (M9 D2 §6.2, T08; MenuHost id "challenges"), opened
## from the Relay training rig (ctx {"room", "entry"}), the title row (ctx
## {"from": "title"}, R01.16) or the dev console. Controller-first: every
## row is a button (locked ones too, disabled but focusable so a pad user can
## read the hint); ui_cancel backs out one page.
##
## Pages:
## - list: "Profile {p} · medals {got} / {max}", then one block per group in
##   ChallengeData.Group order. The Deep Rig block (the internal NULL group,
##   D-154) shows only once null_open holds. A locked row reads "???" until
##   its reveal_when holds (no boss or set piece is named early, R08.2), then
##   "Locked — <hint>".
## - detail: rules line, medal targets (or the rank summary), your best, the
##   local board (5 rows a page, "More…"), the ghost cycler, Start, Back.
## - ranks: "How ranks work" for RANK challenges (the Deep Rig strata).
##
## Medal names always come from RankLadder (data), never style letters
## (D-149). Assisted and reduced-hitstop entries carry a neutral glyph and
## word on the board; there is no filter and no separate table (§24).
## The return point for Start is rebuilt from ctx on every use (R08.5).

## No resource fields of its own: every line is a Loc literal or data text
## (ChallengeData.LOC_FIELDS, RankLadder, ChallengeConfig).
const LOC_FIELDS := {}
const LOC_EXEMPT := []
## Board rows per page (the "More…" row pages through the rest).
const BOARD_PAGE := 5
## The neutral board tag glyph (never a colour alone, never a penalty word).
const TAG_GLYPH := "◇"

## &"list", &"detail" or &"ranks".
var page: StringName = &"list"
## The challenge the detail and ranks pages show.
var selected: ChallengeData = null
var board_page: int = 0
## List row focused before the detail page opened (restored on Back).
var _list_focus: int = 0


func open_menu() -> void:
	page = &"list"
	selected = null
	board_page = 0
	_list_focus = 0
	super.open_menu()
	focus_index(0)


## ui_cancel backs out one page; on the list it closes.
func _process(_delta: float) -> void:
	if not visible or Engine.get_process_frames() == _opened_frame or not cancel_pressed():
		return
	match page:
		&"detail":
			show_list()
		&"ranks":
			show_detail(selected)
		_:
			close_menu()


## Where a run started from here returns (R08.5): the rig's room and spawn,
## the title, or nowhere (dev starts).
func return_to() -> Dictionary:
	if bool(ctx.get("title", false)) or str(ctx.get("from", "")) == "title":
		return {"title": true}
	if str(ctx.get("room", "")) != "":
		return {"room": str(ctx["room"]), "entry": StringName(str(ctx.get("entry", "")))}
	return {}


func rebuild() -> void:
	clear_body()
	match page:
		&"detail":
			_detail_page()
		&"ranks":
			_ranks_page()
		_:
			_list_page()


func show_list() -> void:
	page = &"list"
	selected = null
	_opened_frame = Engine.get_process_frames()
	rebuild()
	focus_index(_list_focus)


func show_detail(ch: ChallengeData) -> void:
	if ch == null:
		return
	if page == &"list":
		_list_focus = focused_index()
		board_page = 0
	page = &"detail"
	selected = ch
	_opened_frame = Engine.get_process_frames()
	rebuild()
	focus_index(_start_index())


func show_ranks() -> void:
	page = &"ranks"
	_opened_frame = Engine.get_process_frames()
	rebuild()
	focus_index(0)


# --- List ---------------------------------------------------------------------------

func _list_page() -> void:
	var list := ChallengeLibrary.all()
	add_label(Loc.t("CHALLENGES"), UiTheme.ACCENT, UiTheme.FONT_SIZE + 2)
	var tally := medal_tally(list)
	add_label(Loc.f("Profile {p} · medals {got} / {max}", {"p": Game.profile_id, "got": tally[0], "max": tally[1]}), UiTheme.MUTED)
	for g in ChallengeData.Group.values():
		var rows := list.filter(func(c: ChallengeData) -> bool: return c.group == g)
		if rows.is_empty():
			continue
		if g == ChallengeData.Group.NULL and not ChallengeLibrary.profile_holds("flag:null_open"):
			continue
		add_label(Loc.t(ChallengeLibrary.group_title(g)), UiTheme.ACCENT)
		if g == ChallengeData.Group.NULL and ChallengeLibrary.profile_holds("flag:null_depth_reached"):
			add_label(Loc.t("Depth reached"), UiTheme.MUTED)
		for c: ChallengeData in rows:
			_add_row(c)
	add_button(Loc.t("Back"), close_menu)


func _add_row(ch: ChallengeData) -> void:
	if ChallengeLibrary.unlocked(ch):
		add_button(row_text(ch), show_detail.bind(ch))
	elif ChallengeLibrary.revealed(ch):
		add_button(Loc.f("Locked — {hint}", {"hint": Loc.t(ch.locked_hint)}), func() -> void: pass, Callable(), false)
	else:
		add_button(Loc.t("???"), func() -> void: pass, Callable(), false)


## "Title    0:28.53  Silver" (a RANK row: "Title    Gold  812"); a failed
## requirement adds its text.
func row_text(ch: ChallengeData) -> String:
	var t := Loc.t(ch.title)
	var best := Challenges.records.best(ch.id, Game.profile_id, ch.revision)
	if not best.is_empty():
		t += "    " + best_text(ch, int(best.get("value", -1)), int(best.get("medal", -1)))
	if not requirements_met(ch):
		t += "  —  " + Loc.t(ch.requires_text)
	return t


## [medals earned, medals possible] over `list` (each challenge's best tier,
## Clear counting 0). The Deep Rig block counts only once it is shown
## (null_open), so the header never hints at a hidden group.
static func medal_tally(list: Array[ChallengeData]) -> Array[int]:
	var got := 0
	var n := 0
	var null_shown := ChallengeLibrary.profile_holds("flag:null_open")
	for ch in list:
		if ch.group == ChallengeData.Group.NULL and not null_shown:
			continue
		n += 1
		var best := Challenges.records.best(ch.id, Game.profile_id, ch.revision)
		got += maxi(0, int(best.get("medal", 0)))
	return [got, n * (RankLadder.COUNT - 1)]


static func requirements_met(ch: ChallengeData) -> bool:
	for c in ch.requires:
		if not ChallengeLibrary.profile_holds(c):
			return false
	return true


## A value and its tier: "0:28.53  Silver", "4 210  Gold", "Gold  812".
static func best_text(ch: ChallengeData, value: int, medal: int) -> String:
	var name := Loc.t(RankLadder.name(medal)) if medal >= 0 else ""
	match ch.score_kind:
		ChallengeData.ScoreKind.RANK:
			return "%s  %d" % [name, value]
		ChallengeData.ScoreKind.SCORE:
			return "%d  %s" % [value, name]
	return "%s  %s" % [RunClock.format(value), name]


static func value_text(ch: ChallengeData, value: int) -> String:
	return RunClock.format(value) if ch.score_kind == ChallengeData.ScoreKind.TIME else str(value)


## Medal targets read in whole seconds when they are ("0:50"), else to the
## centisecond.
static func target_text(ch: ChallengeData, value: int) -> String:
	if ch.score_kind != ChallengeData.ScoreKind.TIME:
		return str(value)
	if value % RunClock.FPS == 0:
		var s := value / RunClock.FPS
		return "%d:%02d" % [s / 60, s % 60]
	return RunClock.format(value)


# --- Detail ------------------------------------------------------------------------

func _detail_page() -> void:
	var ch := selected
	add_label(Loc.t(ch.title), UiTheme.ACCENT, UiTheme.FONT_SIZE + 2)
	add_label(Loc.t(ch.description), UiTheme.MUTED)
	add_label(rules_line(ch))
	if ch.score_kind == ChallengeData.ScoreKind.RANK:
		add_label(Loc.t("Core mode never changes your rank"), UiTheme.MUTED)
		add_label(rank_summary(ch), UiTheme.MUTED)
	else:
		for line in target_lines(ch):
			add_label(line, UiTheme.MUTED)
	add_label(your_best_line(ch))
	var archived := Challenges.records.archived_count(ch.id, ch.revision)
	if archived > 0:
		add_label(Loc.f("Records from an earlier version of this room: {n} (archived)", {"n": archived}), UiTheme.MUTED)
	var board := Challenges.records.board(ch.id, ch.revision)
	var pages := maxi(1, ceili(float(board.size()) / BOARD_PAGE))
	board_page = clampi(board_page, 0, pages - 1)
	if board.is_empty():
		add_label(Loc.t("Local board: no finishes yet"), UiTheme.MUTED)
	else:
		add_label(Loc.t("Local board"), UiTheme.ACCENT)
		var tagged := false
		for i in range(board_page * BOARD_PAGE, mini(board.size(), (board_page + 1) * BOARD_PAGE)):
			var e: Dictionary = board[i]
			add_label(board_row(ch, i + 1, e))
			tagged = tagged or not tag_words(e).is_empty()
		if tagged:
			add_label(Loc.f("{glyph} marks runs with an assist or reduced hitstop. They earn the same medals.", {"glyph": TAG_GLYPH}), UiTheme.MUTED)
		if pages > 1:
			add_button(Loc.f("More… ({page} / {pages})", {"page": board_page + 1, "pages": pages}), func() -> void:
				var i := focused_index()
				board_page = (board_page + 1) % pages
				rebuild()
				focus_index(i))
	if ghost_row_shown(ch):
		add_option_row(Loc.f("Ghost: {mode}", {"mode": Challenges.ghost_mode_label()}), _cycle_ghost.bind(1), _cycle_ghost.bind(3), _cycle_ghost.bind(1))
		if (Settings.challenge_ghost == 2 or Settings.challenge_ghost == 3) and ch.dev_ghost == "":
			add_label(Loc.t("No rig ghost yet"), UiTheme.MUTED)
	if ch.score_kind == ChallengeData.ScoreKind.RANK:
		add_button(Loc.t("How ranks work"), show_ranks)
	var can := requirements_met(ch)
	if not can:
		add_label(Loc.t(ch.requires_text), UiTheme.MUTED)
	add_button(Loc.t("Start"), _start.bind(ch), Callable(), can)
	add_button(Loc.t("Back"), show_list)


## The detail page's Start row (focused when the page opens).
func _start_index() -> int:
	var buttons := _body.get_children().filter(func(n: Node) -> bool: return n is Button)
	for i in buttons.size():
		if (buttons[i] as Button).text.ends_with(Loc.t("Start")):
			return i
	return 0


## "No hits. Falls and Core burnout count. · Fixed kit: Pulse Blade + Service Pistol"
static func rules_line(ch: ChallengeData) -> String:
	var parts := PackedStringArray()
	if ch.fail_on_damage:
		parts.append(Loc.t("No hits. Falls and Core burnout count."))
	if ch.fail_on_attack:
		parts.append(Loc.t("Movement only: no swings or shots."))
	if ch.time_limit_s > 0.0:
		parts.append(Loc.f("Time limit {time}", {"time": RunClock.format(roundi(ch.time_limit_s * RunClock.FPS))}))
	if ch.kit and ch.kit.use_profile_loadout:
		parts.append(Loc.t("Your own loadout"))
	elif ch.kit:
		var names := PackedStringArray()
		var cat := load("res://data/catalog.tres") as ItemCatalog
		for w in [ch.kit.melee, ch.kit.ranged]:
			var wd := cat.weapon(String(w)) if cat and String(w) != "" else null
			if wd:
				names.append(Loc.t(wd.display_name))
		if names.is_empty():
			parts.append(Loc.t("Fixed kit: unarmed"))
		else:
			parts.append(Loc.f("Fixed kit: {weapons}", {"weapons": " + ".join(names)}))
	return "  ·  ".join(parts)


## The medal targets: "Bronze 0:50 · Silver 0:35 · Gold 0:27", then the top
## tier, measured against the rig ghost when one ships.
static func target_lines(ch: ChallengeData) -> PackedStringArray:
	var out := PackedStringArray()
	var m := ch.medal_thresholds
	if m.size() != 4:
		return out
	var parts := PackedStringArray()
	for i in 3:
		parts.append("%s %s" % [Loc.t(RankLadder.name(i + 1)), target_text(ch, m[i])])
	out.append(" · ".join(parts))
	var top := "%s %s" % [Loc.t(RankLadder.name(4)), target_text(ch, m[3])]
	if ch.dev_ghost != "":
		out.append(top + "  ·  " + Loc.t("Beat the rig ghost's time"))
	else:
		out.append(top)
	return out


## "Bronze 450 · Silver 650 · Gold 820 · Redline 900 (of 1000)".
static func rank_summary(ch: ChallengeData) -> String:
	if ch.rank_table == null:
		return ""
	var parts := PackedStringArray()
	var th := ch.rank_table.thresholds
	for i in range(1, mini(th.size(), RankLadder.COUNT)):
		parts.append("%s %d" % [Loc.t(RankLadder.name(i)), th[i]])
	return Loc.f("{tiers} (of 1000)", {"tiers": " · ".join(parts)})


func your_best_line(ch: ChallengeData) -> String:
	var best := Challenges.records.best(ch.id, Game.profile_id, ch.revision)
	var attempts := Challenges.records.attempts(ch.id, Game.profile_id, ch.revision)
	if best.is_empty():
		return Loc.f("Your best: none yet ({n} attempts)", {"n": attempts})
	return Loc.f("Your best: {best} ({n} attempts)", {"best": best_text(ch, int(best.get("value", -1)), int(best.get("medal", -1))),
		"n": attempts})


## "1. P1  0:28.53  Silver  2026-09-26  ◇ assist"
static func board_row(ch: ChallengeData, rank: int, e: Dictionary) -> String:
	var t := Loc.f("{rank}. P{profile}  {value}  {medal}  {date}", {"rank": rank, "profile": int(e.get("profile", 0)),
		"value": value_text(ch, int(e.get("value", -1))), "medal": Loc.t(RankLadder.name(int(e.get("medal", -1)))),
		"date": str(e.get("date", "")).get_slice("T", 0)})
	for w in tag_words(e):
		t += "  %s %s" % [TAG_GLYPH, w]
	return t


## The neutral words for an entry's tags (R08.3): "assist" for any assist,
## "reduced hitstop" for the timing tag. Never "easy", never a penalty.
static func tag_words(e: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if not (e.get("assists", []) as Array).is_empty():
		out.append(Loc.t("assist"))
	if (e.get("timing", []) as Array).has(Challenges.TAG_HITSTOP):
		out.append(Loc.t("reduced hitstop"))
	return out


## Hidden for RANK challenges that have no ghost of either kind.
static func ghost_row_shown(ch: ChallengeData) -> bool:
	if ch.score_kind != ChallengeData.ScoreKind.RANK:
		return true
	return ch.dev_ghost != "" or Challenges.records.pb_ghost(ch.id, Game.profile_id, ch.revision) != null


func _cycle_ghost(steps: int) -> void:
	var i := focused_index()
	for s in steps:
		Challenges.cycle_ghost_mode()
	rebuild()
	focus_index(i)


## Closes first (the run's first room loads unpaused), then starts with the
## return point rebuilt from ctx.
func _start(ch: ChallengeData) -> void:
	var ret := return_to()
	close_menu()
	if not Challenges.start(ch, ret):
		EventBus.hint_requested.emit(Loc.t("The training rig cannot start that run right now."), 2.0)


# --- How ranks work ------------------------------------------------------------------

func _ranks_page() -> void:
	add_label(Loc.t("How ranks work"), UiTheme.ACCENT, UiTheme.FONT_SIZE + 2)
	for line in rank_lines():
		add_label(line)
	add_label(Loc.t("Core mode never changes your rank"), UiTheme.MUTED)
	add_button(Loc.t("Back"), show_detail.bind(selected))


## The four rules of a stage's rank (D3 §3.10): time, damage, style and the
## top tier.
static func rank_lines() -> PackedStringArray:
	return PackedStringArray([
		Loc.t("Time: finishing near the stage's par earns time points; at its Redline time you earn them all."),
		Loc.t("Damage: every hit and every death costs points."),
		Loc.t("Style: a higher average style rank earns more points."),
		Loc.f("{top}: no hits, no deaths and a time at or under the stage's Redline time.", {"top": Loc.t(RankLadder.name(RankLadder.COUNT - 1))}),
	])
