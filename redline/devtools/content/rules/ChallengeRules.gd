class_name ChallengeRules
extends RefCounted
## Challenge content rules (M9 D2 §8.1, T08), run by ContentValidator's rule
## seam over EVERY data/challenges/*.tres (T10's Deep Rig and Pulse Pit files
## included). ChallengeData.validate() already covers the single-file schema;
## this module does the cross-file checks:
##   CH-1  ids unique; every ChallengeData in the folder loads
##   CH-2  start_room (and each stage room) exists and its entry is a
##         SpawnMarker there
##   CH-3  EXIT runs: finish_exit_target is a RoomExit.target_room in the
##         finish room (the finish line replaces that exit)
##   CH-4  boss_id (and each stage boss_id) matches a BossArena in the start
##         room or a stage room
##   CH-5  unlock_when / reveal_when / requires are valid and every flag they
##         read is produced by content (or code)
##   CH-6  kits: weapons and circuits exist in the catalog, the circuits fit
##         the Core capacity, every set/clear flag is produced by content (a
##         kit may not invent flags), reactor_mode -1..2
##   CH-7  medals: 4 values ordered for the score kind (not RANK)
##   CH-8  dev_bot != none: dev_ghost exists and its header matches
##   CH-9  staged runs: each stage room is off-map or a world room and holds
##         a ChallengeGoal with the stage id; waves (duck-typed, R08.13: no
##         T10 class names here) name scenes whose root is an Enemy
##   CH-10 TIME medals: Redline is at or above the rig ghost's frames, and a
##         boss run's Redline is at or above the theoretical floor (boss max
##         HP / best kit DPS + the retry intro)
##   CH-11 rank_ladder.tres has its 5 names (RankLadder.validate)
##   CH-12 kits never set transit_pass (a run never opens the Transit)
##   CH-13 (warning) Gold is closer than 3 s to Redline
##   CH-14 challenge_config.tres validates
##   CH-15 (warning) Silver is under Redline × silver_floor_mult +
##         silver_floor_add_s (Silver must stay reachable on short trials)
## Report: a table of id, group, unlock and rig ghost.

const DIR := "res://data/challenges"
## Gold may not sit closer to Redline than this (CH-13).
const GOLD_GAP_S := 3.0
## Kits may never set these (CH-12).
const FORBIDDEN_KIT_FLAGS: PackedStringArray = ["transit_pass"]

## [id, group title, unlock, dev ghost] of the last run (the report).
static var last_table: Array = []


static func run(v: ContentValidator) -> void:
	var list: Array[ChallengeData] = []
	var paths: Array[String] = []
	for path in DataDir.list(DIR):
		var res := load(path)
		if res is ChallengeData:
			list.append(res as ChallengeData)
			paths.append(path)
	var r := check_list(list, paths, v)
	v.errors.append_array(r["errors"])
	v.warnings.append_array(r["warnings"])
	for e in RankLadder.shared().validate():
		v.errors.append("[CH-11] rank_ladder.tres: " + e)
	var cfg := load(ChallengeConfig.PATH) as ChallengeConfig
	if cfg == null:
		v.errors.append("[CH-14] %s is missing or not a ChallengeConfig" % ChallengeConfig.PATH)
	else:
		for e in cfg.validate():
			v.errors.append("[CH-14] challenge_config.tres: " + e)


static func report(_v: ContentValidator) -> String:
	if last_table.is_empty():
		return ""
	var md := PackedStringArray(["## Challenges", "", "| id | group | unlock | rig ghost |", "|---|---|---|---|"])
	for row: Array in last_table:
		md.append("| %s | %s | %s | %s |" % row)
	return "\n".join(md)


## Every cross-file rule over `list` (paths[i] is list[i]'s file; tests pass
## fixtures). The flag checks read v.produced, so a real run calls this after
## the room and resource passes. Returns {errors, warnings}.
static func check_list(list: Array[ChallengeData], paths: Array[String], v: ContentValidator) -> Dictionary:
	var out := {"errors": PackedStringArray(), "warnings": PackedStringArray()}
	var rooms := {}
	var ids := {}
	last_table = []
	for i in list.size():
		var ch := list[i]
		var tag := paths[i].get_file() if i < paths.size() else ch.id
		if ids.has(ch.id):
			out["errors"].append("[CH-1] %s: id '%s' is also used by %s" % [tag, ch.id, ids[ch.id]])
		ids[ch.id] = tag
		_check_rooms(ch, tag, v, rooms, out)
		_check_conditions(ch, tag, v, out)
		if ch.kit:
			_check_kit(ch.kit, tag, v, out)
		for e in medal_errors(ch):
			out["errors"].append("[CH-7] %s: %s" % [tag, e])
		for e in ghost_errors(ch):
			out["errors"].append("[CH-8] %s: %s" % [tag, e])
		_check_waves(ch, tag, out)
		for e in floor_errors(ch, rooms, v):
			out["errors"].append("[CH-10] %s: %s" % [tag, e])
		for w in medal_warnings(ch):
			out["warnings"].append(w.insert(w.find("] ") + 2, tag + ": "))
		last_table.append([ch.id, ChallengeLibrary.group_title(ch.group), ch.unlock_when if ch.unlock_when != "" else "always",
			ch.dev_ghost.get_file() if ch.dev_ghost != "" else "none"])
	for n: Node in rooms.values():
		if is_instance_valid(n):
			n.free()
	return out


