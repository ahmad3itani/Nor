extends RedlineTestCase
## Economy sanity (bible §12): a thorough first run should afford a real
## share of the stock but not all of it, so purchases are choices; farming
## respawning enemies should be possible but slow.


## test_pending_district_excluded flips the cached Lowlight theme; put it
## back even if that test stops early.
func after_each() -> void:
	var th := load("res://data/districts/lowlight.tres") as DistrictTheme
	if th != null:
		th.economy_final = true


func test_scrap_sources_vs_sinks() -> void:
	var e := EconomyAudit.compute()
	print("ECONOMY %s" % JSON.stringify(e))
	check(int(e["sinks"]) > 0 and int(e["one_time"]) > 0, "audit found nothing")
	var cov := float(e["coverage"])
	check(cov >= 0.45 and cov <= 0.85, "one-time Scrap should cover 45-85%% of all stock, covers %d%%" % roundi(cov * 100.0))
	# Essentials (map + transit) must be affordable early from the first rooms' income.
	check(int(e["bundles"]) + int(e["enemies_first_clear"]) >= 100, "early income too low for the base map + transit pass")
	# Respawning enemies can be farmed, but a full re-clear of the route pays
	# at most 15% of all stock: exploring stays the better income.
	check(float(e["per_clear"]) <= 0.15 * float(e["sinks"]), "re-clearing pays too much (%d of %d)" % [e["per_clear"], e["sinks"]])


## Bosses are counted by data.boss, not by id: the Collector's 80 Scrap is
## one-time "boss" income, never part of the respawning per-clear.
func test_bosses_counted_by_data_flag() -> void:
	var e := EconomyAudit.compute()
	check(int(e["boss"]) >= 150, "Warden Krail's drop should be under boss (%d)" % e["boss"])
	var room := Node2D.new()
	room.add_child((load("res://bosses/CollectorDrone.tscn") as PackedScene).instantiate())
	room.add_child((load("res://enemies/variants/Needle.tscn") as PackedScene).instantiate())
	var r := {"bundles": 0, "walls": 0, "enemies_first_clear": 0, "boss": 0}
	EconomyAudit.tally(room, r)
	room.free()
	check(int(r["boss"]) == 80, "the Collector Drone's 80 Scrap should count as boss (%d)" % r["boss"])
	var needle_drop := (load("res://data/enemies/needle.tres") as EnemyData).scrap_drop
	check(int(r["enemies_first_clear"]) == needle_drop, "only regular enemies are per-clear (%d)" % r["enemies_first_clear"])


## The per-district breakdown adds up to the world totals, so ECONOMY.md's
## district table can't disagree with the headline numbers.
func test_district_breakdown_sums_to_totals() -> void:
	var e := EconomyAudit.compute()
	var by: Dictionary = e["by_district"]
	check(by.has("undercity") and by.has("lowlight"), "districts missing from the breakdown: %s" % [by.keys()])
	for k in ["bundles", "walls", "enemies_first_clear", "boss"]:
		var sum := 0
		for d in by.values():
			sum += int(d[k])
		check(sum == int(e[k]), "%s: districts sum to %d, total is %d" % [k, sum, e[k]])


## M7 D5b audit: the Undercity's Scrap as built (Docs/ECONOMY.md). The
## opening district pays mostly through exploration: 180 in stashes, 50 in
## wall secrets and the Collector's one-time 80, against 71 from a re-clear
## (the dormant Needle in Medical Ruin drops nothing). If this fails after a
## deliberate content change, re-run --filter=economy and update ECONOMY.md.
func test_undercity_income_as_audited() -> void:
	var u: Dictionary = EconomyAudit.compute()["by_district"].get("undercity", {})
	var want := {"bundles": 180, "walls": 50, "enemies_first_clear": 71, "boss": 80, "one_time": 381, "per_clear": 71}
	for k in want:
		check(int(u.get(k, -1)) == want[k], "undercity %s is %d, audited %d" % [k, int(u.get(k, -1)), want[k]])
	var dormant := load("res://data/enemies/needle_dormant.tres") as EnemyData
	check(dormant.scrap_drop == 0, "the dormant Needle must drop nothing (%d)" % dormant.scrap_drop)


