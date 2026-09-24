class_name DevActions
extends RefCounted
## Internal development tools (bible §34: teleport-to-room, unlock-all
## debug profile, quick boss restart, enemy spawning, save-state inspector,
## hitbox visualization, performance overlay). The DevConsole menu calls
## these; tests call them directly. Debug/editor builds only.

const VARIANT_DIR := "res://enemies/variants"


static func available() -> bool:
	return OS.is_debug_build() or OS.has_feature("editor")


## Every world room and its entries, for the teleport list.
static func teleport_targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in Game.world_map.rooms:
		var info := WorldMapIndex.room_info(r.room_path)
		var ids: Array = (info["spawns"] as Dictionary).keys()
		ids.sort()
		for id: String in ids:
			out.append({"room": r.room_path, "entry": id, "label": "%s  ·  %s" % [info["name"], id]})
	return out


static func teleport(room_path: String, entry: String) -> void:
	SceneRouter.transition_to(room_path, StringName(entry))


## A profile that owns everything the game has, for testing late content:
## all weapons and Circuits, Dash, max shards, lots of Scrap, the map and
## transit, every room visited and fully explored, every Anchor on the line.
static func unlock_all() -> void:
	var st := Game.state
	for w in Game.catalog.weapons:
		if not st.owned_weapons.has(String(w.id)):
			st.owned_weapons.append(String(w.id))
	for c in Game.catalog.circuits:
		if not st.owned_circuits.has(String(c.id)):
			st.owned_circuits.append(String(c.id))
	Game.set_ability(&"dash", true)
	st.core_shards = maxi(st.core_shards, 3)
	st.scrap_banked = maxi(st.scrap_banked, 9999)
	for f in ["transit_pass", "map_lowlight", "map_lens", "injector_upgrades"]:
		Game.set_flag(f, 1)
	for r in Game.world_map.rooms:
		if not st.visited_rooms.has(r.room_path):
			st.visited_rooms.append(r.room_path)
		var info := WorldMapIndex.room_info(r.room_path)
		var b: Rect2 = info["bounds"]
		var y := b.position.y + 32.0
		while y < b.end.y:
			var x := b.position.x + 32.0
			while x < b.end.x:
				MapProgress.reveal(st, Game.world_map, r.room_path, Vector2(x, y))
				x += 96.0
			y += 96.0
		for a: Dictionary in info["anchors"]:
			var key := "%s|%s" % [r.room_path, a["id"]]
			if not st.anchors_rested.has(key):
				st.anchors_rested.append(key)
	EventBus.scrap_changed.emit(st.total_scrap())
	EventBus.loadout_changed.emit()


## Re-arm Warden Krail (clear the win) and drop Rook at the arena door with
## full health: iterate on the fight without replaying the tower.
static func quick_boss_restart() -> void:
	Game.state.flags.erase("warden_krail_defeated")
	# Heal the live player too: leaving the room captures its state.
	var room := SceneRouter.current_room as Room
	if room and is_instance_valid(room.player):
		room.player.combat.rest()
	Game.state.health = -1
	Game.state.injectors = -1
	Game.state.reactor_charge = -1.0
	SceneRouter.transition_to("res://world/rooms/lowlight/WardenTower.tscn", &"from_bell")


static func enemy_scenes() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(VARIANT_DIR):
		if f.ends_with(".tscn"):
			out.append("%s/%s" % [VARIANT_DIR, f])
	return out


## Spawns an enemy 90 px in front of Rook in the current room.
static func spawn_enemy(scene_path: String) -> Enemy:
	var room := SceneRouter.current_room as Room
	if room == null or not is_instance_valid(room.player):
		return null
	var e := (load(scene_path) as PackedScene).instantiate() as Enemy
	e.position = room.player.position + Vector2(90.0 * room.player.facing, -2.0)
	room.add_child(e)
	return e


## Save-state inspector text: what the profile holds right now.
static func state_summary() -> String:
	var st := Game.state
	var flags: Array = st.flags.keys()
	flags.sort()
	var flag_text := PackedStringArray()
	for f: String in flags:
		flag_text.append("%s=%s" % [f, st.flags[f]])
	var lines := PackedStringArray([
		"Scrap %d banked + %d carried · shards %d · deaths %d · time %s" % [st.scrap_banked, st.scrap_unbanked, st.core_shards, st.deaths, SliceStats.format_time(st.play_time_sec)],
		"Respawn: %s / %s" % [st.last_anchor_room.get_file(), st.last_anchor_id],
		"Weapons: %s (melee %s, ranged %s)" % [", ".join(st.owned_weapons), st.melee_weapon, st.ranged_weapon],
		"Circuits: %s   equipped: %s" % [", ".join(st.owned_circuits), ", ".join(st.equipped_circuits)],
		"Collected (%d): %s" % [st.collected.size(), ", ".join(PackedStringArray(st.collected.keys()))],
		"Rooms visited %d · Anchors on the line %d · pins %d" % [st.visited_rooms.size(), st.anchors_rested.size(), st.map_pins.size()],
		"Flags (%d): %s" % [flags.size(), ", ".join(flag_text)],
	])
	return "\n".join(lines)


static func state_json() -> String:
	var d := Game.state.to_dict()
	d["schema_version"] = SaveManager.CURRENT_SCHEMA_VERSION
	return JSON.stringify(d, "  ")