# --- CH-2/3/4/9: rooms ---------------------------------------------------------------

static func _room(path: String, v: ContentValidator, cache: Dictionary) -> Room:
	if not cache.has(path):
		cache[path] = v.instantiate_room(path) if ResourceLoader.exists(path) else null
	return cache[path] as Room


static func _check_rooms(ch: ChallengeData, tag: String, v: ContentValidator, cache: Dictionary, out: Dictionary) -> void:
	var room_paths: Array[String] = []
	var entries: Array[StringName] = []
	for i in ch.stage_count():
		room_paths.append(ch.stage_room(i))
		entries.append(ch.stage_entry(i))
	var boss_rooms: Array[Room] = []
	for i in room_paths.size():
		var path := room_paths[i]
		var room := _room(path, v, cache)
		if room == null:
			out["errors"].append("[CH-2] %s: room %s does not load as a Room" % [tag, path])
			continue
		boss_rooms.append(room)
		if not spawn_ids(room).has(entries[i]):
			out["errors"].append("[CH-2] %s: %s has no SpawnMarker '%s'" % [tag, path.get_file(), entries[i]])
		var st := ch.stage(i)
		if st:
			if not ContentValidator.OFF_MAP_DIRS.has(path.get_base_dir()) and not ContentValidator.WORLD_ROOM_DIRS.has(path.get_base_dir()):
				out["errors"].append("[CH-9] %s: stage %s room %s is neither off-map nor a world room" % [tag, st.id, path])
			var goal_found := false
			for g in room.find_children("*", "ChallengeGoal", true, false):
				if (g as ChallengeGoal).stage_id == st.id:
					goal_found = true
			if not goal_found:
				out["errors"].append("[CH-9] %s: %s has no ChallengeGoal for stage '%s'" % [tag, path.get_file(), st.id])
	if ch.end_on == ChallengeData.EndOn.EXIT:
		var fin := _room(ch.finish_room_path(), v, cache)
		if fin and not exit_targets(fin).has(ch.finish_exit_target):
			out["errors"].append("[CH-3] %s: %s has no RoomExit to %s" % [tag, ch.finish_room_path().get_file(), ch.finish_exit_target])
	var bosses := {}
	for r in boss_rooms:
		for id in boss_ids(r):
			bosses[id] = true
	var wanted: Array[String] = []
	if ch.boss_id != "":
		wanted.append(ch.boss_id)
	for s in ch.stages:
		if s and s.boss_id != "":
			wanted.append(s.boss_id)
	for id in wanted:
		if not bosses.has(id):
			out["errors"].append("[CH-4] %s: no BossArena with boss_id '%s' in its rooms" % [tag, id])


static func spawn_ids(room: Node) -> Array[StringName]:
	var out: Array[StringName] = []
	for n in room.find_children("*", "SpawnMarker", true, false):
		out.append((n as SpawnMarker).spawn_id)
	return out


