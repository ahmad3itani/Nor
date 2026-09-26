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
	if descent(r):
		add_button(Loc.t("Descend again"), _guarded.bind(retry.bind(&"menu")))
		add_button(Loc.t("Leave"), _guarded.bind(quit_challenge))
		return
	add_button(Loc.t("Retry"), _guarded.bind(retry.bind(&"menu")))
	add_button(Loc.f("Ghost: {mode}", {"mode": Challenges.ghost_mode_label()}), _guarded.bind(_cycle_ghost))
	add_button(Loc.t("Back to Challenges"), _guarded.bind(back_to_challenges))
	add_button(Loc.t("Quit challenge"), _guarded.bind(quit_challenge))


static func descent(r: Dictionary) -> bool:
	return (r.get("stages", []) as Array).size() > 1


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
	match kind:
		ChallengeData.ScoreKind.TIME:
			out.append([Loc.f("{time}  {tier}", {"time": RunClock.format(value), "tier": tier}), UiTheme.TEXT])
		ChallengeData.ScoreKind.SCORE:
			out.append([Loc.f("Score {score}  {tier}", {"score": value, "tier": tier}), UiTheme.TEXT])
		_:
			out.append([Loc.f("{tier}  ·  score {score}", {"score": value, "tier": tier}), UiTheme.TEXT])
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
static func split_lines(r: Dictionary, ch: ChallengeData) -> PackedStringArray:
	var out := PackedStringArray()
	for s: Dictionary in r.get("stages", []):
		var line := Loc.f("{stage}  {time}  {tier}", {"stage": Loc.t(str(s.get("title", ""))),
			"time": RunClock.format(int(s.get("frames", 0))), "tier": Loc.t(RankLadder.name(int(s.get("tier", 0))))})
		if ch:
			var best := Challenges.records.best_stage(ch.id, int(r.get("profile", Game.profile_id)), str(s.get("id", "")), ch.revision)
			if not best.is_empty() and int(best.get("frames", -1)) >= 0:
				line += "  (%s)" % RunClock.format_delta(int(s.get("frames", 0)) - int(best["frames"]))
		out.append(line)
	return out


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
	close_menu()
	Challenges.quit()
	_back_pending = true
	_reopen_list(ret)


func quit_challenge() -> void:
	close_menu()
	Challenges.quit()


func _reopen_list(ret: Dictionary) -> void:
	var tree := get_tree()
	for i in 600:
		if not is_inside_tree():
			return
		if not Challenges.active() and not SceneRouter.transitioning and _return_ready(ret):
			break
		await tree.process_frame
	_back_pending = false
	var host := get_parent()
	if host == null or not host.has_method("open_with") or Challenges.active():
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