## M9 NG+ (D-155, R09.2, R09.11): one NG+ cycle with the remix on pays no
## more than the base game. Swapped or re-tuned enemies keep their base drop
## and added ones drop nothing, so a re-clear pays exactly the base; plain
## bundles stay taken and secret stashes pay a quarter, so the cycle's
## one-time income is below the first run's (nothing is paid twice in full).
## The refilled stashes stay under the re-clear cap as well.
func test_remix_never_inflates_economy() -> void:
	var base := EconomyAudit.compute()
	var ng := EconomyAudit.compute(true)
	print("ECONOMY_NG %s" % JSON.stringify({"per_clear": ng["per_clear"], "one_time": ng["one_time"], "bundles": ng["bundles"],
		"ng_secret_bundles": ng["ng_secret_bundles"], "base_per_clear": base["per_clear"], "base_one_time": base["one_time"]}))
	check(int(ng["per_clear"]) <= int(base["per_clear"]), "NG+ re-clear pays %d, base %d" % [ng["per_clear"], base["per_clear"]])
	check(int(ng["per_clear"]) == int(base["per_clear"]), "remix on is no hidden Scrap penalty either (R09.11): %d vs %d" % [ng["per_clear"], base["per_clear"]])
	check(int(ng["one_time"]) <= int(base["one_time"]), "NG+ one-time %d is not above base %d" % [ng["one_time"], base["one_time"]])
	check(int(ng["bundles"]) < int(base["bundles"]), "no bundle is paid again in full (%d of %d)" % [ng["bundles"], base["bundles"]])
	check(int(ng["bundles"]) == int(ng["ng_secret_bundles"]), "only secret stashes pay in NG+ (%d vs %d)" % [ng["bundles"], ng["ng_secret_bundles"]])
	check(int(ng["boss"]) == int(base["boss"]), "the bosses pay as in the first run")
	check(int(ng["ng_secret_bundles"]) > 0, "secret stashes refill with some Scrap")
	check(float(ng["ng_secret_bundles"]) <= 0.15 * float(base["sinks"]), "refilled stashes stay under the re-clear cap (%d)" % ng["ng_secret_bundles"])
	# The audit forces each remix on its own copy; nothing stays forced.
	check(not RemixLibrary.force_active, "compute(true) does not flip the global force")


# --- Upgrades and per-act bands (expansion PW1, D-187, D-218) --------------------

## Upgrade tiers are sinks at list price: one price per Mk III branch group
## (the highest, only one can be bought) and none for a granted tier.
## Phase 1: 1,210 of workbench/Vell stock, 1,050 counted (Surge I is
## installed free by Mara, D-218).
func test_upgrade_sinks_counted() -> void:
	var e := EconomyAudit.compute()
	check(int(e["upgrade_sinks"]) == UpgradeLibrary.sink_total(), "audit %d = library %d" % [e["upgrade_sinks"], UpgradeLibrary.sink_total()])
	check(int(e["upgrade_sinks"]) == 1050, "Phase-1 upgrade sinks 1,050 (%d)" % e["upgrade_sinks"])
	var items: Dictionary = e["sink_items"]
	check(int(items.get("upgrades_workbench", -1)) == 810 and int(items.get("upgrades_vell", -1)) == 240
		and int(items.get("upgrades_luma", -1)) == 0, "per station: %s" % [items])
	check(UpgradeLibrary.sink_of(UpgradeLibrary.get_upgrade("surge")) == 0, "the granted Surge I is no sink")
	var u := UpgradeData.new()
	u.id = "test_econ_branch"
	for spec in [[50, 0], [100, 1], [160, 2], [90, 3]]:
		var t := UpgradeTier.new()
		t.price = spec[0]
		t.branch = spec[1]
		t.values = {"riposte": 1}
		u.tiers.append(t)
	check(UpgradeLibrary.sink_of(u) == 210, "a branch group counts its highest price once (%d)" % UpgradeLibrary.sink_of(u))
	u.tiers[3].act = 2
	u.tiers[1].act = 2
	u.tiers[2].act = 2
	check(UpgradeLibrary.sink_of(u, 1) == 50 and UpgradeLibrary.sink_of(u, 2) == 210, "per-act: the group is in its first tier's act")
	check(UpgradeLibrary.sink_of(u, 99, [1]) == 50, "a non-final act is left out")