static func exit_targets(room: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for n in room.find_children("*", "RoomExit", true, false):
		out.append((n as RoomExit).target_room)
	return out


static func boss_ids(room: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for n in room.find_children("*", "BossArena", true, false):
		out.append((n as BossArena).boss_id)
	return out


# --- CH-5/6/12: conditions and kits ------------------------------------------------

static func _produced(v: ContentValidator, flag: String) -> bool:
	return v.produced.has(flag) or ContentValidator.CODE_FLAGS.has(flag)


static func _check_conditions(ch: ChallengeData, tag: String, v: ContentValidator, out: Dictionary) -> void:
	for c in [ch.unlock_when, ch.reveal_when] + Array(ch.requires):
		var expr := String(c)
		if not ContentValidator.is_valid_condition(expr):
			out["errors"].append("[CH-5] %s: invalid condition '%s'" % [tag, expr])
			continue
		var e := expr.trim_prefix("!")
		if e.begins_with("flag:") or e.begins_with("atleast:"):
			var f := e.get_slice(":", 1)
			v.add_consumer(f, "res://data/challenges/" + tag)
			if not _produced(v, f):
				out["errors"].append("[CH-5] %s: condition '%s' reads flag '%s' that no content produces" % [tag, expr, f])


static func _check_kit(kit: ChallengeKit, tag: String, v: ContentValidator, out: Dictionary) -> void:
	var cat := load("res://data/catalog.tres") as ItemCatalog
	for e in kit.validate():
		out["errors"].append("[CH-6] %s: %s" % [tag, e])
	if cat:
		for w in [kit.melee, kit.ranged] + Array(kit.owned_weapons):
			if String(w) != "" and cat.weapon(String(w)) == null:
				out["errors"].append("[CH-6] %s: kit weapon '%s' is not in the catalog" % [tag, w])
		var cost := 0
		for c in kit.circuits:
			var cd := cat.circuit(c)
			if cd == null:
				out["errors"].append("[CH-6] %s: kit circuit '%s' is not in the catalog" % [tag, c])
			else:
				cost += int(cd.get("cost"))
		if not kit.use_profile_loadout and cost > cat.base_core_capacity + kit.core_shards:
			out["errors"].append("[CH-6] %s: kit circuits cost %d, capacity is %d" % [tag, cost, cat.base_core_capacity + kit.core_shards])
	for f in Array(kit.set_flags) + Array(kit.clear_flags):
		if not _produced(v, f):
			out["errors"].append("[CH-6] %s: kit flag '%s' is not produced by any content (kits may not invent flags)" % [tag, f])
	for f in kit.set_flags:
		if FORBIDDEN_KIT_FLAGS.has(f):
			out["errors"].append("[CH-12] %s: kits must not set '%s'" % [tag, f])


# --- CH-7/8/10/13/15: medals and ghosts ------------------------------------------------

static func medal_errors(ch: ChallengeData) -> PackedStringArray:
	var out := PackedStringArray()
	if ch.score_kind == ChallengeData.ScoreKind.RANK:
		return out
	var m := ch.medal_thresholds
	if m.size() != 4:
		out.append("medal_thresholds needs 4 values (Bronze, Silver, Gold, Redline)")
		return out
	for i in range(1, 4):
		var ordered := m[i] < m[i - 1] if ch.score_kind == ChallengeData.ScoreKind.TIME else m[i] > m[i - 1]
		if not ordered:
			out.append("medal thresholds are not strictly ordered for the score kind")
			break
	return out


static func ghost_errors(ch: ChallengeData) -> PackedStringArray:
	var out := PackedStringArray()
	if ch.dev_bot == &"none":
		return out
	if ch.dev_ghost == "":
		out.append("dev_bot %s but no dev_ghost (bake it with devtools/GhostBake.tscn)" % ch.dev_bot)
		return out
	var g := GhostCodec.load_file(ch.dev_ghost)
	if g == null:
		out.append("dev_ghost %s is missing or unreadable" % ch.dev_ghost)
	elif g.challenge != ch.id or g.revision != ch.revision:
		out.append("dev_ghost header is %s rev %d, the challenge is %s rev %d (re-bake)" % [g.challenge, g.revision, ch.id, ch.revision])
	return out


## CH-10: [frames] errors for a TIME challenge's Redline.
static func floor_errors(ch: ChallengeData, rooms: Dictionary, v: ContentValidator) -> PackedStringArray:
	var out := PackedStringArray()
	if ch.score_kind != ChallengeData.ScoreKind.TIME or ch.medal_thresholds.size() != 4:
		return out
	var redline := ch.medal_thresholds[3]
	if ch.dev_bot != &"none" and ch.dev_ghost != "":
		var g := GhostCodec.load_file(ch.dev_ghost)
		if g and g.frames > redline:
			out.append("Redline %d frames is under the rig ghost's %d (the top medal sits above the bot)" % [redline, g.frames])
	if ch.end_on == ChallengeData.EndOn.BOSS_DEFEATED and ch.boss_id != "":
		var room := _room(ch.start_room, v, rooms)
		var f := boss_floor_frames(ch, room)
		if f > 0 and redline < f:
			out.append("Redline %d frames is under the theoretical floor of %d (boss HP / best kit DPS + intro)" % [redline, f])
	return out


## The fastest conceivable kill: boss max HP over the kit's best weapon DPS
## (circuit damage multipliers applied), plus the retry intro the clock
## counts. 0 when it cannot be computed.
static func boss_floor_frames(ch: ChallengeData, room: Room) -> int:
	if room == null or ch.kit == null:
		return 0
	var arena: BossArena = null
	for n in room.find_children("*", "BossArena", true, false):
		if (n as BossArena).boss_id == ch.boss_id:
			arena = n as BossArena
	var boss := arena.get_node_or_null(arena.boss_path) as Enemy if arena else null
	if boss == null or boss.data == null:
		return 0
	var dps := best_kit_dps(ch.kit)
	if dps <= 0.0:
		return 0
	return int(ceil((boss.data.max_health / dps + arena.retry_intro_time) * RunClock.FPS))


static func best_kit_dps(kit: ChallengeKit) -> float:
	var cat := load("res://data/catalog.tres") as ItemCatalog
	if cat == null:
		return 0.0
	var melee_mult := 1.0
	var ranged_mult := 1.0
	for c in kit.circuits:
		var cd := cat.circuit(c)
		if cd:
			var mults: Dictionary = cd.get("multipliers")
			melee_mult *= float(mults.get("melee_damage", 1.0))
			ranged_mult *= float(mults.get("ranged_damage", 1.0))
	var best := 0.0
	for w in [kit.melee, kit.ranged] + Array(kit.owned_weapons):
		var wd := cat.weapon(String(w)) if String(w) != "" else null
		if wd:
			best = maxf(best, weapon_dps(wd) * (ranged_mult if wd.shot else melee_mult))
	return best


## Upper bound of one weapon's damage per second: a light chain cancelled
## as early as allowed, any single attack on repeat, or the shot rate
## (reloads ignored).
static func weapon_dps(w: WeaponData) -> float:
	var best := 0.0
	if w.shot and w.fire_interval > 0.0:
		best = w.shot.damage / w.fire_interval
	var chain_dmg := 0.0
	var chain_t := 0.0
	for a in w.light_chain:
		if a:
			chain_dmg += a.damage
			chain_t += _attack_time(a)
	if chain_t > 0.0:
		best = maxf(best, chain_dmg / chain_t)
	for a in [w.heavy, w.launcher, w.air_light, w.air_heavy]:
		if a and _attack_time(a) > 0.0:
			best = maxf(best, (a as AttackData).damage / _attack_time(a))
	return best


static func _attack_time(a: AttackData) -> float:
	return a.cancel_time if a.cancel_time > 0.0 else a.startup + a.active + a.recovery


## CH-13 and CH-15 (warnings), "[CH-n] text".
static func medal_warnings(ch: ChallengeData) -> PackedStringArray:
	var out := PackedStringArray()
	if ch.score_kind != ChallengeData.ScoreKind.TIME or ch.medal_thresholds.size() != 4:
		return out
	var m := ch.medal_thresholds
	if m[2] - m[3] < roundi(GOLD_GAP_S * RunClock.FPS):
		out.append("[CH-13] Gold %s is closer than %.1f s to Redline %s" % [RunClock.format(m[2]), GOLD_GAP_S, RunClock.format(m[3])])
	var cfg := ChallengeConfig.shared()
	var silver_floor := roundi(m[3] * cfg.silver_floor_mult + cfg.silver_floor_add_s * RunClock.FPS)
	if m[1] < silver_floor:
		out.append("[CH-15] Silver %s is under Redline × %.1f + %.1f s (%s): too tight to stay reachable" % [RunClock.format(m[1]),
			cfg.silver_floor_mult, cfg.silver_floor_add_s, RunClock.format(silver_floor)])
	return out


# --- CH-9: waves (duck-typed, R08.13) -----------------------------------------------

static func _check_waves(ch: ChallengeData, tag: String, out: Dictionary) -> void:
	if ch.waves == null:
		return
	var entries: Variant = ch.waves.get("entries")
	if not entries is Array:
		return
	for entry: Variant in entries:
		if not entry is Object:
			continue
		var scene_path := str((entry as Object).get("scene"))
		if scene_path == "" or not ResourceLoader.exists(scene_path):
			out["errors"].append("[CH-9] %s: wave scene '%s' does not exist" % [tag, scene_path])
			continue
		var packed := load(scene_path) as PackedScene
		var node := packed.instantiate() if packed else null
		if not node is Enemy:
			out["errors"].append("[CH-9] %s: wave scene %s is not an Enemy root" % [tag, scene_path])
		if node:
			node.free()
