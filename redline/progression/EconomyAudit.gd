class_name EconomyAudit
extends RefCounted
## Scrap sources vs sinks for the world on the map (bible §12 "avoid currency
## bloat"), computed from room scenes and data so it can't drift:
## - one_time: secret bundles, wall stashes, quest and dialogue rewards,
##   the boss, and every placed enemy once;
## - per_clear: what a full re-clear of the respawning enemies pays;
## - sinks: every shop item at list price, plus every upgrade tier bought
##   with Scrap (one price per Mk III branch group, the highest; granted
##   tiers are no sink, D-218);
## - by_district: the placed Scrap (bundles, walls, enemies, boss, one_time,
##   per_clear) of each map district, so ECONOMY.md can show where the
##   income comes from. Quests, dialogue and sinks are not per-district.
## Per act (D-187): each district's act comes from its DistrictTheme.act,
## quests from QuestData.act, shop stock from ShopItem.act and upgrade tiers
## from UpgradeData/UpgradeTier.act; sinks_by_act, one_time_by_act and
## per_clear_by_act feed the cumulative bands in test_economy.
## Pending districts (D-187): a district whose theme has economy_final =
## false is still being built. Its rooms, and every quest, shop item and
## upgrade tier of an act with no final district, are tallied under
## r["pending"] only, until its economy merge flips the flag
## (include_pending = true audits them anyway).
## repeatable_sinks: the Mk III rebranch price per upgrade, kept out of the
## one-time bands and the re-clear cap.
## compute(true) audits one NG+ cycle (D-155, R09.2, R09.11): every room with
## its remix applied (forced, whatever the flags say), plain Scrap bundles
## already taken (carried), secret stashes paying NgPlusConfig.
## secret_scrap_scale, everything else (walls, enemies, bosses, quests,
## dialogue) paid again. "ng_secret_bundles" is that stash income.

const STATION_KEYS := {UpgradeData.Station.WORKBENCH: "upgrades_workbench", UpgradeData.Station.VELL: "upgrades_vell",
	UpgradeData.Station.LUMA: "upgrades_luma"}


