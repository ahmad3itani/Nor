extends RedlineTestCase
## Economy sanity (bible §12): a thorough first run should afford a real
## share of the stock but not all of it, so purchases are choices; farming
## respawning enemies should be possible but slow.


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
