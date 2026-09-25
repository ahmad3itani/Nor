class_name EconomyAudit
extends RefCounted
## Scrap sources vs sinks for the world on the map (bible §12 "avoid currency
## bloat"), computed from room scenes and data so it can't drift:
## - one_time: secret bundles, wall stashes, quest and dialogue rewards,
##   the boss, and every placed enemy once;
## - per_clear: what a full re-clear of the respawning enemies pays;
## - sinks: every shop item at list price;
## - by_district: the placed Scrap (bundles, walls, enemies, boss, one_time,
##   per_clear) of each map district, so ECONOMY.md can show where the
##   income comes from. Quests, dialogue and sinks are not per-district.


static func compute() -> Dictionary:
	var r := {"bundles": 0, "walls": 0, "enemies_first_clear": 0, "boss": 0, "quests": 0, "dialogue": 0, "sinks": 0, "sink_items": {}, "by_district": {}}
	for room in Game.world_map.rooms:
		var inst := (load(room.room_path) as PackedScene).instantiate()
		RoomTemplate.expand_all(inst)
		var placed := {"bundles": 0, "walls": 0, "enemies_first_clear": 0, "boss": 0}
		tally(inst, placed)
		inst.free()
		var district := String(room.district)
		if not r["by_district"].has(district):
			r["by_district"][district] = {"bundles": 0, "walls": 0, "enemies_first_clear": 0, "boss": 0}
		for k in placed:
			r[k] += placed[k]
			r["by_district"][district][k] += placed[k]
	for d in r["by_district"].values():
		d["one_time"] = d["bundles"] + d["walls"] + d["enemies_first_clear"] + d["boss"]
		d["per_clear"] = d["enemies_first_clear"]
	for f in DirAccess.get_files_at("res://data/quests"):
		if f.ends_with(".tres"):
			r["quests"] += (load("res://data/quests/" + f) as QuestData).reward_scrap
	for f in DirAccess.get_files_at("res://data/npcs"):
		if f.ends_with(".tres"):
			for rule in (load("res://data/npcs/" + f) as NpcProfile).rules:
				if rule.dialogue:
					r["dialogue"] += rule.dialogue.give_scrap
	for f in DirAccess.get_files_at("res://data/shops"):
		if not f.ends_with(".tres"):
			continue
		var shop := load("res://data/shops/" + f) as ShopData
		var total := 0
		for item in shop.items:
			var price := item.price
			if price <= 0:
				var c := Game.catalog.circuit(item.item_id) as CircuitData
				price = c.price if c else 0
			total += price * maxi(1, item.max_purchases if item.kind == ShopItem.Kind.UPGRADE else 1)
		r["sink_items"][String(shop.id)] = total
		r["sinks"] += total
	r["one_time"] = r["bundles"] + r["walls"] + r["enemies_first_clear"] + r["boss"] + r["quests"] + r["dialogue"]
	r["per_clear"] = r["enemies_first_clear"]
	r["coverage"] = float(r["one_time"]) / maxi(1, r["sinks"])
	return r


## Adds one (expanded) room's placed Scrap to `r`. Bosses are one-time
## income (data.boss), never part of a respawning re-clear.
static func tally(inst: Node, r: Dictionary) -> void:
	for n in inst.find_children("*", "", true, false):
		if n is Collectible and (n as Collectible).kind == Collectible.Kind.SCRAP_BUNDLE:
			r["bundles"] += (n as Collectible).scrap_amount
		elif n is BreakableWall:
			r["walls"] += (n as BreakableWall).scrap_inside
		elif n is Enemy and (n as Enemy).data:
			var drop := (n as Enemy).data.scrap_drop
			if (n as Enemy).data.boss:
				r["boss"] += drop
			else:
				r["enemies_first_clear"] += drop
