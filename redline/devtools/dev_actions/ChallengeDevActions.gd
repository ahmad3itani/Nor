class_name ChallengeDevActions
extends RefCounted
## Dev console helpers for challenges (M9 D2 §8.3, T08). Debug builds only
## (the dev console never opens in a release export). Nothing here is
## player-facing, so the text is English only.
##
## They go through the same Challenges API the menus use: a dev start is a
## normal run (the profile is sandboxed and restored), only the unlock check
## is skipped. Every entry point is gated on DevActions.available() (D2
## §8.3). Anything that fabricates progress taints the real profile
## (dev_tainted, D-145, like DevActions' grants): a start that bypasses an
## unlock, a made-up finish, and a campaign clock reset.

## Ghost debug lines on the F1 overlay (segment and frame of every ghost).
static var ghost_debug: bool = false


## Starts `id` ignoring unlocks and reveal state. A world room is the return
## point (its default spawn); anywhere else the run just ends in place.
static func start(id: String) -> bool:
	if not DevActions.available():
		return false
	var ch := ChallengeLibrary.by_id(id)
	if ch == null:
		push_warning("ChallengeDevActions.start: unknown challenge '%s'" % id)
		return false
	var room := SceneRouter.current_room as Room
	var ret := {}
	if room and room.world_room and not Challenges.active():
		ret = {"room": SceneRouter.current_room_path, "entry": StringName(Game.state.last_entry_id)}
	var bypass := not ChallengeLibrary.unlocked(ch)
	if not Challenges.start(ch, ret):
		return false
	if bypass:
		taint()
	return true


## Marks the real profile (the held one during a run) as dev-fabricated:
## lifetime stats and achievements stop counting it (Platform gates).
static func taint() -> void:
	var p: GameState = Game.held_profile if Game.held_profile != null else Game.state
	p.dev_tainted = true


## The value that earns tier `tier` (0 Clear .. 4 Redline) on `ch`, or -1
## for RANK runs (their tier comes from the stage table).
static func value_for_tier(ch: ChallengeData, tier: int) -> int:
	if ch.score_kind == ChallengeData.ScoreKind.RANK or ch.medal_thresholds.size() != 4:
		return -1
	var m := ch.medal_thresholds
	if tier <= 0:
		return m[0] + RunClock.FPS if ch.score_kind == ChallengeData.ScoreKind.TIME else maxi(0, m[0] - 1)
	return m[clampi(tier, 1, 4) - 1]


## Ends the live run as a finish worth `tier` (for result-card and
## achievement checks). TIME runs set the clock to the tier's frames.
static func finish_as(tier: int) -> bool:
	if not DevActions.available() or not Challenges.active() or Challenges.phase() != Challenges.Phase.RUNNING:
		return false
	# Tainted before finish(): its challenge_finished must not reach the
	# lifetime stats (StatsTracker reads Platform.lifetime_allowed()).
	taint()
	var ch := Challenges.current()
	var v := value_for_tier(ch, tier)
	if v >= 0 and ch.score_kind == ChallengeData.ScoreKind.TIME:
		Challenges.clock.frames = v
	Challenges.finish(ChallengeData.Outcome.FINISHED)
	return true


## Ends the live run as a rule failure: &"hit" or &"attack".
static func fail_now(kind: StringName) -> bool:
	if not DevActions.available() or not Challenges.active() or Challenges.phase() != Challenges.Phase.RUNNING:
		return false
	var hit := kind == &"hit"
	Challenges.session.cause = RuleWatch.cause_line("") if hit else Loc.t("Run over: attack used")
	Challenges.finish(ChallengeData.Outcome.FAILED_HIT if hit else ChallengeData.Outcome.FAILED_ATTACK)
	return true


## Forgets one challenge's records ("" = every record and PB ghost).
static func clear_records(id: String = "") -> void:
	if DevActions.available():
		Challenges.records.clear(id)


static func set_ghost_debug(on: bool) -> void:
	ghost_debug = on and DevActions.available()
	on = ghost_debug
	if on and not DebugOverlay.providers.has(ghost_lines):
		DebugOverlay.providers.append(ghost_lines)
	elif not on:
		DebugOverlay.providers.erase(ghost_lines)


## "GHOST pb frame 412/1021 room NeonRoofs x 530 y -96" per loaded ghost.
static func ghost_lines() -> PackedStringArray:
	var out := PackedStringArray()
	if not ghost_debug or not Challenges.active():
		return out
	for g in Challenges.ghosts:
		var f := g.frame_at(Challenges.clock.frames)
		if f.is_empty():
			continue
		out.append("GHOST %s frame %d/%d room %s x %d y %d%s" % [g.kind, mini(Challenges.clock.frames, g.data.frames),
			g.data.frames, str(f.get("room", "")).get_file().get_basename(), int(f.get("x", 0)), int(f.get("y", 0)),
			" (done)" if bool(f.get("finished", false)) else ""])
	return out


## Editor builds only: copies this profile's PB ghost over the shipped rig
## ghost as a hand-played one ("dev_hand": GhostBake --check skips it).
## Returns the written path, or "" when there is nothing to promote.
static func promote_pb_ghost(id: String) -> String:
	if not OS.has_feature("editor") or not DevActions.available():
		return ""
	var ch := ChallengeLibrary.by_id(id)
	if ch == null:
		return ""
	var src := Challenges.records.pb_ghost(id, Game.profile_id, ch.revision)
	if src == null:
		return ""
	# A copy: the PB ghost itself is never edited.
	var g := GhostData.new()
	g.apply_header(src.header())
	g.samples = src.samples.duplicate()
	g.kind = "dev_hand"
	g.profile = 0
	var path := "%s/%s.ghost" % [GhostBake.DEFAULT_OUT, id]
	return path if GhostCodec.save(path, g) == OK else ""


## "IGT 12:04.33 · 3 splits (last ll_power)" for the live profile.
static func campaign_summary() -> String:
	var s := Game.state
	var last := ""
	var best := -1
	for k: String in s.igt_splits:
		if int(s.igt_splits[k]) > best:
			best = int(s.igt_splits[k])
			last = k
	return "IGT %s · %d splits%s%s" % [RunClock.format(s.igt_frames), s.igt_splits.size(),
		" (last %s)" % last if last != "" else "", "" if s.igt_complete else " · incomplete (pre-M9 save)"]


## Zeroes the campaign clock and its splits on the live profile. The clock
## no longer covers the whole playthrough, so the profile stops counting as
## a complete M9 campaign (igt_complete off): act1_end never submits a
## campaign best from a reset clock.
static func reset_campaign_clock() -> void:
	if not DevActions.available():
		return
	Game.state.igt_frames = 0
	Game.state.igt_splits = {}
	Game.state.igt_complete = false
