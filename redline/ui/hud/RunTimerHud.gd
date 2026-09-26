class_name RunTimerHud
extends CanvasLayer
## The run HUD (M9 D2 §6.3, D3 §3.10), owned by the Challenges autoload. In a
## run: the time (m:ss.cc), the rule chip (NO HIT / NO ATTACKS), the attempt
## or the stage and its projected rank, split deltas, Pulse Pit wave/score,
## the first-use reset chip and the fast-reset hold arc. Outside runs: the
## campaign IGT when Settings.speedrun_timer > 0 (splits in mode 2).
##
## It sits top-left in a small block (R04.8: clear of the style rank at the
## top right and the achievement toast at the top centre). Split deltas carry
## a sign AND an arrow (▲ slower, ▼ faster), so they never rely on colour.
## Hidden while the HUD is hidden for a scene or the tree is paused.

const LOC_FIELDS := {}
const ORIGIN := Vector2(6, 6)
const BLOCK := Vector2(120, 24)
const FONT_SIZE := 7
const LINE := 8.0

var _root: Control
## [text, seconds left] of the transient third line (split deltas).
var _toast: String = ""
var _toast_time: float = 0.0
## Seconds the first-use reset chip still shows.
var _chip_time: float = 0.0
## Campaign mode: the last split line.
var _campaign_split: String = ""


func _ready() -> void:
	layer = 60
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.draw.connect(_draw_hud)
	add_child(_root)
	EventBus.speedrun_split.connect(_on_speedrun_split)


func reset() -> void:
	_toast = ""
	_toast_time = 0.0
	_chip_time = 0.0
	_campaign_split = ""


func _process(delta: float) -> void:
	_toast_time = maxf(_toast_time - delta, 0.0)
	_chip_time = maxf(_chip_time - delta, 0.0)
	if _root:
		_root.queue_redraw()


## A split delta in frames (live - best): "▲ +1.10" slower, "▼ -0.42" faster.
static func delta_text(delta_frames: int) -> String:
	var arrow := "▲" if delta_frames > 0 else ("▼" if delta_frames < 0 else "=")
	return "%s %s" % [arrow, RunClock.format_delta(delta_frames)]


func show_split(delta_frames: int, label: String = "") -> void:
	var t := delta_text(delta_frames)
	_toast = (label + "  " + t) if label != "" else t
	_toast_time = ChallengeConfig.shared().split_toast_s


func show_reset_chip() -> void:
	_chip_time = ChallengeConfig.shared().reset_chip_s


func showing() -> bool:
	if CinematicMode.hud_hidden or (is_inside_tree() and get_tree().paused):
		return false
	return Challenges.active() or Settings.speedrun_timer > 0


## The text lines the HUD draws now (tests read them).
func lines() -> PackedStringArray:
	var out := PackedStringArray()
	if not Challenges.active():
		if Settings.speedrun_timer <= 0:
			return out
		out.append(Loc.f("IGT {time}", {"time": RunClock.format(Game.state.igt_frames)}))
		if Settings.speedrun_timer >= 2 and _campaign_split != "":
			out.append(_campaign_split)
		return out
	var ch := Challenges.current()
	if ch == null:
		return out
	var first := RunClock.format(Challenges.clock.frames)
	var chip := rule_chip(ch)
	if chip != "":
		first += "  " + chip
	out.append(first)
	if ch.score_kind == ChallengeData.ScoreKind.RANK:
		var st := ch.stage(Challenges.stage_index())
		var name := Loc.t(st.title) if st else Loc.t(ch.title)
		out.append("%s · %s" % [name, Loc.t(RankLadder.name(Challenges.projected_rank()))])
	elif ch.score_kind == ChallengeData.ScoreKind.SCORE:
		var wave := Challenges.wave_number()
		if wave > 0:
			out.append(Loc.f("Wave {wave} · Score {score}", {"wave": wave, "score": Challenges.score_value()}))
		else:
			out.append(Loc.f("Score {score}", {"score": Challenges.score_value()}))
	else:
		out.append(Loc.f("Attempt {n}", {"n": Challenges.attempt()}))
	if _toast_time > 0.0 and _toast != "":
		out.append(_toast)
	elif _chip_time > 0.0:
		out.append(Loc.f("{key}: restart", {"key": InputGlyphs.label(&"reset")}))
	return out


static func rule_chip(ch: ChallengeData) -> String:
	if ch.fail_on_damage:
		return Loc.t("NO HIT")
	if ch.fail_on_attack:
		return Loc.t("NO ATTACKS")
	return ""


func _on_speedrun_split(split_id: String, _igt: int, delta_frames: int) -> void:
	if Challenges.active():
		return
	# Room splits are display-only and shown only in "IGT + splits" mode.
	var label := split_id
	if split_id.begins_with("room:"):
		label = split_id.trim_prefix("room:")
	else:
		var list := Challenges.campaign.splits()
		var i := list.index_of(split_id) if list else -1
		if i >= 0 and list.splits[i].label != "":
			label = Loc.t(list.splits[i].label)
	_campaign_split = "%s  %s" % [label, delta_text(delta_frames)]


func _draw_hud() -> void:
	if not showing():
		return
	var ls := lines()
	if ls.is_empty():
		return
	var font := ThemeDB.fallback_font
	var h := LINE * ls.size() + 2.0
	_root.draw_rect(Rect2(ORIGIN - Vector2(2, 1), Vector2(BLOCK.x, h)), Color(0, 0, 0, 0.45))
	for i in ls.size():
		var col := Color.WHITE if i == 0 else Color("c9c3d6")
		_root.draw_string(font, ORIGIN + Vector2(0, LINE * (i + 1) - 1.0), ls[i], HORIZONTAL_ALIGNMENT_LEFT, BLOCK.x - 4.0, FONT_SIZE, col)
	var hold := Challenges.reset_hold_fraction()
	if hold > 0.0:
		var c := ORIGIN + Vector2(BLOCK.x - 8.0, 4.0)
		_root.draw_arc(c, 3.5, -PI * 0.5, -PI * 0.5 + TAU * hold, 16, Color.WHITE, 1.5)