static func compute(remix := false, include_pending := false) -> Dictionary:
	var r := {"bundles": 0, "walls": 0, "enemies_first_clear": 0, "boss": 0, "quests": 0, "dialogue": 0, "sinks": 0, "sink_items": {}, "by_district": {},
		"ng_secret_bundles": 0, "upgrade_sinks": 0, "sinks_by_act": {}, "one_time_by_act": {}, "per_clear_by_act": {},
		"repeatable_sinks": {},
		"pending": {"bundles": 0, "walls": 0, "enemies_first_clear": 0, "boss": 0, "quests": 0, "sinks": 0, "districts": []}}
	var scale := NewGamePlus.config().secret_scrap_scale
	var final_acts: Array = []
	var themes := {}
	for d in Game.world_map.districts():
		var th := district_theme(String(d))
		themes[String(d)] = th
		if (include_pending or th["final"]) and not final_acts.has(th["act"]):
			final_acts.append(th["act"])
	for room in Game.world_map.rooms:
		var district := String(room.district)
		var th: Dictionary = themes.get(district, district_theme(district))
		var inst := (load(room.room_path) as PackedScene).instantiate()
		RoomTemplate.expand_all(inst)
		var placed := {"bundles": 0, "walls": 0, "enemies_first_clear": 0, "boss": 0}
		var ng_bundles := 0
		if remix:
			RemixLibrary.apply(inst, room.room_path, true)
			var secret := NewGamePlus.secret_bundles_in(inst)
			for n in inst.find_children("*", "Collectible", true, false):
				var c := n as Collectible
				if c.kind == Collectible.Kind.SCRAP_BUNDLE and secret.has(c.persist_id):
					var pay := roundi(c.scrap_amount * scale)
					placed["bundles"] += pay
					ng_bundles += pay
			# Bundles are counted above (plain ones stay taken in NG+).
			tally(inst, placed, false)
		else:
			tally(inst, placed)
		inst.free()
		if not include_pending and not th["final"]:
			for k in placed:
				r["pending"][k] += placed[k]
			if not (r["pending"]["districts"] as Array).has(district):
				(r["pending"]["districts"] as Array).append(district)
			continue
		r["ng_secret_bundles"] += ng_bundles
		if not r["by_district"].has(district):
			r["by_district"][district] = {"bundles": 0, "walls": 0, "enemies_first_clear": 0, "boss": 0, "act": th["act"]}
		for k in placed:
			r[k] += placed[k]
			r["by_district"][district][k] += placed[k]
	for d in r["by_district"].values():
		d["one_time"] = d["bundles"] + d["walls"] + d["enemies_first_clear"] + d["boss"]
		d["per_clear"] = d["enemies_first_clear"]
		_add(r["one_time_by_act"], d["act"], d["one_time"])
		_add(r["per_clear_by_act"], d["act"], d["per_clear"])
	for path in DataDir.list("res://data/quests"):
		var q := load(path) as QuestData
		if q == null:
			continue
		if final_acts.has(q.act):
			r["quests"] += q.reward_scrap
			_add(r["one_time_by_act"], q.act, q.reward_scrap)
		else:
			r["pending"]["quests"] += q.reward_scrap
	# Conversations carry no act; their Scrap is Act I (arcs give none, D-122).
	for path in DataDir.list("res://data/npcs"):
		var npc := load(path) as NpcProfile
		if npc == null:
			continue
		for rule in npc.rules:
			if rule.dialogue:
				r["dialogue"] += rule.dialogue.give_scrap
				_add(r["one_time_by_act"], 1, rule.dialogue.give_scrap)
	for path in DataDir.list("res://data/shops"):
		var shop := load(path) as ShopData
		if shop == null:
			continue
		var total := 0
		for item in shop.items:
			var price := item.price
			if price <= 0:
				var c := Game.catalog.circuit(item.item_id) as CircuitData
				price = c.price if c else 0
			var cost := price * maxi(1, item.max_purchases if item.kind == ShopItem.Kind.UPGRADE else 1)
			if final_acts.has(item.act):
				total += cost
				_add(r["sinks_by_act"], item.act, cost)
			else:
				r["pending"]["sinks"] += cost
		r["sink_items"][String(shop.id)] = total
		r["sinks"] += total
	for key in STATION_KEYS.values():
		r["sink_items"][key] = 0
	for u in UpgradeLibrary.all():
		var key: String = STATION_KEYS.get(u.station, "upgrades_workbench")
		for row: Vector2i in UpgradeLibrary.sink_rows(u):
			if final_acts.has(row.x):
				r["sink_items"][key] += row.y
				r["upgrade_sinks"] += row.y
				r["sinks"] += row.y
				_add(r["sinks_by_act"], row.x, row.y)
			else:
				r["pending"]["sinks"] += row.y
		if u.branch_start() >= 0:
			r["repeatable_sinks"][u.id] = u.rebranch_price
	r["one_time"] = r["bundles"] + r["walls"] + r["enemies_first_clear"] + r["boss"] + r["quests"] + r["dialogue"]
	r["per_clear"] = r["enemies_first_clear"]
	r["coverage"] = float(r["one_time"]) / maxi(1, r["sinks"])
	r["final_acts"] = final_acts
	return r


## {act, final} of a district from data/districts/<id>.tres (act 1 and final
## when the theme is missing).
static func district_theme(district: String) -> Dictionary:
	var path := "res://data/districts/%s.tres" % district
	var th: DistrictTheme = load(path) as DistrictTheme if ResourceLoader.exists(path) else null
	if th == null:
		return {"act": 1, "final": true}
	return {"act": th.act, "final": th.economy_final}


## Sum of `by_act` over every act <= `act` (the cumulative bands).
static func up_to(by_act: Dictionary, act: int) -> int:
	var total := 0
	for a in by_act:
		if int(a) <= act:
			total += int(by_act[a])
	return total


static func _add(by_act: Dictionary, act: int, amount: int) -> void:
	by_act[act] = int(by_act.get(act, 0)) + amount


## Adds one (expanded) room's placed Scrap to `r`. Bosses are one-time
## income (data.boss), never part of a respawning re-clear. Schematics carry
## no Scrap and are skipped like every non-bundle Collectible.
static func tally(inst: Node, r: Dictionary, bundles := true) -> void:
	for n in inst.find_children("*", "", true, false):
		if n is Collectible and (n as Collectible).kind == Collectible.Kind.SCRAP_BUNDLE:
			if bundles:
				r["bundles"] += (n as Collectible).scrap_amount
		elif n is BreakableWall:
			r["walls"] += (n as BreakableWall).scrap_inside
		elif n is Enemy and (n as Enemy).data:
			var drop := (n as Enemy).data.scrap_drop
			if (n as Enemy).data.boss:
				r["boss"] += drop
			else:
				r["enemies_first_clear"] += drop
