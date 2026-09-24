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