## Each finished act, counted with everything before it, stays in the bands
## the flat test uses, so later stock never hides an over-generous Act I.
## Acts 2+ also hold alone. Pins the PW1 numbers (ECONOMY.md).
func test_act_cumulative_bands() -> void:
	var e := EconomyAudit.compute()
	print("ECONOMY_ACTS %s" % JSON.stringify({"sinks_by_act": e["sinks_by_act"], "one_time_by_act": e["one_time_by_act"],
		"per_clear_by_act": e["per_clear_by_act"], "final_acts": e["final_acts"], "pending": e["pending"]}))
	var acts: Array = e["final_acts"]
	check(acts.has(1), "Act I is final")
	for a: int in acts:
		var sinks := EconomyAudit.up_to(e["sinks_by_act"], a)
		var one := EconomyAudit.up_to(e["one_time_by_act"], a)
		var per := EconomyAudit.up_to(e["per_clear_by_act"], a)
		var cov := float(one) / maxf(1.0, float(sinks))
		check(cov >= 0.45 and cov <= 0.85, "acts <= %d: one-time covers %d%% of stock (%d / %d)" % [a, roundi(cov * 100.0), one, sinks])
		check(float(per) <= 0.15 * float(sinks), "acts <= %d: re-clear %d over 15%% of %d" % [a, per, sinks])
		if a >= 2:
			var s1 := int(e["sinks_by_act"].get(a, 0))
			var o1 := int(e["one_time_by_act"].get(a, 0))
			var c1 := float(o1) / maxf(1.0, float(s1))
			check(c1 >= 0.45 and c1 <= 0.85, "act %d alone: %d%%" % [a, roundi(c1 * 100.0)])
	check(int(e["sinks"]) == 3280 and int(e["one_time"]) == 1772 and int(e["per_clear"]) == 332,
		"PW1 pins: sinks 3,280, one-time 1,772, re-clear 332 (%d / %d / %d)" % [e["sinks"], e["one_time"], e["per_clear"]])
	check(EconomyAudit.up_to(e["sinks_by_act"], 99) == int(e["sinks"]), "per-act sinks add up")
	check(EconomyAudit.up_to(e["one_time_by_act"], 99) == int(e["one_time"]), "per-act one-time adds up")


## K-49 closed (remedy 3, D-187): the re-clear sits at least 150 Scrap under
## its cap, so new respawning enemies have room again.
func test_k49_headroom() -> void:
	var e := EconomyAudit.compute()
	var headroom := 0.15 * float(e["sinks"]) - float(e["per_clear"])
	check(headroom >= 150.0, "re-clear headroom %.1f (cap %.1f, re-clear %d)" % [headroom, 0.15 * float(e["sinks"]), e["per_clear"]])


## A district still being built (economy_final = false) contributes only to
## r["pending"]: its rooms leave the totals and the district table.
func test_pending_district_excluded() -> void:
	var base := EconomyAudit.compute()
	var th := load("res://data/districts/lowlight.tres") as DistrictTheme
	th.economy_final = false
	var e := EconomyAudit.compute()
	var with_all := EconomyAudit.compute(false, true)
	th.economy_final = true
	var low: Dictionary = base["by_district"]["lowlight"]
	check(not (e["by_district"] as Dictionary).has("lowlight"), "a pending district leaves the table")
	check(int(e["pending"]["enemies_first_clear"]) == int(low["enemies_first_clear"]) and int(e["pending"]["bundles"]) == int(low["bundles"])
		and int(e["pending"]["walls"]) == int(low["walls"]) and int(e["pending"]["boss"]) == int(low["boss"]), "its Scrap is pending: %s" % [e["pending"]])
	check(int(e["one_time"]) == int(base["one_time"]) - int(low["one_time"]), "one-time drops by the district's")
	check(int(e["per_clear"]) == int(base["per_clear"]) - int(low["per_clear"]), "re-clear drops too")
	check(int(e["sinks"]) == int(base["sinks"]), "Act I stock stays (Undercity is a final Act I district)")
	check(int(with_all["one_time"]) == int(base["one_time"]), "include_pending audits it anyway")
	check((e["pending"]["districts"] as Array).has("lowlight"), "pending names the district")
