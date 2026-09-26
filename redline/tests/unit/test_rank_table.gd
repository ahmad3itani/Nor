extends RedlineTestCase
## RankTable (M9 D3 §3.3 folded into challenges): the stage score out of 1000
## (time, damage, style), its RankLadder tier, the top-tier rule (no hits, no
## deaths, at or under the stage's redline) and the descent mean. Pure and
## table-driven: no Settings or Game state is read.


func _stage(par: float = 40.0, redline: float = 30.0, weight: float = 1.0) -> ChallengeStage:
	var s := ChallengeStage.new()
	s.id = "s"
	s.title = "S"
	s.par_s = par
	s.redline_s = redline
	s.style_weight = weight
	return s


func test_score_rows() -> void:
	var t := RankTable.new()
	# [seconds, hits, deaths, avg style rank, weight, want score, want tier]
	var rows := [
		[30.0, 0, 0, 4.0, 1.0, 1000, 4],   # redline time, clean, full style
		[29.0, 0, 0, 4.0, 1.0, 1000, 4],   # under redline clamps to full time
		[80.0, 0, 0, 4.0, 1.0, 500, 1],    # fail_mult × par: no time points
		[90.0, 0, 0, 0.0, 1.0, 300, 0],    # past it: clamps at 0, damage only
		[55.0, 0, 0, 4.0, 1.0, 750, 2],    # halfway in time
		[30.0, 1, 0, 4.0, 1.0, 925, 3],    # a hit: score is top-tier, the rule is not
		[30.0, 0, 1, 4.0, 1.0, 850, 3],    # a death: same
		[30.0, 1, 2, 4.0, 1.0, 700, 2],    # damage floors at 0
		[30.5, 0, 0, 4.0, 1.0, 995, 3],    # over redline: never the top tier
		[30.0, 0, 0, 2.0, 1.0, 900, 4],    # half style
		[30.0, 0, 0, 2.0, 2.0, 1000, 4],   # style weight doubles it
		[30.0, 0, 0, 8.0, 1.0, 1000, 4],   # style clamps
	]
	for r: Array in rows:
		var st := _stage(40.0, 30.0, r[4])
		var s := t.score(r[0], r[1], r[2], r[3], st)
		check(s == r[5], "score %s -> %d (want %d)" % [r, s, r[5]])
		var tier := t.rank_of(s, r[0], r[1], r[2], st)
		check(tier == r[6], "tier %s -> %d (want %d)" % [r, tier, r[6]])


func test_tier_edges() -> void:
	var t := RankTable.new()
	var rows := [[-1, -1], [0, 0], [449, 0], [450, 1], [649, 1], [650, 2], [819, 2], [820, 3], [899, 3], [900, 4], [1000, 4]]
	for r: Array in rows:
		check(t.tier_for_score(r[0]) == r[1], "tier_for_score(%d) = %d (want %d)" % [r[0], t.tier_for_score(r[0]), r[1]])


func test_fail_mult_moves_the_zero_point() -> void:
	var t := RankTable.new()
	t.fail_mult = 3.0
	# zero time points at 120 s for par 40: 80 s is halfway to redline 30.
	var s := t.score(75.0, 0, 0, 0.0, _stage())
	check(s == 300 + 250, "fail_mult 3: %d" % s)


func test_descent_mean_and_top_tier_needs_all() -> void:
	var t := RankTable.new()
	check(RankTable.mean_score([100, 201]) == 151, "mean rounds")
	check(RankTable.mean_score([]) == 0, "empty mean")
	check(t.run_rank([{"score": 1000, "tier": 4}, {"score": 1000, "tier": 4}]) == 4, "all top -> top")
	check(t.run_rank([{"score": 1000, "tier": 4}, {"score": 950, "tier": 3}]) == 3, "one stage short of top caps the run")
	check(t.run_rank([{"score": 500, "tier": 1}, {"score": 800, "tier": 2}]) == 2, "mean 650 -> tier 2")
	check(t.run_rank([]) == -1, "no stages -> no rank")
	t.run_redline_needs_all = false
	check(t.run_rank([{"score": 1000, "tier": 4}, {"score": 950, "tier": 3}]) == 4, "the rule is data")


func test_validate() -> void:
	check(RankTable.new().validate().is_empty(), "defaults validate: %s" % [RankTable.new().validate()])
	var bad := RankTable.new()
	bad.thresholds = PackedInt32Array([0, 500, 400, 800, 900])
	bad.style_points = 100
	var errs := bad.validate()
	check(errs.size() >= 2, "unordered thresholds and a bad point sum are errors: %s" % [errs])
