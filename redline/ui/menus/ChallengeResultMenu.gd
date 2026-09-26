class_name ChallengeResultMenu
extends MenuScreen
## The challenge result card (M9 D2 §6.5, D3 §3.10, T08; MenuHost id
## "challenge_result", ctx {"result": Challenges.last_result}). Challenges
## opens it a beat after a run ends (open_when_free, so it is never dropped).
##
## Neutral copy only (§24): tier 0 reads as its RankLadder name ("Clear"),
## never a style letter; a failed run shows its cause ("Run over: hit
## taken") in the muted colour, never red and never "FAILED".
##
## Leaving (R08.1): every way out ends somewhere live. Retry (focused, and
## the reset action) starts a fresh attempt; ui_cancel is "Back to
## Challenges" (the run is left and the list opens again at the return
## point), never a bare close that would strand a frozen player; "Quit
## challenge" leaves to the return point. Confirming is armed like
## DialogueBox.confirm_armed: a short real-time delay after opening and every
## confirm action seen released, so a jump held through the finish line
## never retries by accident.

## Every line is a Loc literal or run data (the challenge title is
## ChallengeData text).
const LOC_FIELDS := {}
const LOC_EXEMPT := []
## Actions that may confirm a row (or retry): each must be seen released
## after the card opens before any press counts.
const CONFIRM_ACTIONS: Array[StringName] = [&"ui_accept", &"jump", &"reset"]
## Real milliseconds after opening before a confirm counts. Tests set 0.
static var arm_ms: int = 400

var _opened_ms: int = 0
var _released: Dictionary = {}
## A queued list re-open after "Back to Challenges" (set until it opens).
var _back_pending: bool = false


func open_menu() -> void:
	_opened_ms = Time.get_ticks_msec()
	_released.clear()
	super.open_menu()
	focus_index(0)


## The run's SubmitResult (R08.5: read from ctx on every rebuild).
func result() -> Dictionary:
	return ctx.get("result", {}) as Dictionary


func confirm_armed() -> bool:
	if Time.get_ticks_msec() - _opened_ms < arm_ms:
		return false
	for a in CONFIRM_ACTIONS:
		if not _released.has(a):
			return false
	return true


func _process(_delta: float) -> void:
	if not visible:
		return
	for a in CONFIRM_ACTIONS:
		if not Input.is_action_pressed(a):
			_released[a] = true
	if Engine.get_process_frames() == _opened_frame:
		return
	if cancel_pressed():
		back_to_challenges()
	elif Input.is_action_just_pressed(&"reset") and confirm_armed():
		retry(&"reset")


func rebuild() -> void:
	clear_body()
	var r := result()
	var ch := ChallengeLibrary.by_id(str(r.get("challenge", "")))
	add_label(Loc.t(str(r.get("title", ch.title if ch else ""))), UiTheme.ACCENT, UiTheme.FONT_SIZE + 2)
	for line in summary_lines(r, ch):
		add_label(line[0], line[1])
	var stages: Array = r.get("stages", [])
	if stages.size() > 1:
		for line in split_lines(r, ch):
			add_label(line, UiTheme.MUTED)
	if descent(r, ch):
		add_button(Loc.t("Descend again"), _guarded.bind(retry.bind(&"menu")))
		add_button(Loc.t("Leave"), _guarded.bind(quit_challenge))
		return
	add_button(Loc.t("Retry"), _guarded.bind(retry.bind(&"menu")))
	add_button(Loc.f("Ghost: {mode}", {"mode": Challenges.ghost_mode_label()}), _guarded.bind(_cycle_ghost))
	add_button(Loc.t("Back to Challenges"), _guarded.bind(back_to_challenges))
	add_button(Loc.t("Quit challenge"), _guarded.bind(quit_challenge))


## A Deep Rig descent (the NULL group) gets "Descend again / Leave"; every
## other run, staged or not, keeps Retry, Ghost, Back and Quit.
static func descent(r: Dictionary, ch: ChallengeData) -> bool:
	if ch != null:
		return ch.group == ChallengeData.Group.NULL
	return int(r.get("score_kind", -1)) == ChallengeData.ScoreKind.RANK and (r.get("stages", []) as Array).size() > 1


