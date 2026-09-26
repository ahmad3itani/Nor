extends RedlineTestCase
## RecordStore (M9 D2 §5, D-149): one profile-independent file under
## Platform.store_dir, top-10 boards (TIME lower-better, SCORE higher-better,
## ties by the earlier date), per-profile bests and attempt counts, failed
## runs counting attempts only, atomic writes with .bak recovery, revision
## archives, and memory-only use while the platform store is inactive.

const H := preload("res://tests/fixtures/challenges/ChallengeHarness.gd")

var h: H


func before_each() -> void:
	h = H.new(self, "records")
	h.setup()


func after_each() -> void:
	await h.teardown()


func _store() -> RecordStore:
	var r := RecordStore.new()
	r.now_override = 1000.0
	return r


func _score_ch() -> ChallengeData:
	var ch := H.fx(H.TRIAL)
	ch.id = "fx_score"
	ch.score_kind = ChallengeData.ScoreKind.SCORE
	ch.medal_thresholds = PackedInt32Array([100, 200, 300, 400])
	return ch


func test_top10_sort_time_and_score_ties_by_date() -> void:
	var r := _store()
	var ch := H.fx(H.TRIAL)
	var values := [900, 500, 700, 500, 1200, 650, 800, 1000, 1100, 1300, 1400, 400]
	for i in values.size():
		r.now_override = 1000.0 + i
		r.submit(ch, 1 + i % 2, values[i], ChallengeData.Outcome.FINISHED)
	var b := r.board(ch.id)
	check(b.size() == 10, "top 10 kept (%d)" % b.size())
	var got: Array = b.map(func(e: Dictionary) -> int: return int(e["value"]))
	check(got == [400, 500, 500, 650, 700, 800, 900, 1000, 1100, 1200], "time: lower first (%s)" % [got])
	check(float(b[1]["t"]) < float(b[2]["t"]), "equal times: the earlier run first")
	var res := r.submit(ch, 1, 5000, ChallengeData.Outcome.FINISHED)
	check(int(res["rank"]) == 0, "off the board: rank 0")
	var s := _score_ch()
	for v in [100, 400, 250, 400]:
		r.now_override += 1.0
		r.submit(s, 1, v, ChallengeData.Outcome.FINISHED)
	got = r.board(s.id).map(func(e: Dictionary) -> int: return int(e["value"]))
	check(got == [400, 400, 250, 100], "score: higher first (%s)" % [got])
	check(float(r.board(s.id)[0]["t"]) < float(r.board(s.id)[1]["t"]), "equal scores: the earlier first")


func test_pb_per_profile_and_new_best() -> void:
	var r := _store()
	var ch := H.fx(H.TRIAL)
	var a := r.submit(ch, 1, 1000, ChallengeData.Outcome.FINISHED)
	check(a["new_best"] and int(a["prev_best"]) == -1 and int(a["rank"]) == 1, "first finish is a best: %s" % [a])
	var b := r.submit(ch, 1, 1200, ChallengeData.Outcome.FINISHED)
	check(not b["new_best"] and int(b["prev_best"]) == 1000, "slower is not")
	var c := r.submit(ch, 2, 1500, ChallengeData.Outcome.FINISHED)
	check(c["new_best"], "each profile has its own best")
	var d := r.submit(ch, 1, 800, ChallengeData.Outcome.FINISHED, PackedInt32Array([300, 500]))
	check(d["new_best"] and int(r.best(ch.id, 1)["value"]) == 800 and int(r.best(ch.id, 2)["value"]) == 1500, "bests per profile")
	check(r.best(ch.id, 1)["splits"] == [300, 500], "the best keeps its splits")
	check(int(d["medal"]) == ch.medal_for(800) and int(d["medal"]) == 3, "medal by threshold (%d)" % int(d["medal"]))
	check(r.attempts(ch.id, 1) == 3 and r.clears(ch.id, 1) == 3 and r.attempts(ch.id, 2) == 1, "counts")


func test_failed_runs_count_attempts_only() -> void:
	var r := _store()
	var ch := H.fx(H.TRIAL)
	for o in [ChallengeData.Outcome.FAILED_HIT, ChallengeData.Outcome.FAILED_ATTACK, ChallengeData.Outcome.DIED]:
		var res := r.submit(ch, 1, -1, o)
		check(not res["new_best"] and int(res["medal"]) == -1 and int(res["rank"]) == 0, "failed: nothing posted (%s)" % [res])
	check(r.attempts(ch.id, 1) == 3 and r.clears(ch.id, 1) == 0, "attempts count, clears do not")
	check(r.board(ch.id).is_empty() and r.best(ch.id, 1).is_empty(), "no entry, no best")


func test_atomic_write_and_bak_recovery() -> void:
	var r := _store()
	var ch := H.fx(H.TRIAL)
	r.submit(ch, 1, 1000, ChallengeData.Outcome.FINISHED)
	r.submit(ch, 1, 900, ChallengeData.Outcome.FINISHED)
	check(FileAccess.file_exists(r.path()) and FileAccess.file_exists(r.path() + ".bak"), "file + .bak written")
	check(not FileAccess.file_exists(r.path() + ".tmp"), "no tmp left")
	var fresh := RecordStore.new()
	check(int(fresh.best(ch.id, 1)["value"]) == 900, "a new store reads the file")
	var f := FileAccess.open(r.path(), FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	var recovered := RecordStore.new()
	check(int(recovered.best(ch.id, 1)["value"]) == 1000, "a corrupt primary falls back to .bak (%s)" % [recovered.best(ch.id, 1)])


func test_revision_bump_archives() -> void:
	var r := _store()
	var ch := H.fx(H.TRIAL)
	r.submit(ch, 1, 1000, ChallengeData.Outcome.FINISHED)
	r.submit(ch, 1, 1100, ChallengeData.Outcome.FINISHED)
	var v2 := H.fx(H.TRIAL)
	v2.revision = 2
	var res := r.submit(v2, 1, 1500, ChallengeData.Outcome.FINISHED)
	check(res["new_best"] and int(res["prev_best"]) == -1, "a new revision starts a fresh best")
	check(r.board(ch.id).size() == 1 and r.archived_count(ch.id) == 2, "old entries archived (%d)" % r.archived_count(ch.id))
	check(r.attempts(ch.id, 1) == 1, "attempts restart with the revision")


func test_inactive_platform_keeps_memory_only() -> void:
	Platform.allow_headless = false
	check(not Platform.active(), "headless without opt-in: inactive")
	var r := _store()
	var ch := H.fx(H.TRIAL)
	r.submit(ch, 1, 1000, ChallengeData.Outcome.FINISHED)
	r.record_unlock(ch.id)
	check(not FileAccess.file_exists(r.path()), "nothing written")
	check(int(r.best(ch.id, 1)["value"]) == 1000 and r.ever_unlocked(ch.id), "kept in memory")
	var g := GhostData.new()
	g.add_sample(0, 0, 0, 0, 0)
	g.frames = 1
	check(r.save_pb_ghost(ch.id, 1, g) != OK and not FileAccess.file_exists(r.ghost_path(ch.id, 1)), "no ghost file")
	Platform.allow_headless = true


func test_store_follows_platform_dir() -> void:
	var r := _store()
	var ch := H.fx(H.TRIAL)
	r.submit(ch, 1, 1000, ChallengeData.Outcome.FINISHED)
	Platform.store_dir = h.platform_dir + "/other"
	check(r.best(ch.id, 1).is_empty(), "a new store_dir reloads (empty)")
	Platform.store_dir = h.platform_dir
	check(int(r.best(ch.id, 1)["value"]) == 1000, "and back")
