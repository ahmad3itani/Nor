class_name NullRules
extends RefCounted
## Deep Rig and Pulse Pit rules (M9 D3 §3.6, D-154/D-155) over the challenge
## rooms (res://world/rooms/challenge) and the NULL / PULSE_PIT challenge data.
## ('null' is an internal id; the player reads "Deep Rig".)
##   NU-1 a challenge room has no Anchor, Collectible, BreakableWall, NPC,
##        SliceEndTrigger, ScrapCache or MapMarker: runs keep nothing, heal
##        nowhere and never touch the map
##   NU-2 challenge rooms are off the world map and outside WORLD_ROOM_DIRS
##        (SliceStats and the economy never count them)
##   NU-3 every stage of a NULL-group challenge resolves to a ChallengeGoal
##        with its stage_id in the stage's room (on_boss = the stage's boss)
##   NU-4 a Deep Rig boss variant keeps §17 readable: its EnemyData passes
##        min_telegraph and its phase2_telegraph_scale is >= the 0.6 floor
##   NU-5 every *_null EnemyData drops no Scrap
##   NU-6 every WaveSpawn a challenge's WaveSet names exists in its room

const ROOM_DIR := "res://world/rooms/challenge"
const VARIANT_DIR := "res://bosses/variants"
const ENEMY_DIR := "res://data/enemies"
## Enemy's telegraph floor (Enemy._physics_process: maxf(telegraph_scale, 0.6)).
const TELEGRAPH_FLOOR := 0.6
const FORBIDDEN := ["Anchor", "Collectible", "BreakableWall", "NPC", "SliceEndTrigger", "ScrapCache", "MapMarker"]


static func run(v: ContentValidator) -> void:
	for path in DataDir.list_scenes(ROOM_DIR):
		var room := v.instantiate_room(path)
		if room == null:
			continue
		check_room(room, path, v)
		room.free()
	check_off_map(v)
	for ch in _challenges():
		check_challenge(ch, v)
	check_variants(v)
	check_enemy_data(v)


static func _challenges() -> Array[ChallengeData]:
	var out: Array[ChallengeData] = []
	for path in DataDir.list(ChallengeLibrary.DEFAULT_DIR):
		var ch := load(path) as ChallengeData
		if ch:
			out.append(ch)
	return out


## NU-1 for one room instance (tests pass fixtures).
static func check_room(room: Node, path: String, v: ContentValidator) -> void:
	for n in room.find_children("*", "", true, false):
		for cls in FORBIDDEN:
			if _is(n, cls):
				v.errors.append("[NU-1] %s: %s is a %s (challenge rooms keep nothing and never touch the map)" % [
					path.get_file(), n.name, cls])


static func _is(n: Node, cls: String) -> bool:
	var s: Script = n.get_script()
	while s:
		if s.get_global_name() == cls:
			return true
		s = s.get_base_script()
	return false


## NU-2: not on the world map, not a district folder.
static func check_off_map(v: ContentValidator) -> void:
	if ContentValidator.WORLD_ROOM_DIRS.has(ROOM_DIR):
		v.errors.append("[NU-2] %s is in ContentValidator.WORLD_ROOM_DIRS (SliceStats and the economy would count it)" % ROOM_DIR)
	if not ContentValidator.OFF_MAP_DIRS.has(ROOM_DIR):
		v.errors.append("[NU-2] %s is not in ContentValidator.OFF_MAP_DIRS" % ROOM_DIR)
	for path in DataDir.list_scenes(ROOM_DIR):
		if Game.world_map.room(path.get_file().get_basename()) != null:
			v.errors.append("[NU-2] %s is on the world map (challenge rooms stay off it)" % path.get_file())


## NU-3 (NULL group) and NU-6 (any challenge with a WaveSet).
static func check_challenge(ch: ChallengeData, v: ContentValidator) -> void:
	var tag := "%s.tres" % ch.id
	if ch.group == ChallengeData.Group.NULL:
		for i in ch.stage_count():
			var st := ch.stage(i)
			var room_path := ch.stage_room(i)
			var want_id := st.id if st else ch.id
			var want_boss := st.boss_id if st else ""
			var room := _load(room_path)
			if room == null:
				v.errors.append("[NU-3] %s: stage %s room %s does not load" % [tag, want_id, room_path])
				continue
			var found := false
			for g in room.find_children("*", "ChallengeGoal", true, false):
				var goal := g as ChallengeGoal
				if goal.stage_id == want_id and goal.on_boss == want_boss:
					found = true
			if not found:
				v.errors.append("[NU-3] %s: stage %s has no ChallengeGoal (stage_id '%s', on_boss '%s') in %s" % [
					tag, want_id, want_id, want_boss, room_path.get_file()])
			room.free()
	var ws := ch.waves as WaveSet
	if ch.waves != null and ws == null:
		v.errors.append("[NU-6] %s: waves is not a WaveSet" % tag)
	if ws:
		check_waves(ws, ch.start_room, tag, v)


static func check_waves(ws: WaveSet, room_path: String, tag: String, v: ContentValidator) -> void:
	var room := _load(room_path)
	if room == null:
		v.errors.append("[NU-6] %s: wave room %s does not load" % [tag, room_path])
		return
	for i in ws.spawn_points():
		if room.get_node_or_null("WaveSpawns/WaveSpawn_%d" % i) == null:
			v.errors.append("[NU-6] %s: WaveSpawn_%d is missing in %s" % [tag, i, room_path.get_file()])
	if room.find_children("*", "WaveDirector", true, false).is_empty():
		v.errors.append("[NU-6] %s: %s has no WaveDirector" % [tag, room_path.get_file()])
	room.free()


## NU-4 over every Deep Rig boss variant scene.
static func check_variants(v: ContentValidator) -> void:
	for path in DataDir.list_scenes(VARIANT_DIR):
		var packed := load(path) as PackedScene
		var e := packed.instantiate() as Enemy if packed else null
		if e == null:
			v.errors.append("[NU-4] %s is not an Enemy scene" % path.get_file())
			continue
		check_variant(e, path, v)
		e.free()


static func check_variant(e: Enemy, path: String, v: ContentValidator) -> void:
	if e.data == null:
		v.errors.append("[NU-4] %s has no EnemyData" % path.get_file())
	else:
		for err in e.data.validate():
			v.errors.append("[NU-4] %s: %s" % [path.get_file(), err])
	var behavior := e.get_node_or_null("Behavior")
	var scale: Variant = behavior.get("phase2_telegraph_scale") if behavior else null
	if scale != null and float(scale) < TELEGRAPH_FLOOR:
		v.errors.append("[NU-4] %s: phase2_telegraph_scale %.2f is under the %.1f telegraph floor" % [path.get_file(), float(scale), TELEGRAPH_FLOOR])


## NU-5.
static func check_enemy_data(v: ContentValidator) -> void:
	for path in DataDir.list(ENEMY_DIR):
		if not path.get_file().get_basename().ends_with("_null"):
			continue
		var d := load(path) as EnemyData
		if d and d.scrap_drop != 0:
			v.errors.append("[NU-5] %s drops %d Scrap (the rig's enemies drop none)" % [path.get_file(), d.scrap_drop])


static func _load(path: String) -> Node:
	var packed := load(path) as PackedScene if path != "" and ResourceLoader.exists(path) else null
	return packed.instantiate() if packed else null