## [[text, colour], ...]: the outcome, the value and tier, a new best, the
## board rank and the next target.
static func summary_lines(r: Dictionary, ch: ChallengeData) -> Array:
	var out: Array = []
	var outcome := int(r.get("outcome", -1))
	var value := int(r.get("value", -1))
	var medal := int(r.get("medal", -1))
	if outcome != ChallengeData.Outcome.FINISHED or value < 0:
		out.append([cause_text(r), UiTheme.MUTED])
		out.append([Loc.f("Time {time}", {"time": RunClock.format(int(r.get("frames", 0)))}), UiTheme.MUTED])
		return out
	var kind := int(r.get("score_kind", ch.score_kind if ch else 0))
	var tier := Loc.t(RankLadder.name(maxi(medal, 0)))
	var line := ""
	match kind:
		ChallengeData.ScoreKind.TIME:
			line = Loc.f("{time}  {tier}", {"time": RunClock.format(value), "tier": tier})
		ChallengeData.ScoreKind.SCORE:
			line = Loc.f("Score {score}  {tier}", {"score": value, "tier": tier})
		_:
			line = Loc.f("{tier}  ·  score {score}", {"score": value, "tier": tier})
	# R08.3: the same neutral tags the board row shows for this run.
	for w in ChallengesMenu.tag_words(r.get("tags", {}) as Dictionary):
		line += "  %s %s" % [ChallengesMenu.TAG_GLYPH, w]
	out.append([line, UiTheme.TEXT])
	var prev := int(r.get("prev_best", -1))
	if bool(r.get("new_best", false)):
		if prev >= 0 and kind == ChallengeData.ScoreKind.TIME:
			out.append([Loc.f("New personal best! {delta}", {"delta": RunClock.format_delta(value - prev)}), UiTheme.ACCENT])
		elif prev >= 0:
			out.append([Loc.f("New personal best! +{points}", {"points": value - prev}), UiTheme.ACCENT])
		else:
			out.append([Loc.t("New personal best!"), UiTheme.ACCENT])
	var rank := int(r.get("rank", 0))
	if rank > 0:
		out.append([Loc.f("Local board: #{rank}", {"rank": rank}), UiTheme.MUTED])
	var next := next_target(ch, medal, kind)
	if next != "":
		out.append([next, UiTheme.MUTED])
	return out


## The neutral cause of a run that did not finish.
static func cause_text(r: Dictionary) -> String:
	var cause := str(r.get("cause", ""))
	if cause != "":
		return cause
	match int(r.get("outcome", -1)):
		ChallengeData.Outcome.FAILED_HIT:
			return Loc.t("Run over: hit taken")
		ChallengeData.Outcome.FAILED_ATTACK:
			return Loc.t("Run over: attack used")
		ChallengeData.Outcome.DIED:
			return Loc.t("Run over: out of health")
	return Loc.t("Run over")


## "Next: Gold at 0:26" (nothing at the top tier or for RANK runs).
static func next_target(ch: ChallengeData, medal: int, kind: int) -> String:
	if ch == null or kind == ChallengeData.ScoreKind.RANK or ch.medal_thresholds.size() != 4:
		return ""
	var nxt := maxi(medal, 0) + 1
	if nxt > 4:
		return ""
	return Loc.f("Next: {tier} at {target}", {"tier": Loc.t(RankLadder.name(nxt)),
		"target": ChallengesMenu.target_text(ch, ch.medal_thresholds[nxt - 1])})


## A staged run's split table: "Static Lane  0:31.52  Gold  (-1.20)".
## The delta is against the stage best from before this run: a stage result
## carrying "prev_frames" uses it; otherwise the stored stage best is used
## only when it is not this very result (Challenges stores a new stage best
## at the stage clear, before the card opens, so comparing against it would
## always read +0.00). A new stage best without its previous time reads
## "(new best)".
static func split_lines(r: Dictionary, ch: ChallengeData) -> PackedStringArray:
	var out := PackedStringArray()
	for s: Dictionary in r.get("stages", []):
		var frames := int(s.get("frames", 0))
		var line := Loc.f("{stage}  {time}  {tier}", {"stage": Loc.t(str(s.get("title", ""))),
			"time": RunClock.format(frames), "tier": Loc.t(RankLadder.name(int(s.get("tier", 0))))})
		var prev := stage_prev_frames(r, ch, s)
		if prev >= 0:
			line += "  (%s)" % RunClock.format_delta(frames - prev)
		elif prev == STAGE_NEW_BEST:
			line += "  (%s)" % Loc.t("new best")
		out.append(line)
	return out


## stage_prev_frames: no earlier best to compare against.
const STAGE_NO_PREV := -1
## stage_prev_frames: this stage is the stored best and the earlier one is gone.
const STAGE_NEW_BEST := -2


## The previous best frames for stage result `s`, or STAGE_NO_PREV /
## STAGE_NEW_BEST.
static func stage_prev_frames(r: Dictionary, ch: ChallengeData, s: Dictionary) -> int:
	if s.has("prev_frames"):
		var pf := int(s["prev_frames"])
		return pf if pf >= 0 else STAGE_NO_PREV
	if ch == null:
		return STAGE_NO_PREV
	var best := Challenges.records.best_stage(ch.id, int(r.get("profile", Game.profile_id)), str(s.get("id", "")), ch.revision)
	if best.is_empty() or int(best.get("frames", -1)) < 0:
		return STAGE_NO_PREV
	if int(best["frames"]) == int(s.get("frames", 0)) and int(best.get("score", -1)) == int(s.get("score", -1)):
		return STAGE_NEW_BEST
	return int(best["frames"])


## Runs `action` only once confirming is armed (a held key never fires it).
func _guarded(action: Callable) -> void:
	if confirm_armed():
		action.call()


## A fresh attempt (Retry, Descend again, or the reset action).
func retry(reason: StringName = &"menu") -> void:
	close_menu()
	Challenges.restart(reason)


func _cycle_ghost() -> void:
	var i := focused_index()
	Challenges.cycle_ghost_mode()
	rebuild()
	focus_index(i)


## Leaves the run and opens the list again once Rook is back at the return
## point (the Relay rig spawn, or the title).
func back_to_challenges() -> void:
	var ret: Dictionary = Challenges.session.return_to.duplicate() if Challenges.session else {}
	if not _leave():
		return
	_back_pending = true
	_reopen_list(ret)


func quit_challenge() -> void:
	_leave()


## Closes the card and leaves the run. Challenges.quit() does nothing while a
## transition runs or the session is starting; then the card opens again
## so the player is never left frozen with no menu (R08.1). True when the
## run is over or on its way out.
func _leave() -> bool:
	close_menu()
	Challenges.quit()
	if left_run():
		return true
	open_menu()
	return false


static func left_run() -> bool:
	return not Challenges.active() or Challenges.phase() == Challenges.Phase.LEAVING


func _reopen_list(ret: Dictionary) -> void:
	var tree := get_tree()
	for i in 600:
		if not is_inside_tree():
			return
		if not Challenges.active() and not SceneRouter.transitioning and _return_ready(ret):
			break
		await tree.process_frame
	_back_pending = false
	if Challenges.active():
		# The run never left: bring the card back rather than strand a
		# frozen player with no menu.
		if Challenges.phase() == Challenges.Phase.FINISHED and not visible and is_inside_tree():
			open_menu()
		return
	var host := get_parent()
	if host == null or not host.has_method("open_with"):
		return
	var ctx_out: Dictionary = {"from": "title"} if bool(ret.get("title", false)) else ret
	host.call("open_with", &"challenges", ctx_out)


## Back at the title: its menu is up again. Back in a room: it is loaded.
func _return_ready(ret: Dictionary) -> bool:
	if bool(ret.get("title", false)):
		var title: Variant = get_parent().get("title") if get_parent() else null
		return title is MenuScreen and (title as MenuScreen).visible
	return SceneRouter.current_room != null


func back_pending() -> bool:
	return _back_pending
